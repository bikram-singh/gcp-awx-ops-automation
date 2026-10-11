variable "state_bucket" {
  description = "GCS bucket that holds the platform stack state (same bucket as this stack's backend)."
  type        = string
}

variable "awx_namespace" {
  description = "Kubernetes namespace for AWX and the operator."
  type        = string
  default     = "awx"
}

variable "awx_operator_chart_version" {
  description = "Version of the awx-operator Helm chart. Pin it; check the chart repo for the latest."
  type        = string
  default     = "2.19.1"
}

variable "awx_admin_user" {
  description = "AWX admin username."
  type        = string
  default     = "admin"
}

variable "awx_replicas" {
  description = "Number of AWX web/task replicas."
  type        = number
  default     = 1
}
