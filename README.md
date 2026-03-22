# AWS Glue Book Data Pipeline

End-to-end serverless data pipeline that ingests book data from a public website, processes it using AWS Glue, and makes it available for analytics via Amazon Athena.

---

## Overview

This project implements a complete data engineering workflow using AWS services. It extracts data from an external source, stores it in a raw data lake, transforms it into a curated format, and enables SQL-based analytics.

The pipeline demonstrates practical data engineering concepts including ingestion, transformation, schema management, and cost-efficient cloud processing.

---

## Architecture

```text
books.toscrape.com
        ↓  (Python scraper)
S3 raw/books/  (JSON)
        ↓  (Glue Crawler)
Glue Data Catalog (raw_books)
        ↓  (Glue ETL Job - PySpark)
S3 curated/books/  (Parquet, partitioned)
        ↓  (Glue Crawler)
Glue Data Catalog (curated_books)
        ↓
Athena (SQL queries)
```

---

## Data Flow

1. Python scraper extracts book data from a public website  
2. Raw data stored in S3 (newline-delimited JSON)  
3. Glue Crawler infers schema and updates Data Catalog  
4. Glue ETL job transforms data into partitioned Parquet  
5. Curated data registered in Glue Catalog  
6. Athena used for analytical queries  

---

## What This Project Demonstrates

- Building ingestion pipelines using Python  
- Designing raw and curated data lake layers in S3  
- Automating schema discovery with Glue Crawlers  
- Performing ETL transformations using AWS Glue (PySpark)  
- Creating partitioned Parquet datasets for efficient querying  
- Enabling serverless analytics using Athena  
- Managing cost-efficient cloud data pipelines  

---

## Technology Stack

| Component | Technology |
|----------|-----------|
| Ingestion | Python (Web Scraper) |
| Storage | Amazon S3 |
| Processing | AWS Glue (Python Shell + PySpark) |
| Metadata | Glue Data Catalog |
| Querying | Amazon Athena |
| Infrastructure | Terraform |
| Local Dev | Docker + MinIO |

---

## Key Features

- End-to-end pipeline from ingestion to analytics  
- Raw → curated data lake architecture  
- Partitioned Parquet output for performance  
- Serverless processing using AWS Glue  
- Cost-optimized design using low DPU and Flex jobs  
- Local development environment using Docker and MinIO  

---

## Example Outputs

- Top-rated books by price  
- Average book price by rating category  
- Partitioned dataset optimized for Athena queries  

Sample queries available in:
```
docs/athena_queries.sql
```

---

## How to Run

### 1. Deploy infrastructure
```bash
cd terraform
terraform init
terraform apply
```

### 2. Run pipeline
```bash
aws glue start-workflow-run --name books-lab-pipeline
```

### 3. Query results
- Open Athena
- Run queries from `docs/athena_queries.sql`

### 4. Tear down resources
```bash
terraform destroy
```

---

## Local Development (Optional)

Run pipeline locally using Docker + MinIO:

```bash
cd docker
docker-compose up -d
```

Run scraper locally:

```bash
docker-compose run scraper python scraper.py --dry-run --pages 3
```

---

## Cost Considerations

- Low-cost Python Shell job for scraping  
- Flex execution class for Glue ETL (reduced cost)  
- Partitioned Parquet to reduce Athena scan costs  
- S3 lifecycle rules to manage storage  

Estimated cost per run: **~$0.10 – $0.50**

---

## Project Structure

```text
book-scraper-lab/
├── scraper/
├── glue-job/
├── terraform/
├── docker/
├── docs/
```

---

## Key Learnings

- Building serverless data pipelines on AWS  
- Using Glue for both ingestion and transformation  
- Structuring data lakes using raw and curated layers  
- Optimizing data formats and partitions for query performance  
- Managing costs in cloud-based pipelines  

---

## Future Improvements

- Add orchestration using Dagster or Airflow  
- Add CI/CD pipeline for Terraform and Glue jobs  
- Add data quality checks and validation layer  
- Add dashboarding layer (Power BI / Superset)  
- Implement incremental data loading  

---

## References

- AWS Glue Documentation  
- Amazon Athena Documentation  
- Terraform AWS Provider Documentation  
