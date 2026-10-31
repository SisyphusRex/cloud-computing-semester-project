variable "secrets" {
  description = "Secret ID => { accessors = { name => IAM member } }. Static names keep for_each keys known before apply."
  type = map(object({
    accessors = map(string)
  }))
}

variable "secret_values" {
  description = "Secret ID => value. Every key in `secrets` needs one. Ephemeral; never stored in state."
  type        = map(string)
  ephemeral   = true
}

variable "secret_value_versions" {
  description = "Secret ID => version number; change it to write a new value. Defaults to 1."
  type        = map(number)
  default     = {}
}

variable "labels" {
  description = "Labels for the console; see docs/monitoring/dashboard-links.md."
  type        = map(string)
}
