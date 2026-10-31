variable "notification_channel" {
  description = "Cloud Monitoring channel name (projects/<id>/notificationChannels/<n>). Empty creates no alert."
  type        = string
  default     = ""
}

variable "labels" {
  description = "Labels for the console; see docs/monitoring/dashboard-links.md."
  type        = map(string)
}
