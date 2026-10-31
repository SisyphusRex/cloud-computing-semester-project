variable "account_name" {
  description = "Globally unique: 3-24 lowercase letters and digits."
  type        = string
}

variable "resource_group_id" {
  type = string
}

variable "location" {
  type = string
}

variable "container_name" {
  type    = string
  default = "backups"
}

variable "immutable_days" {
  description = "How long a blob can't be changed or deleted. Cool-tier blobs are billed for 30 days anyway."
  type        = number
  default     = 30
}

variable "delete_after_days" {
  description = "When the lifecycle rule deletes a blob. Must be above immutable_days."
  type        = number
  default     = 35
}
