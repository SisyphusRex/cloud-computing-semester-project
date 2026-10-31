variable "name" {
  type = string
}

variable "region" {
  type = string
}

variable "labels" {
  description = "Labels for the console; see docs/monitoring/dashboard-links.md."
  type        = map(string)
}
