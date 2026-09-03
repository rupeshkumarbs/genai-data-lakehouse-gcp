# ------------------------------------------------------------------
# Bronze layer storage: raw, immutable, append-only landing zone.
# One bucket per domain to keep IAM boundaries clean and to make
# lifecycle/retention policy tunable per domain.
# ------------------------------------------------------------------

resource "google_storage_bucket" "bronze" {
  for_each = toset(var.lake_domains)

  name                        = "${var.project_id}-bronze-${each.key}-${var.environment}"
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy               = false

  versioning {
    enabled = true # protects against accidental overwrite of raw source data
  }

  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  labels = {
    layer       = "bronze"
    domain      = each.key
    environment = var.environment
    managed_by  = "terraform"
  }
}

# Staging bucket for streaming ingestion (Dataflow temp/staging location)
resource "google_storage_bucket" "streaming_staging" {
  name                        = "${var.project_id}-streaming-staging-${var.environment}"
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = 7 # staging files are transient
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    purpose     = "dataflow-staging"
    environment = var.environment
    managed_by  = "terraform"
  }
}
