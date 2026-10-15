variable "gcp_project_id" {
  type = string
}

variable "gcp_region" {
  type    = string
  default = "us-central1"
}

variable "azure_subscription_id" {
  type = string
}

variable "azure_location" {
  description = "Must be a Static Web Apps region."
  type        = string
  default     = "eastus2"
}

variable "name" {
  description = "Prefix for resource names."
  type        = string
  default     = "li"
}

variable "k8s_namespace" {
  description = "Namespace the app runs in; Workload Identity bindings are scoped to it."
  type        = string
  default     = "li"
}

variable "ci_deploy_service_account" {
  description = "The bootstrap output deploy_service_account; it gets push access to Artifact Registry."
  type        = string
}

variable "cloudsql_tier" {
  type    = string
  default = "db-f1-micro"
}

variable "db_admin_password_version" {
  description = "Bump to rotate the li_admin password (Cloud SQL and Secret Manager together)."
  type        = number
  default     = 1
}
