variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  description = "Static Web Apps regions: westus2, centralus, eastus2, westeurope, eastasia."
  type        = string
}
