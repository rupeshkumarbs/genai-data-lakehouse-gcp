# ADR 002: Streaming via Pub/Sub → Dataflow → GCS, not Direct BigQuery Streaming Insert

## Status
Accepted

## Context
Real-time events (from Pub/Sub) need to reach the lakehouse. BigQuery supports direct streaming inserts (`tabledata.insertAll` / Storage Write API), which would let streaming data reach a query-able table with sub-second latency and no intermediate storage hop.

## Options considered

**Option A — Pub/Sub → BigQuery direct streaming insert.** Lowest latency path; skips GCS entirely for streaming data.

**Option B — Pub/Sub → Dataflow → GCS Bronze → same Silver/Gold transforms as batch.** Slightly higher latency; unifies streaming and batch through one Bronze layer.

## Decision
Option B.

## Rationale
- **Consistency for downstream consumers:** with Option A, Silver/Gold transforms would need two code paths — one reading from a streaming-inserted BigQuery table, one reading from BigLake-over-GCS for batch sources. Option B means every downstream transform is ingestion-pattern-agnostic; a Silver table doesn't know or care whether a given Bronze record arrived via nightly batch or real-time stream.
- **Replayability parity:** Option A's streamed records land directly in BigQuery with no raw-file equivalent preserved (unless separately archived), losing the replay/audit benefit that Bronze gives batch sources (see ADR 001). Option B preserves this for streaming data too.
- **Cost at our volume:** direct streaming inserts have a per-row cost that becomes material at high event volume; Dataflow micro-batching into GCS, then a single BigQuery load/merge job, is materially cheaper at the volumes in scope for this platform.

## Trade-off accepted
Latency to Silver/Gold is measured in minutes (Dataflow micro-batch window + checkpoint cadence), not sub-second. This was explicitly validated against actual use-case requirements before deciding — none of the current consuming dashboards or downstream ML features need true sub-second freshness. **This is a decision to revisit, not a permanent architectural stance** — if a future use case genuinely requires sub-second Gold freshness (e.g. real-time fraud scoring), Option A becomes the right call for that specific data product, likely as an addition alongside Option B rather than a wholesale replacement.

## Consequences
- One streaming-specific orchestration DAG (`streaming_ingestion_dag.py`) exists purely to manage Dataflow job health and checkpoint cadence — this is operational overhead Option A wouldn't have needed.
- Any future low-latency requirement should be scoped and justified against actual business need before reopening this decision, not adopted by default "because streaming should be real-time."
