variable "notification_channel" {
  description = "Cloud Monitoring channel name (projects/<id>/notificationChannels/<n>). Empty creates no alert."
  type        = string
  default     = ""
}
