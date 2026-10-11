data "terraform_remote_state" "platform" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "platform"
  }
}

locals {
  platform = data.terraform_remote_state.platform.outputs
}

data "google_client_config" "default" {}

data "google_container_cluster" "awx" {
  name     = local.platform.cluster_name
  location = local.platform.region
  project  = local.platform.project_id
}

provider "google" {
  project = local.platform.project_id
  region  = local.platform.region
}

provider "kubernetes" {
  host                   = "https://${data.google_container_cluster.awx.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(data.google_container_cluster.awx.master_auth[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = "https://${data.google_container_cluster.awx.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(data.google_container_cluster.awx.master_auth[0].cluster_ca_certificate)
  }
}

provider "kubectl" {
  host                   = "https://${data.google_container_cluster.awx.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(data.google_container_cluster.awx.master_auth[0].cluster_ca_certificate)
  load_config_file       = false
}
