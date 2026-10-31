resource "google_artifact_registry_repository" "this" {
  location      = var.region
  repository_id = var.name
  format        = "DOCKER"
  description   = "Lecture Indexer container images, tagged by commit SHA"
  labels        = var.labels

  # Keep storage (and cost) bounded: the last 10 versions of each image, plus
  # anything newer than 30 days.
  cleanup_policy_dry_run = false
  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }
  cleanup_policies {
    id     = "delete-old"
    action = "DELETE"
    condition {
      older_than = "2592000s"
    }
  }
}

resource "google_artifact_registry_repository_iam_member" "readers" {
  for_each   = var.readers
  location   = google_artifact_registry_repository.this.location
  repository = google_artifact_registry_repository.this.name
  role       = "roles/artifactregistry.reader"
  member     = each.value
}

resource "google_artifact_registry_repository_iam_member" "writers" {
  for_each   = var.writers
  location   = google_artifact_registry_repository.this.location
  repository = google_artifact_registry_repository.this.name
  role       = "roles/artifactregistry.writer"
  member     = each.value
}
