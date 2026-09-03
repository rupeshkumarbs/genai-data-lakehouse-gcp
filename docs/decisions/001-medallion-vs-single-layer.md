# ADR 001: Medallion Architecture vs. Single-Layer Warehouse

## Status
Accepted

## Context
The platform needs to serve two very different consumers: (a) the data platform team debugging ingestion issues and needing access to raw, unmodified source data, and (b) business/BI users who need fast, trustworthy, pre-aggregated data and should never see a malformed or duplicate record.

## Options considered

**Option A — Single-layer warehouse.** Land data directly into cleaned, query-ready BigQuery tables. Simpler to build and reason about initially.

**Option B — Medallion (Bronze/Silver/Gold).** Separate raw, conformed, and business-ready layers.

## Decision
Option B (medallion). 

## Rationale
- **Replayability:** if business logic in a transformation has a bug discovered weeks later, Option A requires re-extracting from the source system (often no longer possible for transactional systems with short retention). With Bronze preserved, we replay the transform against unchanged raw data.
- **Separation of concerns for access control:** Bronze/Silver need to stay locked down to the platform team; Gold needs to be broadly queryable. A single layer forces an uncomfortable trade-off between "clean enough to expose" and "raw enough to debug."
- **Cost:** raw Parquet/Avro in GCS (Bronze, via BigLake) is meaningfully cheaper than the same volume in BigQuery native storage, and most of Bronze is rarely queried once it's passed validation.

## Trade-off accepted
Added pipeline complexity (three transformation stages instead of one) and slightly higher end-to-end latency to Gold. Judged acceptable since none of the current use cases require sub-minute freshness in Gold — see ADR 002 for the streaming-specific version of this trade-off.

## Consequences
- Every new data source requires defining all three layers up front, which is more initial design work per source.
- Silver becomes the natural place to enforce data contracts with upstream source-system owners.
