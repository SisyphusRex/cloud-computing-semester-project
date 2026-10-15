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
  type    = string
  default = "eastus2"
}

variable "github_repository" {
  description = "owner/name of the repository whose workflows may deploy."
  type        = string
  default     = "SisyphusRex/cloud-computing-semester-project"
}

variable "github_environment" {
  description = "GitHub Actions environment that apply/deploy jobs run in."
  type        = string
  default     = "prod"
}
