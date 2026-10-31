locals {
  services = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "sqladmin.googleapis.com",
    "run.googleapis.com",
    "servicenetworking.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "youtube.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
  ]

  # On every resource that takes labels, plus a `component`, so the consoles can
  # show and filter them. Azure tags use the same keys. GCP allows only lowercase
  # letters, digits, - and _ here. Scheme: docs/monitoring/dashboard-links.md.
  labels = {
    app         = "lecture-indexer"
    environment = "prod"
    managed-by  = "terraform"
  }
}

resource "google_project_service" "this" {
  for_each           = toset(local.services)
  service            = each.value
  disable_on_destroy = false
}

module "network" {
  source     = "../../modules/gcp-network"
  name       = var.name
  region     = var.gcp_region
  labels     = merge(local.labels, { component = "network" })
  depends_on = [google_project_service.this]
}

module "gke" {
  source              = "../../modules/gke"
  project_id          = var.gcp_project_id
  name                = var.name
  region              = var.gcp_region
  network_id          = module.network.network_id
  subnet_id           = module.network.subnet_id
  pods_range_name     = module.network.pods_range_name
  services_range_name = module.network.services_range_name
  labels              = merge(local.labels, { component = "api-cluster" })
}

module "artifact_registry" {
  source  = "../../modules/artifact-registry"
  name    = var.name
  region  = var.gcp_region
  readers = { gke-nodes = "serviceAccount:${module.gke.node_service_account}" }
  writers = { ci-deploy = "serviceAccount:${var.ci_deploy_service_account}" }
  labels  = merge(local.labels, { component = "container-images" })
  # The API is enabled in this same run; creating the repository first fails.
  depends_on = [google_project_service.this]
}

# The SPA on Cloud Run; why: docs/architecture_decision_records/0001-frontend-on-cloud-run.md.
# CI deploys revisions; Terraform owns the service, its access and its service account.
module "frontend" {
  source     = "../../modules/cloud-run-frontend"
  name       = "${var.name}-frontend"
  region     = var.gcp_region
  deployers  = { ci-deploy = "serviceAccount:${var.ci_deploy_service_account}" }
  labels     = merge(local.labels, { component = "frontend" })
  depends_on = [google_project_service.this]
}

# Ephemeral: generated during the run and passed only to write-only arguments,
# so the password never lands in Terraform state. It is applied when
# db_admin_password_version changes (bump it to rotate).
ephemeral "random_password" "db_admin" {
  length  = 32
  special = false
}

module "cloudsql" {
  source                 = "../../modules/cloudsql"
  name                   = "${var.name}-pg"
  region                 = var.gcp_region
  network_id             = module.network.network_id
  tier                   = var.cloudsql_tier
  admin_password         = ephemeral.random_password.db_admin.result
  admin_password_version = var.db_admin_password_version
  labels                 = merge(local.labels, { component = "database" })
  iam_service_accounts = {
    ingest = google_service_account.workload["ingest"].email
    search = google_service_account.workload["search"].email
  }
  depends_on = [module.network]
}

module "secrets" {
  source = "../../modules/secrets"
  labels = merge(local.labels, { component = "secrets" })
  secrets = {
    db-admin-password = {
      accessors = {
        migrate = google_service_account.workload["migrate"].member
        backup  = google_service_account.workload["backup"].member
      }
    }
  }
  secret_values = {
    db-admin-password = ephemeral.random_password.db_admin.result
  }
  secret_value_versions = {
    db-admin-password = var.db_admin_password_version
  }
  depends_on = [google_project_service.this]
}

# The upload SAS for backups. Terraform owns only the secret and who can read it:
# scripts/cloud-backup-sas.sh adds the value, so it never lands in state (ADR 0004).
resource "google_secret_manager_secret" "backup_sas" {
  secret_id = "backup-sas"
  labels    = merge(local.labels, { component = "secrets" })

  replication {
    auto {}
  }

  depends_on = [google_project_service.this]
}

resource "google_secret_manager_secret_iam_member" "backup_sas" {
  secret_id = google_secret_manager_secret.backup_sas.id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.workload["backup"].member
}

module "monitoring" {
  source               = "../../modules/monitoring"
  notification_channel = var.alert_notification_channel
  labels               = merge(local.labels, { component = "monitoring" })
  depends_on           = [google_project_service.this]
}

# The API's public address. Without a domain of our own, sslip.io maps
# <a-b-c-d>.sslip.io to a.b.c.d, which is enough for a Google-managed certificate.
resource "google_compute_global_address" "api" {
  name       = "${var.name}-api"
  labels     = merge(local.labels, { component = "api-load-balancer" })
  depends_on = [google_project_service.this]
}

locals {
  api_hostname = "${replace(google_compute_global_address.api.address, ".", "-")}.sslip.io"
}
