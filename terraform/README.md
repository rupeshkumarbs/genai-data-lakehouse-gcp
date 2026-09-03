# Deploying this Terraform module

## Prerequisites
- A GCP project with billing enabled
- Terraform >= 1.5
- `gcloud` CLI authenticated with an account that has `roles/owner` or equivalent on the target project
- The following APIs enabled on the target project:
  - `bigquery.googleapis.com`
  - `storage.googleapis.com`
  - `dataplex.googleapis.com`
  - `dataflow.googleapis.com`
  - `pubsub.googleapis.com`

## Deploy

```bash
cd terraform
terraform init
terraform plan -var="project_id=YOUR_PROJECT_ID"
terraform apply -var="project_id=YOUR_PROJECT_ID"
```

## What gets created
- GCS buckets for the Bronze layer (one per domain) + a Dataflow staging bucket
- BigQuery datasets for Silver and Gold layers (one pair per domain)
- A BigLake connection + example external table over Bronze
- Dataplex Lakes, Zones (raw/curated), and Assets binding GCS/BigQuery resources into the governance layer
- Service accounts and IAM bindings scoped to least-privilege per layer

## Notes
- This module is written for clarity and review, not for blind `terraform apply` against a production project. Review `variables.tf` and adjust `lake_domains`, `data_owner_group`, and `analytics_reader_group` before applying.
- Row-level security and column-level policy tags (PII masking) are not declared here — see [`../governance/access_control_policy.md`](../governance/access_control_policy.md) for that model, since those are typically applied against live table schemas after initial data lands.
