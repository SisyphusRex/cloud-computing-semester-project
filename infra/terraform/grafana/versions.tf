terraform {
  required_version = ">= 1.9"

  # Applied by hand, never in CI, so no Grafana token goes into GitHub and a
  # Grafana problem can't block a release:
  #   terraform init -backend-config="bucket=<project>-tfstate"
  backend "gcs" {
    prefix = "grafana"
  }

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 4.53"
    }
  }
}

# Reads GRAFANA_URL and GRAFANA_AUTH from the environment.
provider "grafana" {}
