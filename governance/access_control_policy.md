# Access Control & Governance Policy

## Principles

1. **Least privilege by layer.** Bronze and Silver are restricted to the data platform team and pipeline service accounts. Gold is the only layer broadly exposed to analytics/BI users.
2. **PII is masked by default**, not by exception. Any column tagged as PII requires an explicit, logged grant to view unmasked — the default state for every role (including data platform engineers) is masked.
3. **Region-scoped access enforced at the row level**, not left to query-time filtering by dashboard authors. A regional analyst physically cannot query another region's rows, regardless of how their BI tool is configured.
4. **Every access grant is traceable to a Terraform commit or a documented emergency-access exception** — no manual IAM console changes in production.

## Dataset-level access (IAM)

| Layer | Data Platform Team | Pipeline Service Accounts | Analytics Readers | Business Users (BI) |
|---|---|---|---|---|
| Bronze (GCS) | Read/Write | Write only | No access | No access |
| Silver (BigQuery) | Read/Write | Write only | No access | No access |
| Gold (BigQuery) | Read/Write | Read only | Read | Read (via BI tool service account) |

## Row-level security

Applied via BigQuery `CREATE ROW ACCESS POLICY` on region-partitioned Gold tables (e.g. `gold_customer.customer_360`):

```sql
CREATE ROW ACCESS POLICY region_scoped_access
ON `PROJECT.gold_customer.customer_360`
GRANT TO ("group:apac-analysts@example.com")
FILTER USING (region = 'APAC');

CREATE ROW ACCESS POLICY region_scoped_access_amer
ON `PROJECT.gold_customer.customer_360`
GRANT TO ("group:amer-analysts@example.com")
FILTER USING (region = 'AMER');
```

Members of `data-platform-team` bypass row-level policies via `bigquery.rowAccessPolicies.overrideRowLevelSecurity`, granted narrowly and logged.

## Column-level security (PII)

PII columns (customer email, phone, government ID fields where present in upstream `customer_dim`) are tagged with a Data Catalog policy tag hierarchy:

```
PII (root taxonomy)
├── PII_MASKED     -- default: values shown as hashed/redacted
└── PII_UNMASKED   -- requires explicit grant, logged via Cloud Audit Logs
```

Only members of a narrowly-scoped `pii-unmasked-readers@example.com` group — approved case-by-case with a business justification — are granted `PII_UNMASKED` reader access. This mirrors regulatory expectations (e.g. GDPR/DPDP-style purpose limitation) without needing a separate access-request system outside of the existing IAM/Terraform workflow.

## Compliance mapping

| Requirement | Control |
|---|---|
| Data minimization / purpose limitation | Gold-only broad access; PII masked by default |
| Right to audit access | Cloud Audit Logs on all BigQuery/GCS access, exported to `governance` dataset for retention |
| Data retention | Bronze lifecycle policy moves data to Coldline at 365 days (see `terraform/gcs.tf`); long-term retention/deletion policy is domain-specific and documented per Dataplex Lake |
| Data lineage for audit | Dataplex automatic lineage (BigQuery job-level) + manual lineage docs for cross-system lineage (see `docs/architecture.md` section 5) |

## Change management

All access changes go through the same Terraform PR/review process as infrastructure changes — no console-applied IAM grants in production. Emergency access exceptions (e.g. an incident responder needing temporary unmasked PII access) are logged in an exceptions register and expire automatically after 24 hours via a scheduled IAM Conditions expiry, not manual revocation.
