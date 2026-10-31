terraform {
  required_version = ">= 1.9"

  # State lives in a GCS bucket created by hand first (see docs/runbooks/bootstrap.md):
  #   terraform init -backend-config="bucket=<project>-tfstate"
  backend "gcs" {
    prefix = "bootstrap"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.7"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.10"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.13"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
}

provider "azapi" {
  subscription_id = var.azure_subscription_id
}
