variable "name" {
  description = "Cloud Run service name, also used for its service account."
  type        = string
}

variable "region" {
  type = string
}

# Map with static keys, because member values may be unknown until apply.
variable "deployers" {
  description = "Name => IAM member that deploys revisions (e.g. the CI deploy service account)."
  type        = map(string)
  default     = {}
}

variable "max_instances" {
  description = "Caps cost if the site is ever flooded."
  type        = number
  default     = 2
}

variable "placeholder_image" {
  description = "Image for the first revision, before CI has deployed one."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "labels" {
  description = "Labels for the console; see docs/monitoring/dashboard-links.md."
  type        = map(string)
}
