terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ------------------------------------------------------------------
# This root module wires together the storage, warehouse, governance,
# and IAM layers of the lakehouse. Each concern lives in its own file
# so the platform can be reasoned about and reviewed layer-by-layer,
# mirroring the Bronze/Silver/Gold + Governance architecture in
# docs/architecture.md.
# ------------------------------------------------------------------
