"""
Batch ingestion DAG: extracts from source systems, lands raw files in
GCS Bronze, then chains the Bronze -> Silver -> Gold SQL transforms
as BigQuery jobs.

Designed to run on Cloud Composer (managed Airflow). Retries and SLA
alerting are configured per task so pipeline failures surface the
same way schema/data-quality failures do (see data_quality/ and
governance/dataplex_data_quality.yaml).
"""
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.google.cloud.transfers.gcs_to_bigquery import GCSToBigQueryOperator
from airflow.providers.google.cloud.operators.bigquery import BigQueryInsertJobOperator
from airflow.providers.google.cloud.operators.dataplex import DataplexRunDataQualityScanOperator

PROJECT_ID = "{{ var.value.gcp_project_id }}"
REGION = "us-central1"
DOMAIN = "customer"
BRONZE_BUCKET = f"{PROJECT_ID}-bronze-{DOMAIN}-prod"

default_args = {
    "owner": "data-platform-team",
    "retries": 3,
    "retry_delay": timedelta(minutes=5),
    "sla": timedelta(hours=2),
    "email_on_failure": True,
    "email": ["data-platform-alerts@example.com"],
}

with DAG(
    dag_id="batch_ingestion_customer_domain",
    description="Extract source -> land in Bronze -> transform through Silver/Gold for the customer domain",
    default_args=default_args,
    schedule_interval="0 3 * * *",  # daily at 03:00
    start_date=datetime(2025, 1, 1),
    catchup=False,
    tags=["lakehouse", "batch", "customer-domain"],
) as dag:

    def extract_from_source(**context):
        """
        Placeholder extraction step. In production this pulls from the
        source transactional system (e.g. via JDBC or an export API)
        and writes Parquet files to a local/staging path before upload.
        Kept as a Python callable (rather than a source-specific
        operator) so the extraction logic is swappable per source
        system without changing the rest of the DAG.
        """
        execution_date = context["ds"]
        print(f"Extracting customer domain records for {execution_date}")
        # extraction implementation would go here

    extract_task = PythonOperator(
        task_id="extract_from_source",
        python_callable=extract_from_source,
    )

    load_to_bronze = GCSToBigQueryOperator(
        task_id="register_bronze_partition",
        bucket=BRONZE_BUCKET,
        source_objects=["events/{{ ds }}/*.parquet"],
        destination_project_dataset_table=f"{PROJECT_ID}.silver_{DOMAIN}.bronze_customer_events_external",
        source_format="PARQUET",
        write_disposition="WRITE_APPEND",
        autodetect=False,
    )

    bronze_to_silver = BigQueryInsertJobOperator(
        task_id="bronze_to_silver",
        configuration={
            "query": {
                "query": "{% include '../../sql/bronze_to_silver.sql' %}",
                "useLegacySql": False,
            }
        },
        location=REGION,
    )

    silver_to_gold = BigQueryInsertJobOperator(
        task_id="silver_to_gold",
        configuration={
            "query": {
                "query": "{% include '../../sql/silver_to_gold.sql' %}",
                "useLegacySql": False,
            }
        },
        location=REGION,
    )

    data_quality_scan = DataplexRunDataQualityScanOperator(
        task_id="run_data_quality_scan",
        project_id=PROJECT_ID,
        region=REGION,
        data_scan_id=f"silver-{DOMAIN}-quality-scan",
    )

    extract_task >> load_to_bronze >> bronze_to_silver >> silver_to_gold >> data_quality_scan
