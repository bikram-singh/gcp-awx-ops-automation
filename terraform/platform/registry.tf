# Private image registry for the custom AWX execution environment (built by .github/workflows/ee-build.yml).
# The GKE node service account already has roles/artifactregistry.reader (see gke.tf), so AWX job pods
# can pull from it without any stored credential.
resource "google_artifact_registry_repository" "awx_ee" {
  project       = var.project_id
  location      = var.region
  repository_id = "awx-ee"
  description   = "Custom AWX execution environment images"
  format        = "DOCKER"

  depends_on = [google_project_service.apis]
}
