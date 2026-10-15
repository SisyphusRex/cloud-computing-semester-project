# GKE Autopilot: Google manages nodes; we pay per pod request (Spot pods for
# workloads that tolerate it). Workload Identity is always on in Autopilot.

resource "google_service_account" "nodes" {
  account_id   = "${var.name}-nodes"
  display_name = "GKE nodes (${var.name})"
}

# Minimum node permissions instead of the default compute SA's Editor.
resource "google_project_iam_member" "nodes" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/autoscaling.metricsWriter",
  ])
  project = var.project_id
  role    = each.value
  member  = google_service_account.nodes.member
}

resource "google_container_cluster" "this" {
  name     = var.name
  location = var.region

  enable_autopilot    = true
  deletion_protection = false

  network    = var.network_id
  subnetwork = var.subnet_id

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # Nodes get no public IPs. The control plane keeps a public endpoint so
  # GitHub-hosted runners can deploy; access still requires IAM.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
  }

  release_channel {
    channel = "REGULAR"
  }

  cluster_autoscaling {
    auto_provisioning_defaults {
      service_account = google_service_account.nodes.email
      oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    }
  }

  # Mounts Secret Manager secrets into pods as files.
  secret_manager_config {
    enabled = true
  }

  depends_on = [google_project_iam_member.nodes]
}
