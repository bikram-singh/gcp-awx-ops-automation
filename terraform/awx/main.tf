data "google_secret_manager_secret_version" "db_password" {
  project = local.platform.project_id
  secret  = local.platform.db_password_secret_id
}

resource "kubernetes_namespace" "awx" {
  metadata {
    name = var.awx_namespace
  }
}

# External database configuration consumed by the AWX operator.
resource "kubernetes_secret" "awx_postgres" {
  metadata {
    name      = "awx-postgres-configuration"
    namespace = kubernetes_namespace.awx.metadata[0].name
  }

  data = {
    host     = local.platform.db_private_ip
    port     = "5432"
    database = local.platform.db_name
    username = local.platform.db_user
    password = data.google_secret_manager_secret_version.db_password.secret_data
    sslmode  = "prefer"
    type     = "unmanaged"
  }

  type = "Opaque"
}

resource "helm_release" "awx_operator" {
  name       = "awx-operator"
  namespace  = kubernetes_namespace.awx.metadata[0].name
  repository = "https://ansible-community.github.io/awx-operator-helm/"
  chart      = "awx-operator"
  version    = var.awx_operator_chart_version

  wait    = true
  timeout = 600

  # The chart's default sidecar image (gcr.io/kubebuilder/kube-rbac-proxy) no longer
  # exists, which leaves the operator pod in ImagePullBackOff. Override it.
  values = [
    yamlencode({
      "operator-controller-containers" = {
        "kube-rbac-proxy" = {
          image = var.kube_rbac_proxy_image
        }
      }
    })
  ]

}

resource "kubectl_manifest" "awx" {
  yaml_body = yamlencode({
    apiVersion = "awx.ansible.com/v1beta1"
    kind       = "AWX"
    metadata = {
      name      = "awx"
      namespace = kubernetes_namespace.awx.metadata[0].name
    }
    spec = {
      admin_user                    = var.awx_admin_user
      replicas                      = var.awx_replicas
      postgres_configuration_secret = kubernetes_secret.awx_postgres.metadata[0].name
      service_type                  = "ClusterIP"
      ingress_type                  = "none"
      web_resource_requirements = {
        requests = { cpu = "250m", memory = "512Mi" }
        limits   = { cpu = "1", memory = "2Gi" }
      }
      task_resource_requirements = {
        requests = { cpu = "500m", memory = "1Gi" }
        limits   = { cpu = "2", memory = "4Gi" }
      }
      ee_resource_requirements = {
        requests = { cpu = "250m", memory = "256Mi" }
        limits   = { cpu = "1", memory = "1Gi" }
      }
    }
  })

  server_side_apply = true
  wait_for_rollout  = false

  depends_on = [
    helm_release.awx_operator,
    kubernetes_secret.awx_postgres,
  ]
}
