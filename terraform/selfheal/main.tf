locals {
  project_id = local.platform.project_id
}

resource "google_project_service" "pubsub" {
  project            = local.project_id
  service            = "pubsub.googleapis.com"
  disable_on_destroy = false
}

# Events flow: audit log (VM stopped) -> log sink -> this topic -> subscription -> bridge (pull) -> AWX.
# The bridge pulls, so AWX never needs a public or load-balanced address.
resource "google_pubsub_topic" "events" {
  project = local.project_id
  name    = "awx-selfheal-events"

  depends_on = [google_project_service.pubsub]
}

resource "google_pubsub_subscription" "bridge" {
  project = local.project_id
  name    = "awx-selfheal-bridge"
  topic   = google_pubsub_topic.events.id

  ack_deadline_seconds       = 60
  message_retention_duration = "3600s" # a stop event older than an hour is not worth acting on

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }

  expiration_policy {
    ttl = "" # never expire
  }
}

# Completed "stop VM" calls on the managed fleet, from the Admin Activity audit log (always on, free).
resource "google_logging_project_sink" "vm_stop" {
  project                = local.project_id
  name                   = "awx-selfheal-vm-stop"
  destination            = "pubsub.googleapis.com/${google_pubsub_topic.events.id}"
  unique_writer_identity = true

  filter = <<-EOT
    protoPayload.serviceName="compute.googleapis.com"
    protoPayload.methodName:"compute.instances.stop"
    operation.last=true
    protoPayload.resourceName=~"/instances/${var.vm_name_regex}$"
  EOT
}

resource "google_pubsub_topic_iam_member" "sink_publisher" {
  project = local.project_id
  topic   = google_pubsub_topic.events.name
  role    = "roles/pubsub.publisher"
  member  = google_logging_project_sink.vm_stop.writer_identity
}

# Identity of the bridge pod (Workload Identity, no key): may pull from this one subscription and nothing else.
resource "google_service_account" "bridge" {
  project      = local.project_id
  account_id   = "awx-selfheal-bridge"
  display_name = "AWX self-heal bridge (Pub/Sub subscriber)"
}

resource "google_pubsub_subscription_iam_member" "bridge_subscriber" {
  project      = local.project_id
  subscription = google_pubsub_subscription.bridge.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${google_service_account.bridge.email}"
}

resource "google_service_account_iam_member" "bridge_workload_identity" {
  service_account_id = google_service_account.bridge.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.project_id}.svc.id.goog[${var.awx_namespace}/selfheal-bridge]"
}

# Credential the bridge uses against AWX. The same password is applied to the AWX user "selfheal"
# by the awx-config workflow (which reads this secret), and that user may only run the heal template.
resource "random_password" "bridge" {
  length  = 32
  special = false
}

resource "kubernetes_secret" "bridge" {
  metadata {
    name      = "selfheal-bridge"
    namespace = var.awx_namespace
  }

  data = {
    username = "selfheal"
    password = random_password.bridge.result
  }

  type = "Opaque"
}

resource "kubernetes_service_account" "bridge" {
  metadata {
    name      = "selfheal-bridge"
    namespace = var.awx_namespace
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.bridge.email
    }
  }
}

resource "kubernetes_config_map" "bridge" {
  metadata {
    name      = "selfheal-bridge-code"
    namespace = var.awx_namespace
  }

  data = {
    "bridge.py" = file("${path.module}/bridge.py")
  }
}

resource "kubernetes_deployment" "bridge" {
  metadata {
    name      = "selfheal-bridge"
    namespace = var.awx_namespace
    labels = {
      app = "selfheal-bridge"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "selfheal-bridge"
      }
    }

    template {
      metadata {
        labels = {
          app = "selfheal-bridge"
        }
        annotations = {
          "checksum/code" = sha256(file("${path.module}/bridge.py"))
        }
      }

      spec {
        service_account_name = kubernetes_service_account.bridge.metadata[0].name

        container {
          name    = "bridge"
          image   = var.bridge_image
          command = ["python", "-u", "/app/bridge.py"]

          env {
            name  = "GCP_PROJECT"
            value = local.project_id
          }
          env {
            name  = "PUBSUB_SUBSCRIPTION"
            value = google_pubsub_subscription.bridge.name
          }
          env {
            name  = "AWX_URL"
            value = "http://awx-service.${var.awx_namespace}.svc.cluster.local"
          }
          env {
            name  = "AWX_TEMPLATE"
            value = var.heal_template_name
          }
          env {
            name = "AWX_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.bridge.metadata[0].name
                key  = "username"
              }
            }
          }
          env {
            name = "AWX_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.bridge.metadata[0].name
                key  = "password"
              }
            }
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "64Mi"
            }
          }

          security_context {
            run_as_non_root            = true
            run_as_user                = 65534
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "code"
            mount_path = "/app"
            read_only  = true
          }
        }

        volume {
          name = "code"
          config_map {
            name = kubernetes_config_map.bridge.metadata[0].name
          }
        }
      }
    }
  }
}
