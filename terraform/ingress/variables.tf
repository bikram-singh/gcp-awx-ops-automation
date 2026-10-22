variable "state_bucket" {
  description = "GCS bucket that holds the platform stack state (same bucket as this stack's backend)."
  type        = string
}

variable "awx_namespace" {
  description = "Kubernetes namespace where AWX runs."
  type        = string
  default     = "awx"
}

variable "domain" {
  description = "Public host name for AWX, for example awx.gcpcloudhub.in. Empty (the default) creates nothing."
  type        = string
  default     = ""
}

variable "allowed_cidrs" {
  description = "Source IP ranges allowed to reach AWX (Cloud Armor allowlist), for example [\"203.0.113.10/32\"]. Required when domain is set; 0.0.0.0/0 is refused."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.allowed_cidrs : can(cidrnetmask(c))])
    error_message = "Every entry must be an IPv4 range in CIDR form, for example 203.0.113.10/32."
  }

  validation {
    condition     = !contains(var.allowed_cidrs, "0.0.0.0/0")
    error_message = "0.0.0.0/0 would put AWX open on the internet. List your own addresses instead."
  }
}
