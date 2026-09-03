# GCP Data Lakehouse Reference Architecture

A reference implementation of an enterprise-grade **Data Lakehouse on Google Cloud Platform**, built to demonstrate end-to-end architecture, design, and implementation patterns for scalable analytics platforms — from raw ingestion through governed, query-ready data products.

This project was built as a hands-on architecture exercise covering the full lifecycle: infrastructure-as-code, batch and streaming ingestion, medallion-layer data modeling, data governance/cataloging, access control, and data quality — the same set of concerns that come up in real enterprise data platform engagements.

## Why this project exists

I've spent 25+ years architecting cloud and data platforms — primarily on AWS and Azure, with deep experience in Star/Snowflake schema data warehousing, ETL pipeline design (Apache PySpark), and data governance for enterprise clients (see my [background](https://www.linkedin.com/in/rupesh-kumar-b-s-976b348)). This project is a deliberate deep-dive into **GCP-native Lakehouse tooling** — BigQuery, GCS, BigLake, and Dataplex — to build hands-on depth on a stack I hadn't previously worked with directly, using architecture patterns I already know well (medallion modeling, governed data platforms, IaC-driven infrastructure).

## Architecture Overview

```
Sources ──▶ Ingestion ──▶ Bronze (raw) ──▶ Silver (cleaned/conformed) ──▶ Gold (business-ready)
             │                 │                    │                          │
        Batch: Airflow    GCS + BigLake        BigQuery datasets         BigQuery datasets
        Stream: Pub/Sub   (external tables)    (partitioned/clustered)   (aggregated marts)
                                │                    │                          │
                                └──────────── Dataplex: lake/zones, cataloging, lineage, quality ─────┘
                                                       │
                                          IAM: row/column-level access control
```

See [`docs/architecture.md`](docs/architecture.md) for the full diagram, layer-by-layer rationale, and design trade-offs.

## What's in this repo

| Area | JD Requirement | Where |
|---|---|---|
| **Infrastructure as Code** | End-to-end architecture on GCP (BigQuery, GCS, BigLake, Dataplex) | [`terraform/`](terraform/) |
| **Batch ingestion** | Data pipelines for batch ingestion using orchestration frameworks | [`pipelines/airflow/dags/batch_ingestion_dag.py`](pipelines/airflow/dags/batch_ingestion_dag.py) |
| **Streaming ingestion** | Real-time ingestion using streaming frameworks | [`pipelines/airflow/dags/streaming_ingestion_dag.py`](pipelines/airflow/dags/streaming_ingestion_dag.py) |
| **Medallion transformations** | Data modeling, partitioning, and performance tuning for analytical workloads | [`pipelines/sql/`](pipelines/sql/) |
| **Data cataloging & lineage** | Best practices for cataloging, metadata, lineage across systems | [`governance/dataplex_catalog.tf`](terraform/dataplex.tf), [`docs/data_catalog.md`](docs/data_catalog.md) |
| **Data governance & security** | Access control and governance models per enterprise/regulatory standards | [`governance/`](governance/) |
| **Data quality** | Data quality enforcement | [`data_quality/quality_checks.py`](data_quality/quality_checks.py) |
| **Architecture trade-offs** | Ability to articulate trade-offs and recommendations to stakeholders | [`docs/decisions/`](docs/decisions/) |

## Tech Stack

- **Storage & Compute:** Google Cloud Storage (GCS), BigQuery, BigLake
- **Governance & Cataloging:** Dataplex, Data Catalog, IAM
- **Orchestration:** Apache Airflow (Cloud Composer-compatible DAGs)
- **Streaming:** Pub/Sub → Dataflow (streaming ingestion pattern)
- **Infrastructure as Code:** Terraform
- **Data Quality:** Python-based validation framework (Great Expectations-style assertions)
- **Modeling pattern:** Medallion architecture (Bronze → Silver → Gold)

## Design Principles

1. **Layered, governed-by-default** — every zone in the lakehouse (raw/curated/gold) is registered in Dataplex from day one; governance isn't bolted on after the fact.
2. **Both ingestion patterns supported natively** — batch (Airflow-orchestrated GCS → BigLake → BigQuery loads) and streaming (Pub/Sub → Dataflow → BigQuery) share the same downstream medallion model, so consumers don't care how data arrived.
3. **IaC-first** — every resource (buckets, datasets, lake zones, IAM bindings) is defined in Terraform, not clicked into existence, so the platform is reproducible and auditable.
4. **Cost- and performance-aware modeling** — partitioning and clustering strategy is documented per table in [`docs/architecture.md`](docs/architecture.md), not left as an afterthought.

## Status

This is an architecture and IaC reference implementation — the Terraform, DAGs, SQL, and governance configs are structured to deploy against a real GCP project (see [`terraform/README.md`](terraform/README.md) for deployment steps) and are not currently running against live infrastructure. Sample/synthetic data is used throughout for demonstration.

## About

Built by Rupesh Kumar B S — Cloud Solutions Architect with 25+ years across AWS, Azure, GenAI/agentic AI systems, and enterprise data architecture. [LinkedIn](https://www.linkedin.com/in/rupesh-kumar-b-s-976b348)
