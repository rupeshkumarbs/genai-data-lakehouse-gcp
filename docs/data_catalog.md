# Data Cataloging & Metadata Management

## Approach

Cataloging is enforced structurally, not bolted on. Every Bronze GCS bucket and every Silver/Gold BigQuery dataset is registered as a Dataplex asset at creation time (`terraform/dataplex.tf`), so nothing enters the platform without being discoverable.

## What gets catalogued automatically

- **Schema** — Dataplex's discovery scan infers and registers schema for new Bronze partitions hourly.
- **Table/column-level metadata** — description, owner, last-modified, row count, size.
- **Lineage** — BigQuery job-level lineage is automatic; a query that reads `silver_customer.customer_events` and writes `gold_customer.customer_360` is captured without any manual annotation.

## What's catalogued manually (business context Dataplex can't infer)

Applied via Data Catalog tag templates, enforced in Terraform:

| Tag | Applies to | Purpose |
|---|---|---|
| `data_owner` | Every dataset | Who to contact for questions/incidents — maps to a team, not an individual, to survive personnel changes |
| `pii_classification` | Column-level | `NONE` / `PII_MASKED` / `PII_UNMASKED` — drives the policy-tag access model in `governance/access_control_policy.md` |
| `business_glossary_term` | Key Gold columns | Links a column like `gold_customer.customer_360.revenue_90d` to a single canonical business definition, so "revenue" means the same thing across every dashboard built on top of it |
| `retention_policy` | Dataset-level | Documents the intended retention/deletion timeline, separate from the technical GCS lifecycle rule |

## Why this matters in practice

The most common real-world data platform failure isn't a broken pipeline — it's two teams building dashboards on the same underlying concept ("active customer," "revenue") with silently different definitions, discovered months later when numbers don't reconcile. The `business_glossary_term` tag exists specifically to make that discoverable *before* it becomes a trust problem, by giving every Gold column a single source of truth for its definition, enforced at the same review gate as schema changes.
