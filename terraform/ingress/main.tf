# Optional public HTTPS entry to AWX: global load balancer, Google-managed certificate, Cloud Armor allowlist.
# Nothing is created until a domain AND at least one allowed address range are set (see docs/INGRESS.md).
# GitHub Actions keeps using the private port-forward; this is only for people.
locals {
  project_id  = local.platform.project_id
  enabled     = var.domain != "" && length(var.allowed_cidrs) > 0
  cidr_chunks = chunklist(var.allowed_cidrs, 10) # Cloud Armor allows 10 ranges per rule
}

resource "terraform_data" "guard" {
  lifecycle {
    precondition {
      condition     = var.domain == "" || length(var.allowed_cidrs) > 0
      error_message = "A domain is set but allowed_cidrs is empty. Refusing to put AWX on the internet without an allowlist."
    }
  }
}

resource "google_compute_global_address" "awx" {
  count   = local.enabled ? 1 : 0
  project = local.project_id
  name    = "awx-ingress-ip"
}

resource "google_compute_managed_ssl_certificate" "awx" {
  count   = local.enabled ? 1 : 0
  project = local.project_id
  name    = "awx-cert"

  managed {
    domains = [var.domain]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_security_policy" "awx" {
  count       = local.enabled ? 1 : 0
  project     = local.project_id
  name        = "awx-allowlist"
  description = "Only listed source addresses may reach AWX"

  dynamic "rule" {
    for_each = local.cidr_chunks
    content {
      action      = "allow"
      priority    = 1000 + rule.key
      description = "Allowed source ranges ${rule.key + 1}"
      match {
        versioned_expr = "SRC_IPS_V1"
        config {
          src_ip_ranges = rule.value
        }
      }
    }
  }

  rule {
    action      = "deny(403)"
    priority    = 2147483647
    description = "Default: deny"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }
}

# Reuse the selector and port of the Service the AWX operator already created.
data "kubernetes_service_v1" "awx" {
  count = local.enabled ? 1 : 0

  metadata {
    name      = "awx-service"
    namespace = var.awx_namespace
  }
}

# Health check, long timeout (job output streams over a websocket) and the Cloud Armor policy.
resource "kubectl_manifest" "backend_config" {
  count = local.enabled ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "cloud.google.com/v1"
    kind       = "BackendConfig"
    metadata = {
      name      = "awx-backend"
      namespace = var.awx_namespace
    }
    spec = {
      timeoutSec         = 3600
      connectionDraining = { drainingTimeoutSec = 60 }
      healthCheck = {
        type               = "HTTP"
        requestPath        = "/api/v2/ping/"
        checkIntervalSec   = 15
        timeoutSec         = 5
        healthyThreshold   = 1
        unhealthyThreshold = 3
      }
      securityPolicy = { name = google_compute_security_policy.awx[0].name }
    }
  })
}

resource "kubernetes_service_v1" "web" {
  count = local.enabled ? 1 : 0

  metadata {
    name      = "awx-web-lb"
    namespace = var.awx_namespace
    annotations = {
      "cloud.google.com/neg"            = jsonencode({ ingress = true })
      "cloud.google.com/backend-config" = jsonencode({ default = "awx-backend" })
    }
  }

  spec {
    type     = "ClusterIP"
    selector = data.kubernetes_service_v1.awx[0].spec[0].selector

    port {
      name        = "http"
      port        = 80
      target_port = data.kubernetes_service_v1.awx[0].spec[0].port[0].target_port
    }
  }

  depends_on = [kubectl_manifest.backend_config]
}

resource "kubernetes_ingress_v1" "awx" {
  count = local.enabled ? 1 : 0

  metadata {
    name      = "awx"
    namespace = var.awx_namespace
    annotations = {
      "kubernetes.io/ingress.class"                 = "gce"
      "kubernetes.io/ingress.global-static-ip-name" = google_compute_global_address.awx[0].name
      "ingress.gcp.kubernetes.io/pre-shared-cert"   = google_compute_managed_ssl_certificate.awx[0].name
      "kubernetes.io/ingress.allow-http"            = "false"
    }
  }

  spec {
    default_backend {
      service {
        name = kubernetes_service_v1.web[0].metadata[0].name
        port {
          number = 80
        }
      }
    }
  }

  wait_for_load_balancer = false
}
