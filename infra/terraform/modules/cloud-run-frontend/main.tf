# The React SPA as an nginx container on Cloud Run: public, scales to zero.
# Terraform creates the service with a placeholder image; the frontend deploy
# workflow ships each revision with `gcloud run deploy`.

# Runs the container. nginx serves static files and calls nothing, so it
# gets no roles.
resource "google_service_account" "this" {
  account_id   = var.name
  display_name = "Lecture Indexer frontend (Cloud Run)"
}

resource "google_cloud_run_v2_service" "this" {
  name                = var.name
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  template {
    service_account = google_service_account.this.email

    scaling {
      min_instance_count = 0
      max_instance_count = var.max_instances
    }

    containers {
      image = var.placeholder_image
      ports {
        container_port = 8080
      }
      resources {
        limits   = { cpu = "1", memory = "256Mi" }
        cpu_idle = true
      }
    }
  }

  # CI deploys the real image (and gcloud sets client fields and revision
  # labels), and moves traffic only after checking the new revision
  # (scripts/ci/deploy-frontend.sh); an apply must not undo either.
  lifecycle {
    ignore_changes = [
      client,
      client_version,
      traffic,
      template[0].containers[0].image,
      template[0].labels,
      template[0].annotations,
      template[0].revision,
    ]
  }
}

# A public website.
resource "google_cloud_run_v2_service_iam_member" "public" {
  name     = google_cloud_run_v2_service.this.name
  location = google_cloud_run_v2_service.this.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Deployers may update this one service, and run it as its service account.
resource "google_cloud_run_v2_service_iam_member" "deployers" {
  for_each = var.deployers
  name     = google_cloud_run_v2_service.this.name
  location = google_cloud_run_v2_service.this.location
  role     = "roles/run.developer"
  member   = each.value
}

resource "google_service_account_iam_member" "deployers" {
  for_each           = var.deployers
  service_account_id = google_service_account.this.name
  role               = "roles/iam.serviceAccountUser"
  member             = each.value
}
