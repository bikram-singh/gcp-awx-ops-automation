resource "random_password" "db" {
  length  = 24
  special = false
}

resource "random_id" "db_suffix" {
  byte_length = 3
}

resource "google_sql_database_instance" "awx" {
  # Instance names cannot be reused for ~1 week after deletion, hence the suffix.
  name             = "${var.name_prefix}-pg-${random_id.db_suffix.hex}"
  region           = var.region
  database_version = "POSTGRES_15"

  deletion_protection = var.db_deletion_protection

  settings {
    tier              = var.db_tier
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = 20
    disk_autoresize   = true

    user_labels = var.labels

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = google_compute_network.vpc.id
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "21:00" # UTC, early morning in India
    }

    maintenance_window {
      day  = 7
      hour = 22
    }

    insights_config {
      query_insights_enabled = true
    }
  }

  depends_on = [google_service_networking_connection.private_services]
}

resource "google_sql_database" "awx" {
  name     = "awx"
  instance = google_sql_database_instance.awx.name
}

resource "google_sql_user" "awx" {
  name     = "awx"
  instance = google_sql_database_instance.awx.name
  password = random_password.db.result
}

resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.name_prefix}-db-password"
  labels    = var.labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db.result
}
