# ------------------------------------------------------------------
# Dataplex: governance and cataloging layer. One Lake per domain,
# with raw/curated/analytics zones mapping to Bronze/Silver/Gold.
# Asset discovery is enabled on Bronze so new partitions are
# catalogued automatically without manual registration.
# ------------------------------------------------------------------

resource "google_dataplex_lake" "domain_lake" {
  for_each = toset(var.lake_domains)

  name         = "${each.key}-lake-${var.environment}"
  location     = var.region
  project      = var.project_id
  display_name = "${title(each.key)} Domain Lake"
  description  = "Governs raw, curated, and analytics zones for the ${each.key} domain."

  labels = {
    domain      = each.key
    environment = var.environment
  }
}

resource "google_dataplex_zone" "raw_zone" {
  for_each = toset(var.lake_domains)

  name         = "raw-zone"
  lake         = google_dataplex_lake.domain_lake[each.key].name
  location     = var.region
  project      = var.project_id
  display_name = "Raw Zone (Bronze)"
  type         = "RAW"

  discovery_spec {
    enabled = true # auto-discovers new GCS partitions as they land
    schedule = "0 * * * *" # hourly discovery scan
  }

  resource_spec {
    location_type = "SINGLE_REGION"
  }
}

resource "google_dataplex_zone" "curated_zone" {
  for_each = toset(var.lake_domains)

  name         = "curated-zone"
  lake         = google_dataplex_lake.domain_lake[each.key].name
  location     = var.region
  project      = var.project_id
  display_name = "Curated Zone (Silver + Gold)"
  type         = "CURATED"

  discovery_spec {
    enabled = true
  }

  resource_spec {
    location_type = "SINGLE_REGION"
  }
}

# Asset binding: registers the Bronze GCS bucket into the raw zone
# so Dataplex auto-discovers, catalogs, and tracks lineage for it.
resource "google_dataplex_asset" "bronze_asset" {
  for_each = toset(var.lake_domains)

  name          = "${each.key}-bronze-asset"
  lake          = google_dataplex_lake.domain_lake[each.key].name
  dataplex_zone = google_dataplex_zone.raw_zone[each.key].name
  location      = var.region
  project       = var.project_id

  resource_spec {
    name = "projects/${var.project_id}/buckets/${google_storage_bucket.bronze[each.key].name}"
    type = "STORAGE_BUCKET"
  }

  discovery_spec {
    enabled = true
  }
}

# Asset binding: registers the Silver BigQuery dataset into the
# curated zone for cataloging and lineage.
resource "google_dataplex_asset" "silver_asset" {
  for_each = toset(var.lake_domains)

  name          = "${each.key}-silver-asset"
  lake          = google_dataplex_lake.domain_lake[each.key].name
  dataplex_zone = google_dataplex_zone.curated_zone[each.key].name
  location      = var.region
  project       = var.project_id

  resource_spec {
    name = "projects/${var.project_id}/datasets/${google_bigquery_dataset.silver[each.key].dataset_id}"
    type = "BIGQUERY_DATASET"
  }

  discovery_spec {
    enabled = true
  }
}
