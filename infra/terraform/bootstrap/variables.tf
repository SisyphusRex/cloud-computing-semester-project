variable "gcp_project_id" {
  description = "GCP project that hosts everything on the Google side."
  type        = string
}

variable "gcp_region" {
  type    = string
  default = "us-central1"
}

variable "state_bucket" {
  description = "GCS bucket holding Terraform state (created by hand before bootstrap)."
  type        = string
}

variable "azure_subscription_id" {
  type = string
}

variable "azure_location" {
  description = "Azure for Students only allows canadacentral, mexicocentral, northcentralus, francecentral and swedencentral (policy sys.regionrestriction)."
  type        = string
  default     = "northcentralus"
}

variable "github_repository" {
  description = "owner/name of the repository whose workflows may deploy."
  type        = string
  default     = "SisyphusRex/cloud-computing-semester-project"
}

# GitHub puts the owner and repository IDs in the token subject when
# "immutable subjects" are on, as they are for this repository:
#   gh api repos/OWNER/REPO/actions/oidc/customization/sub -q .sub_claim_prefix
# Every identity binding matches <prefix>:environment:<name> or <prefix>:pull_request.
variable "github_subject_prefix" {
  description = "Start of GitHub's OIDC token subject for this repository (see the comment above)."
  type        = string
  default     = "repo:SisyphusRex@84345902/cloud-computing-semester-project@1403489193"
}

variable "github_plan_environment" {
  description = "GitHub Actions environment (no reviewers, main only) for release.yml's read-only plan job."
  type        = string
  default     = "prod-plan"
}

variable "github_environment" {
  description = "GitHub Actions environment that apply/deploy jobs run in."
  type        = string
  default     = "prod"
}
