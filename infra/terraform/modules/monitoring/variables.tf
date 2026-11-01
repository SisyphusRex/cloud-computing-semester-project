variable "notification_channel" {
  description = "Cloud Monitoring channel name (projects/<id>/notificationChannels/<n>). Empty creates no alert."
  type        = string
  default     = ""
}

variable "project_id" {
  type = string
}

variable "uptime_checks" {
  description = "HTTPS checks the dashboard shows as Up or Down, by name."
  type = map(object({
    host = string
    path = string
  }))
}

variable "namespace" {
  description = "Namespace the app runs in; app_errors counts only its containers."
  type        = string
}

variable "labels" {
  description = "Labels for the console; see docs/monitoring/dashboard-links.md."
  type        = map(string)
}
