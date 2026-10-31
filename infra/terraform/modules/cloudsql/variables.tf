variable "name" {
  type = string
}

variable "region" {
  type = string
}

variable "network_id" {
  type = string
}

variable "tier" {
  description = "db-f1-micro is the cheapest shared-core tier."
  type        = string
  default     = "db-f1-micro"
}

variable "database_name" {
  type    = string
  default = "li"
}

variable "admin_username" {
  type    = string
  default = "li_admin"
}

variable "admin_password" {
  description = "Write-only; never stored in state."
  type        = string
  ephemeral   = true
}

variable "admin_password_version" {
  description = "Change to apply a new admin_password."
  type        = number
}

variable "iam_service_accounts" {
  description = "Service account emails to create IAM database users for, keyed by a short name."
  type        = map(string)
  default     = {}
}

variable "labels" {
  description = "Labels for the console; see docs/monitoring/dashboard-links.md."
  type        = map(string)
}
