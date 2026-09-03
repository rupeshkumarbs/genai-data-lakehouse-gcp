# ------------------------------------------------------------------
# IAM: coarse-grained dataset access control. Fine-grained
# row/column-level policies (PII masking, regional row security)
# live in BigQuery policy tags and row-access-policies — see
# governance/access_control_policy.md for the full model, since
# those resources are typically applied post-deployment against
# live table schemas rather than declared purely in Terraform.
# ------------------------------------------------------------------

# Service account the ingestion pipelines (Airflow/Composer, Dataflow)
# run as. Scoped narrowly — write access to Bronze, no direct access
# to Gold, so pipeline failures can't corrupt business-ready data.
resource "google_service_account" "ingestion_pipeline_sa" {
  account_id   = "lakehouse-ingestion-${var.environment}"
  display_name = "Lakehouse Ingestion Pipeline Service Account"
  project      = var.project_id
}

resource "google_project_iam_member" "ingestion_gcs_writer" {
  project = var.project_id
  role    = "roles/storage.objectCreator"
  member  = "serviceAccount:${google_service_account.ingestion_pipeline_sa.email}"
}

resource "google_project_iam_member" "ingestion_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.ingestion_pipeline_sa.email}"
}

# Data owner group gets full control over Silver/Gold datasets
# (granted per-dataset in bigquery.tf `access` blocks); this binding
# additionally grants Dataplex admin so the platform team can manage
# governance configuration.
resource "google_project_iam_member" "data_owner_dataplex_admin" {
  project = var.project_id
  role    = "roles/dataplex.admin"
  member  = "group:${var.data_owner_group}"
}

# Analytics readers: BigQuery job-run permission only. Actual data
# access is scoped per-dataset (Gold only) via the `access` block in
# google_bigquery_dataset.gold, not granted broadly here.
resource "google_project_iam_member" "analytics_reader_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "group:${var.analytics_reader_group}"
}
