output "project_id" {
  value = var.project_id
}

output "region" {
  value = var.region
}

output "network_name" {
  value = google_compute_network.vpc.name
}

output "subnet_name" {
  value = google_compute_subnetwork.main.name
}

output "cluster_name" {
  value = google_container_cluster.awx.name
}

output "db_private_ip" {
  value = google_sql_database_instance.awx.private_ip_address
}

output "db_name" {
  value = google_sql_database.awx.name
}

output "db_user" {
  value = google_sql_user.awx.name
}

output "db_password_secret_id" {
  description = "Secret Manager secret holding the AWX database password."
  value       = google_secret_manager_secret.db_password.secret_id
}
