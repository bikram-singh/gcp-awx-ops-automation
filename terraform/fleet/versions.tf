terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # terraform init -backend-config="bucket=<state-bucket>"
  backend "gcs" {
    prefix = "fleet"
  }
}
