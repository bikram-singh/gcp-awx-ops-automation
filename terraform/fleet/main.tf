data "terraform_remote_state" "platform" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "platform"
  }
}

locals {
  platform   = data.terraform_remote_state.platform.outputs
  project_id = local.platform.project_id
  region     = local.platform.region
}

provider "google" {
  project = local.project_id
  region  = local.region
}

data "google_compute_image" "debian" {
  family  = "debian-12"
  project = "debian-cloud"
}

# Identity attached to the fleet VMs: logging and metrics only.
resource "google_service_account" "vm" {
  account_id   = "awxplat-fleet-vm"
  display_name = "Managed fleet VMs"
}

resource "google_project_iam_member" "vm" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ])

  project = local.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.vm.email}"
}

# Read-only identity for the AWX GCE inventory sync (compute.viewer only).
# Create a key for it manually and paste it into an AWX credential; see docs/PHASE2.md.
resource "google_service_account" "awx_inventory" {
  account_id   = "awx-inventory"
  display_name = "AWX dynamic inventory (read-only)"
}

resource "google_project_iam_member" "awx_inventory" {
  project = local.project_id
  role    = "roles/compute.viewer"
  member  = "serviceAccount:${google_service_account.awx_inventory.email}"
}

resource "google_compute_instance" "fleet" {
  for_each = var.fleet

  name         = each.key
  machine_type = var.vm_machine_type
  zone         = "${local.region}-${each.value.zone}"

  tags = ["ansible-managed", each.value.role]

  labels = merge(var.labels, {
    env             = each.value.env
    role            = each.value.role
    patch_group     = each.value.patch_group
    ansible_managed = "true"
  })

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian.self_link
      size  = 20
      type  = "pd-balanced"
    }
  }

  # No access_config block: private IP only. Egress goes through Cloud NAT.
  network_interface {
    subnetwork         = local.platform.subnet_name
    subnetwork_project = local.project_id
  }

  service_account {
    email  = google_service_account.vm.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  # Creates the 'ansible' user with key-based SSH and passwordless sudo. Runs at every boot (idempotent).
  metadata = {
    startup-script = templatefile("${path.module}/startup.sh.tpl", {
      ssh_public_key = trimspace(var.ssh_public_key)
    })
  }

  allow_stopping_for_update = true

  depends_on = [google_project_iam_member.vm]
}
