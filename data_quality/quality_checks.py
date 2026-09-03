"""
Data quality validation for Silver/Gold tables.

Runs as a standalone checkable module (invoked from the Airflow DAG
or ad hoc) so the quality rules are readable and testable outside the
orchestration layer. Complements the Dataplex-native Data Quality
scans (governance/dataplex_data_quality.yaml) rather than duplicating
them -- Dataplex handles table-level scheduled scans across the
platform, while this module encodes the same business rules in a
form that's easy to unit test in CI before a rule ever runs against
production data.
"""
from dataclasses import dataclass
from typing import Callable
from google.cloud import bigquery


@dataclass
class QualityCheck:
    name: str
    description: str
    sql: str
    # a check "passes" if the query returns zero rows (i.e. zero
    # violations found)
    severity: str = "ERROR"  # ERROR blocks downstream pipeline; WARN alerts only


CUSTOMER_EVENTS_CHECKS = [
    QualityCheck(
        name="no_null_event_id",
        description="event_id must never be null in Silver -- it's the dedup/merge key",
        sql="""
            SELECT COUNT(*) AS violations
            FROM `{project}.silver_customer.customer_events`
            WHERE event_id IS NULL
              AND event_date = CURRENT_DATE()
        """,
        severity="ERROR",
    ),
    QualityCheck(
        name="no_future_event_ts",
        description="event_ts should never be in the future -- signals a clock-skew or source bug",
        sql="""
            SELECT COUNT(*) AS violations
            FROM `{project}.silver_customer.customer_events`
            WHERE event_ts > CURRENT_TIMESTAMP()
              AND event_date = CURRENT_DATE()
        """,
        severity="ERROR",
    ),
    QualityCheck(
        name="event_value_non_negative",
        description="event_value should never be negative for purchase events",
        sql="""
            SELECT COUNT(*) AS violations
            FROM `{project}.silver_customer.customer_events`
            WHERE event_type = 'purchase'
              AND event_value < 0
              AND event_date = CURRENT_DATE()
        """,
        severity="ERROR",
    ),
    QualityCheck(
        name="unknown_device_rate_below_threshold",
        description="More than 10% UNKNOWN device_id in a day suggests an upstream ingestion problem, not just normal missing data",
        sql="""
            SELECT
              SAFE_DIVIDE(
                COUNTIF(device_id = 'UNKNOWN'),
                COUNT(*)
              ) AS unknown_rate
            FROM `{project}.silver_customer.customer_events`
            WHERE event_date = CURRENT_DATE()
            HAVING unknown_rate > 0.10
        """,
        severity="WARN",
    ),
]


def run_checks(project_id: str, checks: list[QualityCheck]) -> dict:
    """
    Executes each check against BigQuery and returns a results summary.
    Raises on the first ERROR-severity violation so the calling
    Airflow task fails loudly rather than silently propagating bad
    data into Gold.
    """
    client = bigquery.Client(project=project_id)
    results = {}

    for check in checks:
        query = check.sql.format(project=project_id)
        rows = list(client.query(query).result())
        violation_count = rows[0][0] if rows and rows[0][0] is not None else 0

        passed = violation_count == 0 if "violations" in check.sql else not rows
        results[check.name] = {
            "passed": passed,
            "severity": check.severity,
            "description": check.description,
        }

        if not passed and check.severity == "ERROR":
            raise DataQualityError(
                f"Data quality check '{check.name}' failed: {check.description}"
            )

    return results


class DataQualityError(Exception):
    """Raised when an ERROR-severity data quality check fails."""
    pass


if __name__ == "__main__":
    import sys

    project = sys.argv[1] if len(sys.argv) > 1 else "your-gcp-project"
    outcome = run_checks(project, CUSTOMER_EVENTS_CHECKS)
    for check_name, result in outcome.items():
        status = "PASS" if result["passed"] else "FAIL"
        print(f"[{status}] {check_name}: {result['description']}")
