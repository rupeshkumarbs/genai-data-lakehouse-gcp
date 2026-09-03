# ------------------------------------------------------------------
# BigQuery datasets: one Silver + one Gold dataset per domain.
# Bronze is NOT a native BigQuery dataset — it's queried via BigLake
# external tables defined below, pointing at the GCS bronze buckets.
# ------------------------------------------------------------------

resource "google_bigquery_dataset" "silver" {
  for_each = toset(var.lake_domains)

  dataset_id  = "silver_${each.key}"
  project     = var.project_id
  location    = var.region
  description = "Cleaned, conformed data for the ${each.key} domain. Not exposed to broad analytics access — see governance/access_control_policy.md."

  labels = {
    layer       = "silver"
    domain      = each.key
    environment = var.environment
  }

  access {
    role          = "OWNER"
    group_by_email = var.data_owner_group
  }
}

resource "google_bigquery_dataset" "gold" {
  for_each = toset(var.lake_domains)

  dataset_id  = "gold_${each.key}"
  project     = var.project_id
  location    = var.region
  description = "Business-ready, query-optimized data marts for the ${each.key} domain. This is the layer analytics/BI users query directly."

  labels = {
    layer       = "gold"
    domain      = each.key
    environment = var.environment
  }

  access {
    role          = "OWNER"
    group_by_email = var.data_owner_group
  }

  access {
    role          = "READER"
    group_by_email = var.analytics_reader_group
  }
}

# BigLake connection: lets BigQuery query GCS objects directly with
# fine-grained access delegated to a service account rather than
# per-user GCS IAM.
resource "google_bigquery_connection" "biglake" {
  connection_id = "biglake-bronze-connection-${var.environment}"
  project       = var.project_id
  location      = var.region

  cloud_resource {}
}

# Example BigLake external table over the Bronze bucket for the
# "customer" domain — Parquet, Hive-partitioned by ingestion date.
# Additional tables follow the same pattern per source.
resource "google_bigquery_table" "bronze_customer_events_biglake" {
  dataset_id = "silver_customer" # BigLake tables commonly live alongside silver for discoverability, physically pointing at bronze storage
  project    = var.project_id
  table_id   = "bronze_customer_events_external"

  external_data_configuration {
    autodetect    = false
    source_format = "PARQUET"
    connection_id = google_bigquery_connection.biglake.name

    source_uris = [
      "gs://${google_storage_bucket.bronze["customer"].name}/events/*"
    ]

    hive_partitioning_options {
      mode              = "AUTO"
      source_uri_prefix = "gs://${google_storage_bucket.bronze["customer"].name}/events/"
    }
  }

  depends_on = [google_bigquery_dataset.silver]
}
