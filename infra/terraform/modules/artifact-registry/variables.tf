variable "name" {
  type = string
}

variable "region" {
  type = string
}

# Maps with static keys, because member values may be unknown until apply.
variable "readers" {
  description = "Name => IAM member that pulls images (e.g. the GKE node service account)."
  type        = map(string)
  default     = {}
}

variable "writers" {
  description = "Name => IAM member that pushes images (e.g. the CI deploy service account)."
  type        = map(string)
  default     = {}
}

variable "labels" {
  description = "Labels for the console; see docs/monitoring/dashboard-links.md."
  type        = map(string)
}
