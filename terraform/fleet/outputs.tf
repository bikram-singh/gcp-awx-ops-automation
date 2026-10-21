output "fleet" {
  description = "Fleet VMs with private IPs and the labels used for inventory grouping."
  value = {
    for name, vm in google_compute_instance.fleet : name => {
      zone       = vm.zone
      private_ip = vm.network_interface[0].network_ip
      labels     = vm.labels
    }
  }
}

output "awx_inventory_sa_email" {
  description = "Service account to create a key for, to use in the AWX Google Compute Engine credential."
  value       = google_service_account.awx_inventory.email
}
