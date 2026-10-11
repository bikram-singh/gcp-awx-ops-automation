output "namespace" {
  value = kubernetes_namespace.awx.metadata[0].name
}

output "port_forward_command" {
  description = "Reach the AWX UI locally until managed ingress is added."
  value       = "kubectl -n ${kubernetes_namespace.awx.metadata[0].name} port-forward svc/awx-service 8080:80"
}

output "admin_password_command" {
  description = "Read the generated AWX admin password."
  value       = "kubectl -n ${kubernetes_namespace.awx.metadata[0].name} get secret awx-admin-password -o jsonpath='{.data.password}' | base64 -d"
}
