variable "state_bucket" {
  description = "GCS bucket that holds the platform stack state (same bucket as this stack's backend)."
  type        = string
}

variable "awx_namespace" {
  description = "Kubernetes namespace where AWX runs. The bridge runs next to it."
  type        = string
  default     = "awx"
}

variable "heal_template_name" {
  description = "AWX job template the bridge launches when a managed VM is stopped. Must match awx_config.yml."
  type        = string
  default     = "40 Heal: start stopped VM"
}

variable "vm_name_regex" {
  description = "Regex (RE2) for the names of VMs that trigger self-healing. Keeps GKE nodes and other VMs out."
  type        = string
  default     = "(web|app|db)-(dev|prod)-[0-9]+"
}

variable "bridge_image" {
  description = "Image for the bridge. Any image with Python 3.9+ works; the code comes from a ConfigMap. mirror.gcr.io avoids Docker Hub rate limits."
  type        = string
  default     = "mirror.gcr.io/library/python:3.12-slim"
}
