# Keyless GitHub Actions -> GCP: GitHub's OIDC token is exchanged through a
# Workload Identity pool for short-lived service account credentials.
#
# Which service account a job may use depends on the token's subject:
#   repo:<repo>:environment:<env>  -> github-terraform, github-deploy
#                                     (jobs in the protected GitHub environment)
#   repo:<repo>:pull_request       -> github-plan (read-only)
#   repo:<repo>:environment:<plan env> -> github-plan (release.yml's plan job)

locals {
  bootstrap_services = [
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
  ]

  # Terraform creates every resource in envs/prod, including IAM bindings.
  terraform_roles = [
    "roles/editor",
    "roles/resourcemanager.projectIamAdmin",
    "roles/iam.serviceAccountAdmin",
    "roles/secretmanager.admin",
    "roles/artifactregistry.admin",
    "roles/servicenetworking.networksAdmin",
  ]

  # Deploy jobs push images and apply Kubernetes manifests; Cloud SQL Viewer
  # lets them see that the environment is paused (scripts/ci/check-paused.sh).
  deploy_roles = [
    "roles/container.developer",
    "roles/cloudsql.viewer",
  ]

  # PR plans run with -refresh=false, so this is only for reading state and
  # for anyone running a full plan by hand. Viewer can't read secret values.
  plan_roles = [
    "roles/viewer",
  ]

  subject_prefix       = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/subject/repo:${var.github_repository}"
  environment_subject  = "${local.subject_prefix}:environment:${var.github_environment}"
  pull_request_subject = "${local.subject_prefix}:pull_request"
  plan_env_subject     = "${local.subject_prefix}:environment:${var.github_plan_environment}"
}

resource "google_project_service" "bootstrap" {
  for_each           = toset(local.bootstrap_services)
  service            = each.value
  disable_on_destroy = false
}

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"
  depends_on                = [google_project_service.bootstrap]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"

  # Only claims present on every token can be mapped; `environment` is absent
  # on jobs without one, so bindings match on the subject instead.
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }
  # Tokens from any other repository are rejected outright.
  attribute_condition = "assertion.repository == \"${var.github_repository}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "terraform" {
  account_id   = "github-terraform"
  display_name = "GitHub Actions: Terraform apply (prod environment only)"
}

resource "google_service_account" "deploy" {
  account_id   = "github-deploy"
  display_name = "GitHub Actions: image push and Kubernetes deploy (prod environment only)"
}

resource "google_service_account" "plan" {
  account_id   = "github-plan"
  display_name = "GitHub Actions: read-only Terraform plan on pull requests"
}

resource "google_project_iam_member" "terraform" {
  for_each = toset(local.terraform_roles)
  project  = var.gcp_project_id
  role     = each.value
  member   = google_service_account.terraform.member
}

resource "google_project_iam_member" "deploy" {
  for_each = toset(local.deploy_roles)
  project  = var.gcp_project_id
  role     = each.value
  member   = google_service_account.deploy.member
}

resource "google_project_iam_member" "plan" {
  for_each = toset(local.plan_roles)
  project  = var.gcp_project_id
  role     = each.value
  member   = google_service_account.plan.member
}

resource "google_storage_bucket_iam_member" "terraform_state" {
  bucket = var.state_bucket
  role   = "roles/storage.objectAdmin"
  member = google_service_account.terraform.member
}

# Read-only: PR plans run with -lock=false, so no lock object is written.
resource "google_storage_bucket_iam_member" "plan_state" {
  bucket = var.state_bucket
  role   = "roles/storage.objectViewer"
  member = google_service_account.plan.member
}

resource "google_service_account_iam_member" "terraform_wif" {
  service_account_id = google_service_account.terraform.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.environment_subject
}

resource "google_service_account_iam_member" "deploy_wif" {
  service_account_id = google_service_account.deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.environment_subject
}

resource "google_service_account_iam_member" "plan_wif" {
  service_account_id = google_service_account.plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.pull_request_subject
}

# The release workflow plans with this identity before asking for approval.
resource "google_service_account_iam_member" "plan_env_wif" {
  service_account_id = google_service_account.plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.plan_env_subject
}
