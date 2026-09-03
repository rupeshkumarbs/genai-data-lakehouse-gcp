-- Bronze -> Silver transformation for customer events.
--
-- Responsibilities of this layer:
--   1. Deduplicate (source systems occasionally redeliver events)
--   2. Conform schema (normalize types, handle nulls explicitly)
--   3. Apply late-arriving-data handling via a merge, not a blind append
--
-- Reads from the BigLake external table over raw Bronze GCS files;
-- writes to a native BigQuery table for query performance.

MERGE `{{ project_id }}.silver_customer.customer_events` AS target
USING (
  SELECT
    event_id,
    customer_id,
    event_type,
    -- explicit null handling rather than letting downstream queries
    -- silently coalesce -- makes data quality issues visible early
    IFNULL(device_id, 'UNKNOWN') AS device_id,
    SAFE_CAST(event_value AS NUMERIC) AS event_value,
    TIMESTAMP(event_ts) AS event_ts,
    DATE(TIMESTAMP(event_ts)) AS event_date,
    _FILE_NAME AS source_file,
    CURRENT_TIMESTAMP() AS silver_loaded_at
  FROM `{{ project_id }}.silver_customer.bronze_customer_events_external`
  WHERE DATE(_PARTITIONDATE) = DATE('{{ ds }}')
    -- basic quality gate: drop records missing the fields every
    -- downstream consumer requires. Records failing this filter are
    -- captured separately by the Dataplex data quality scan rather
    -- than silently dropped -- see governance/dataplex_data_quality.yaml
    AND event_id IS NOT NULL
    AND customer_id IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY event_id ORDER BY event_ts DESC
  ) = 1  -- dedupe: keep latest version of each event_id
) AS source
ON target.event_id = source.event_id

WHEN MATCHED THEN
  UPDATE SET
    customer_id      = source.customer_id,
    event_type        = source.event_type,
    device_id         = source.device_id,
    event_value        = source.event_value,
    event_ts          = source.event_ts,
    event_date         = source.event_date,
    source_file        = source.source_file,
    silver_loaded_at    = source.silver_loaded_at

WHEN NOT MATCHED THEN
  INSERT (
    event_id, customer_id, event_type, device_id,
    event_value, event_ts, event_date, source_file, silver_loaded_at
  )
  VALUES (
    source.event_id, source.customer_id, source.event_type, source.device_id,
    source.event_value, source.event_ts, source.event_date, source.source_file, source.silver_loaded_at
  );

-- Table is partitioned by event_date and clustered by customer_id --
-- see docs/architecture.md section 4 for the partitioning rationale.
