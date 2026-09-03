-- Silver -> Gold transformation: builds the customer_360 business
-- mart consumed directly by BI tools and analytics users.
--
-- This is a full rebuild (not incremental) because the aggregation
-- window (trailing 90 days) makes incremental merge logic more
-- complex than the cost of a daily full recompute at this data
-- volume. Revisit if Silver volume grows past ~500M rows/day --
-- see docs/architecture.md trade-offs section for similar sizing
-- decisions made elsewhere in the pipeline.

CREATE OR REPLACE TABLE `{{ project_id }}.gold_customer.customer_360`
PARTITION BY summary_date
CLUSTER BY region
AS
SELECT
  CURRENT_DATE() AS summary_date,
  c.customer_id,
  c.region,
  COUNT(DISTINCT e.event_id) AS event_count_90d,
  COUNT(DISTINCT e.device_id) AS distinct_devices_90d,
  SUM(CASE WHEN e.event_type = 'purchase' THEN e.event_value ELSE 0 END) AS revenue_90d,
  MAX(e.event_ts) AS last_active_ts,
  DATE_DIFF(CURRENT_DATE(), DATE(MAX(e.event_ts)), DAY) AS days_since_last_active

FROM `{{ project_id }}.silver_customer.customer_events` AS e
JOIN `{{ project_id }}.silver_customer.customer_dim` AS c
  ON e.customer_id = c.customer_id

WHERE e.event_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)

GROUP BY c.customer_id, c.region;

-- Row-level security (region-scoped access for regional business
-- users) and column-level policy tags (PII on any customer_dim
-- columns joined upstream) are applied against this table post-
-- creation -- see governance/access_control_policy.md.
