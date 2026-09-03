"""
Streaming ingestion orchestration DAG.

The actual streaming path is Pub/Sub -> Dataflow (always-on streaming
job) -> GCS Bronze, so records arrive continuously outside of Airflow's
scheduling. Airflow's role here is NOT to move the streaming data
itself -- it's to:
  1. Launch/verify the Dataflow streaming job is running (idempotent).
  2. Periodically checkpoint Bronze->Silver micro-batch transforms
     for streaming-landed data, on a tighter schedule than the batch
     DAG, so streaming freshness reaches Silver/Gold quickly without
     requiring true row-by-row streaming inserts into BigQuery.
  3. Monitor Dataflow job health and alert on failure/backlog.

This keeps ingestion-pattern-specific orchestration (batch vs.
streaming) separate, while both patterns land into the same Bronze
GCS layout and share the same Silver/Gold SQL transforms -- see
docs/architecture.md, section 3, for the reasoning.
"""
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.google.cloud.operators.dataflow import DataflowStartFlexTemplateOperator
from airflow.providers.google.cloud.sensors.dataflow import DataflowJobStatusSensor
from airflow.providers.google.cloud.operators.bigquery import BigQueryInsertJobOperator

PROJECT_ID = "{{ var.value.gcp_project_id }}"
REGION = "us-central1"
DOMAIN = "customer"
STAGING_BUCKET = f"{PROJECT_ID}-streaming-staging-prod"
PUBSUB_TOPIC = f"projects/{PROJECT_ID}/topics/customer-events-stream"

default_args = {
    "owner": "data-platform-team",
    "retries": 2,
    "retry_delay": timedelta(minutes=2),
    "email_on_failure": True,
    "email": ["data-platform-alerts@example.com"],
}

with DAG(
    dag_id="streaming_ingestion_customer_domain",
    description="Ensure the Pub/Sub -> Dataflow streaming pipeline is healthy and checkpoint micro-batches to Silver",
    default_args=default_args,
    schedule_interval=timedelta(minutes=15),  # checkpoint cadence, not the streaming cadence itself
    start_date=datetime(2025, 1, 1),
    catchup=False,
    tags=["lakehouse", "streaming", "customer-domain"],
) as dag:

    ensure_streaming_job_running = DataflowStartFlexTemplateOperator(
        task_id="ensure_streaming_job_running",
        project_id=PROJECT_ID,
        location=REGION,
        body={
            "launchParameter": {
                "jobName": f"customer-events-streaming-{DOMAIN}",
                "containerSpecGcsPath": f"gs://{STAGING_BUCKET}/templates/pubsub-to-gcs-streaming.json",
                "parameters": {
                    "inputTopic": PUBSUB_TOPIC,
                    "outputDirectory": f"gs://{PROJECT_ID}-bronze-{DOMAIN}-prod/events/streaming/",
                    "outputFilenamePrefix": "stream-",
                    "outputFilenameSuffix": ".avro",
                },
            }
        },
        # Dataflow handles idempotency: if the job is already running,
        # this call is a no-op rather than a duplicate launch.
    )

    check_job_health = DataflowJobStatusSensor(
        task_id="check_streaming_job_health",
        project_id=PROJECT_ID,
        location=REGION,
        job_id="{{ task_instance.xcom_pull(task_ids='ensure_streaming_job_running')['job']['id'] }}",
        expected_statuses={"JOB_STATE_RUNNING"},
        timeout=120,
    )

    checkpoint_streaming_to_silver = BigQueryInsertJobOperator(
        task_id="checkpoint_streaming_bronze_to_silver",
        configuration={
            "query": {
                # Same Bronze->Silver transform as batch, filtered to
                # only the streaming-landed partition since the last
                # checkpoint -- see pipelines/sql/bronze_to_silver.sql
                "query": "{% include '../../sql/bronze_to_silver.sql' %}",
                "useLegacySql": False,
            }
        },
        location=REGION,
    )

    def alert_on_backlog(**context):
        """
        Placeholder for Pub/Sub subscription backlog monitoring --
        in production this checks the `num_undelivered_messages`
        metric via Cloud Monitoring and pages the on-call rotation if
        backlog exceeds a threshold, since a growing backlog usually
        means the Dataflow job is under-provisioned relative to
        incoming event volume.
        """
        print("Checking Pub/Sub subscription backlog for customer-events-stream")

    monitor_backlog = PythonOperator(
        task_id="monitor_pubsub_backlog",
        python_callable=alert_on_backlog,
    )

    ensure_streaming_job_running >> check_job_health >> checkpoint_streaming_to_silver
    check_job_health >> monitor_backlog
