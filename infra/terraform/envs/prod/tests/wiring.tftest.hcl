# Runs the whole configuration against mocked providers: no credentials, no
# real resources. Checks the values that later steps depend on.
#   terraform -chdir=infra/terraform/envs/prod test

mock_provider "google" {
  mock_resource "google_service_account" {
    defaults = {
      email  = "li-workload@li-test.iam.gserviceaccount.com"
      member = "serviceAccount:li-workload@li-test.iam.gserviceaccount.com"
      name   = "projects/li-test/serviceAccounts/li-workload@li-test.iam.gserviceaccount.com"
    }
  }
  mock_resource "google_compute_network" {
    defaults = {
      id = "projects/li-test/global/networks/li"
    }
  }
  mock_resource "google_compute_global_address" {
    defaults = {
      address = "34.120.1.2"
    }
  }
  mock_resource "google_sql_database_instance" {
    defaults = {
      connection_name = "li-test:us-central1:li-pg"
    }
  }
  mock_resource "google_secret_manager_secret" {
    defaults = {
      id = "projects/li-test/secrets/db-admin-password"
    }
  }
  mock_resource "google_cloud_run_v2_service" {
    defaults = {
      uri = "https://li-frontend-abc123-uc.a.run.app"
    }
  }
  mock_resource "google_artifact_registry_repository" {
    defaults = {
      project = "li-test"
    }
  }
}

mock_provider "azurerm" {}

# The real random provider: it needs no credentials, and mocks can't
# provide ephemeral resources.

variables {
  gcp_project_id            = "li-test"
  azure_subscription_id     = "00000000-0000-0000-0000-000000000000"
  ci_deploy_service_account = "github-deploy@li-test.iam.gserviceaccount.com"
}

run "wiring" {
  command = apply

  assert {
    condition     = output.api_hostname == "34-120-1-2.sslip.io"
    error_message = "API hostname should be the sslip.io form of the static IP"
  }

  assert {
    condition     = output.frontend_url == "https://li-frontend-abc123-uc.a.run.app"
    error_message = "frontend_url should be the Cloud Run service's URL"
  }

  assert {
    condition     = module.frontend.name == "li-frontend"
    error_message = "unexpected Cloud Run service name"
  }

  assert {
    condition     = output.image_repository == "us-central1-docker.pkg.dev/li-test/li"
    error_message = "unexpected Artifact Registry URL"
  }

  assert {
    condition     = output.migrate_grants == "li_ingest_role=li-workload@li-test.iam,li_search_role=li-workload@li-test.iam"
    error_message = "IAM database users must drop the .gserviceaccount.com suffix"
  }

  assert {
    condition     = toset(keys(output.workload_service_accounts)) == toset(["ingest", "search", "migrate", "backup"])
    error_message = "expected one service account per workload"
  }

  assert {
    condition = alltrue([
      for k, b in google_service_account_iam_member.workload_identity :
      b.member == "serviceAccount:li-test.svc.id.goog[li/${k}]"
    ])
    error_message = "Workload Identity must bind each GSA to li/<workload> only"
  }

  assert {
    condition     = !contains([for k, v in google_project_iam_member.workload : k], "migrate/roles/cloudsql.instanceUser")
    error_message = "migrate logs in with the built-in admin user, not IAM"
  }

  assert {
    condition     = !contains([for k, v in google_project_iam_member.workload : k], "backup/roles/cloudsql.instanceUser")
    error_message = "backup logs in with the built-in admin user, not IAM"
  }

  assert {
    condition     = length(module.cloudsql.iam_usernames) == 2
    error_message = "only ingest and search get IAM database users"
  }

  # The Grafana dashboard refers to these by name.
  assert {
    condition = toset(module.monitoring.log_metric_names) == toset([
      "app_errors", "backup_bytes", "backup_failed", "backup_succeeded", "ingest_failed", "ingest_succeeded",
      "search_failed", "searches",
    ])
    error_message = "unexpected log-based metrics"
  }
}

run "frontend_access" {
  command = apply

  # Public site: anyone may invoke it, and that's all anyone gets.
  assert {
    condition     = module.frontend.public_member == "allUsers" && module.frontend.public_role == "roles/run.invoker"
    error_message = "the frontend must be public with run.invoker only"
  }

  # CI deploys this service only: run.developer on the service, not the project.
  assert {
    condition = (
      module.frontend.deployer_bindings == { ci-deploy = "serviceAccount:github-deploy@li-test.iam.gserviceaccount.com" }
      && !anytrue([for k, v in google_project_iam_member.workload : v.role == "roles/run.developer"])
    )
    error_message = "the deploy SA should get run.developer on the frontend service only"
  }
}

run "no_secrets_in_state" {
  command = apply

  assert {
    condition     = toset(keys(module.secrets.secret_ids)) == toset(["db-admin-password"])
    error_message = "unexpected secrets"
  }

  # Read-only PR plans can read state, so it must not hold the admin password.
  assert {
    condition     = module.cloudsql.admin_password_in_state == null
    error_message = "li_admin's password must be write-only"
  }

  assert {
    condition     = module.secrets.values_in_state == {}
    error_message = "secret values must be write-only"
  }

  # Only the secret: its value is added outside Terraform, so it's never in state.
  assert {
    condition     = google_secret_manager_secret_iam_member.backup_sas.member == google_service_account.workload["backup"].member
    error_message = "only the backup workload may read the upload SAS"
  }
}

run "backup_alert" {
  command = apply

  # No channel, no alert: the default for anyone who hasn't set one up.
  assert {
    condition     = length(module.monitoring.backup_alert_ids) == 0
    error_message = "no alert without a notification channel"
  }
}

run "labels" {
  command = apply

  # GCP only rejects a bad label at apply time, partway through a release.
  assert {
    condition     = alltrue([for k, v in local.labels : can(regex("^[a-z0-9_-]{1,63}$", k)) && can(regex("^[a-z0-9_-]{1,63}$", v))])
    error_message = "GCP labels allow only lowercase letters, digits, - and _ (63 characters at most)"
  }

  assert {
    condition     = google_compute_global_address.api.labels["component"] == "api-load-balancer" && google_compute_global_address.api.labels["app"] == "lecture-indexer"
    error_message = "the API address should have the shared labels and its component"
  }

  assert {
    condition     = google_secret_manager_secret.backup_sas.labels["component"] == "secrets" && google_secret_manager_secret.backup_sas.labels["app"] == "lecture-indexer"
    error_message = "the backup-sas secret should have the shared labels and its component"
  }

  assert {
    condition     = azurerm_resource_group.this.tags["app"] == "lecture-indexer" && azurerm_resource_group.this.tags["purpose"] != ""
    error_message = "the resource group should have the shared tags and a purpose"
  }
}

run "backup_alert_with_a_channel" {
  command = apply

  variables {
    alert_notification_channel = "projects/li-test/notificationChannels/1"
  }

  assert {
    condition     = length(module.monitoring.backup_alert_ids) == 1
    error_message = "a notification channel should create the alert"
  }
}
