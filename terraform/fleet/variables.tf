variable "state_bucket" {
  description = "GCS bucket that holds the platform stack state."
  type        = string
}

variable "ssh_public_key" {
  description = "Public key for the 'ansible' user on every VM. The matching private key goes into an AWX Machine credential."
  type        = string
}

variable "vm_machine_type" {
  description = "Machine type for fleet VMs."
  type        = string
  default     = "e2-small"
}

variable "fleet" {
  description = "VMs to create. Labels drive the AWX dynamic inventory groups (env_*, role_*, patch_*)."
  type = map(object({
    env         = string
    role        = string
    patch_group = string
    zone        = string # zone suffix: a, b or c
  }))
  default = {
    "web-dev-01"  = { env = "dev", role = "web", patch_group = "a", zone = "a" }
    "web-dev-02"  = { env = "dev", role = "web", patch_group = "b", zone = "b" }
    "app-dev-01"  = { env = "dev", role = "app", patch_group = "a", zone = "a" }
    "db-dev-01"   = { env = "dev", role = "db", patch_group = "b", zone = "b" }
    "web-prod-01" = { env = "prod", role = "web", patch_group = "a", zone = "a" }
    "app-prod-01" = { env = "prod", role = "app", patch_group = "b", zone = "b" }
    "app-dev-02"  = { env = "dev", role = "app", patch_group = "a", zone = "a" }
  }
}

variable "labels" {
  description = "Labels applied to every VM, in addition to env/role/patch_group."
  type        = map(string)
  default = {
    project    = "awx-ops-platform"
    managed_by = "terraform"
  }
}
