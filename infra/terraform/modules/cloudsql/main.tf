# Smallest Cloud SQL Postgres: shared-core, zonal, private IP only.
# Apps log in as IAM users (no passwords) through the Cloud SQL Auth Proxy;
# only the migrate Job uses the built-in admin user, whose password lives in
# Secret Manager.

resource "google_sql_database_instance" "this" {
  name                = var.name
  region              = var.region
  database_version    = "POSTGRES_16"
  deletion_protection = false

  settings {
    tier              = var.tier
    edition           = "ENTERPRISE"
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = 10

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    # Off to save cost; the nightly pg_dump to Azure Blob is the backup (step 5).
    backup_configuration {
      enabled = false
    }

    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }

    # Free on Enterprise edition; feeds the "database load" dashboard panel.
    insights_config {
      query_insights_enabled = true
    }
  }
}

resource "google_sql_database" "app" {
  name     = var.database_name
  instance = google_sql_database_instance.this.name
}

resource "google_sql_user" "admin" {
  name                = var.admin_username
  instance            = google_sql_database_instance.this.name
  password_wo         = var.admin_password
  password_wo_version = var.admin_password_version
}

# Cloud SQL names IAM service-account users by the email minus ".gserviceaccount.com".
resource "google_sql_user" "iam" {
  for_each = var.iam_service_accounts
  name     = trimsuffix(each.value, ".gserviceaccount.com")
  instance = google_sql_database_instance.this.name
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}
