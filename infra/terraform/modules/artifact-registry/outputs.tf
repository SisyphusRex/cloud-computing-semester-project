output "repository_url" {
  description = "Image prefix, e.g. us-central1-docker.pkg.dev/<project>/li."
  value       = "${var.region}-docker.pkg.dev/${google_artifact_registry_repository.this.project}/${google_artifact_registry_repository.this.repository_id}"
}
