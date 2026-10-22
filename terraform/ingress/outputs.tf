output "enabled" {
  description = "True when the public entry exists."
  value       = local.enabled
}

output "ip_address" {
  description = "Create a DNS A record for the domain that points here."
  value       = try(google_compute_global_address.awx[0].address, null)
}

output "url" {
  value = local.enabled ? "https://${var.domain}" : null
}
