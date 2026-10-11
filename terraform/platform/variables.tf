variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region for all regional resources."
  type        = string
  default     = "asia-south1"
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "awxplat"
}

variable "subnet_cidr" {
  description = "Primary subnet range (GKE nodes, fleet VMs)."
  type        = string
  default     = "10.10.0.0/20"
}

variable "pods_cidr" {
  description = "Secondary range for GKE pods."
  type        = string
  default     = "10.20.0.0/16"
}

variable "services_cidr" {
  description = "Secondary range for GKE services."
  type        = string
  default     = "10.30.0.0/20"
}

variable "gke_master_cidr" {
  description = "Private /28 for the GKE control plane peering."
  type        = string
  default     = "172.16.0.0/28"
}

variable "master_authorized_cidrs" {
  description = "CIDRs allowed to reach the GKE control-plane endpoint. Lab only: tighten for production."
  type = list(object({
    cidr         = string
    display_name = string
  }))
  default = []
}

variable "gke_machine_type" {
  description = "Machine type for GKE nodes. AWX needs roughly 4 vCPU / 16 GB for a comfortable lab."
  type        = string
  default     = "e2-standard-4"
}

variable "gke_min_nodes" {
  description = "Minimum nodes per zone in the node pool."
  type        = number
  default     = 1
}

variable "gke_max_nodes" {
  description = "Maximum nodes per zone in the node pool."
  type        = number
  default     = 2
}

variable "db_tier" {
  description = "Cloud SQL machine tier."
  type        = string
  default     = "db-custom-2-7680"
}

variable "db_deletion_protection" {
  description = "Protect the Cloud SQL instance from deletion. Set false for lab teardown."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels applied to supported resources."
  type        = map(string)
  default = {
    project    = "awx-ops-platform"
    managed_by = "terraform"
  }
}
