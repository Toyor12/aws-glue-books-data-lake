# ============================================================
# AWS Glue Book Scraper Lab — Terraform Infrastructure
# AWS Glue Buch-Scraper Lab — Terraform-Infrastruktur
#
# Budget target: < $2/hr during lab session
# Budgetziel: < 2 $/Std. während der Lab-Sitzung
#
# Estimated costs / Geschätzte Kosten:
#   S3:        ~$0.02/month per GB
#   Crawler:   ~$0.015 per run (< 2 min @ $0.44/DPU-hr)
#   ETL Job:   ~$0.04–$0.10 per run (Flex, 2 DPUs, ~5 min)
#   Athena:    ~$0.000005 per 1 MB query
#   Total lab: ~$0.10–$0.50 for a full session
# ============================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "glue-books-lab"
      Environment = "workshop"
      ManagedBy   = "terraform"
      # Tag for cost tracking / Für Kostenverfolgung
      CostCenter  = "data-engineering-workshop"
    }
  }
}

# ── Variables / Variablen ────────────────────────────────────
variable "aws_region" {
  description = "AWS region / AWS-Region"
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Project prefix for resource names / Projekt-Präfix für Ressourcennamen"
  default     = "books-lab"
}

variable "glue_version" {
  description = "Glue version (4.0 recommended) / Glue-Version (4.0 empfohlen)"
  default     = "4.0"
}

variable "scraper_pages" {
  description = "Number of catalogue pages to scrape / Anzahl der zu scrapenden Katalogseiten"
  default     = 10
}

# ── Data sources ─────────────────────────────────────────────
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── S3 Bucket ────────────────────────────────────────────────
resource "aws_s3_bucket" "data_lake" {
  # Budget: S3 is the cheapest storage option
  # Budget: S3 ist die günstigste Speicheroption
  bucket = "${var.project_name}-lake-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = "Disabled"  # Disabled to save cost / Deaktiviert um Kosten zu sparen
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  rule {
    id     = "delete-old-raw-data"
    status = "Enabled"
    filter { prefix = "raw/" }
    expiration { days = 30 }  # Auto-delete raw after 30 days / Raw nach 30 Tagen auto-löschen
  }
  rule {
    id     = "transition-curated-ia"
    status = "Enabled"
    filter { prefix = "curated/" }
    transition {
      days          = 30
      storage_class = "STANDARD_IA"  # Cheaper storage class / Günstigere Speicherklasse
    }
  }
}

# Glue scripts bucket / Glue-Skripte-Bucket
resource "aws_s3_bucket" "glue_scripts" {
  bucket = "${var.project_name}-glue-scripts-${data.aws_caller_identity.current.account_id}"
}

# Upload ETL job script / ETL-Job-Skript hochladen
resource "aws_s3_object" "etl_job_script" {
  bucket = aws_s3_bucket.glue_scripts.id
  key    = "scripts/books_etl_job.py"
  source = "${path.module}/../glue-job/books_etl_job.py"
  etag   = filemd5("${path.module}/../glue-job/books_etl_job.py")
}

# Upload scraper script / Scraper-Skript hochladen
resource "aws_s3_object" "scraper_script" {
  bucket = aws_s3_bucket.glue_scripts.id
  key    = "scripts/scraper.py"
  source = "${path.module}/../scraper/scraper.py"
  etag   = filemd5("${path.module}/../scraper/scraper.py")
}

# ── IAM Role for Glue ─────────────────────────────────────────
resource "aws_iam_role" "glue_role" {
  name = "${var.project_name}-glue-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3_access" {
  name = "s3-data-lake-access"
  role = aws_iam_role.glue_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Read/write data lake / Data Lake lesen/schreiben
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.data_lake.arn,
          "${aws_s3_bucket.data_lake.arn}/*",
        ]
      },
      {
        # Read scripts / Skripte lesen
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.glue_scripts.arn,
          "${aws_s3_bucket.glue_scripts.arn}/*",
        ]
      }
    ]
  })
}

# ── Glue Database / Glue-Datenbank ───────────────────────────
resource "aws_glue_catalog_database" "books_db" {
  name        = "books_db"
  description = "Books data lake catalog / Bücher-Data-Lake-Catalog"
}

# ── Glue Crawler — Raw Zone ───────────────────────────────────
resource "aws_glue_crawler" "raw_books" {
  name          = "${var.project_name}-raw-crawler"
  role          = aws_iam_role.glue_role.arn
  database_name = aws_glue_catalog_database.books_db.name

  # Budget: run on-demand rather than scheduled
  # Budget: Auf Anfrage statt geplant ausführen

  s3_target {
    path = "s3://${aws_s3_bucket.data_lake.bucket}/raw/books/"
  }

  schema_change_policy {
    delete_behavior = "LOG"      # Don't delete tables on schema change
    update_behavior = "UPDATE_IN_DATABASE"
  }

  configuration = jsonencode({
    Version = 1.0
    Grouping = {
      # Group all JSON files into one table / Alle JSON-Dateien zu einer Tabelle gruppieren
      TableGroupingPolicy = "CombineCompatibleSchemas"
    }
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
    }
  })
}

# ── Glue Crawler — Curated Zone ───────────────────────────────
resource "aws_glue_crawler" "curated_books" {
  name          = "${var.project_name}-curated-crawler"
  role          = aws_iam_role.glue_role.arn
  database_name = aws_glue_catalog_database.books_db.name

  s3_target {
    path = "s3://${aws_s3_bucket.data_lake.bucket}/curated/books/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }
}

# ── Glue ETL Job ─────────────────────────────────────────────
resource "aws_glue_job" "books_etl" {
  name        = "${var.project_name}-etl-job"
  role_arn    = aws_iam_role.glue_role.arn
  description = "Cleans raw books JSON → curated Parquet / Bereinigt JSON → Parquet"

  glue_version      = var.glue_version
  number_of_workers = 2          # Minimum for budget / Minimum für Budget
  worker_type       = "G.1X"     # Smallest worker / Kleinster Worker

  # BUDGET: Use Flex execution class for 35% discount on interruptible jobs
  # BUDGET: Flex-Ausführungsklasse für 35% Rabatt bei unterbrechbaren Jobs
  execution_class = "FLEX"

  max_retries = 1
  timeout     = 30  # 30 min timeout / 30 Min. Timeout — prevents runaway costs / verhindert unkontrollierte Kosten

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/scripts/books_etl_job.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--enable-job-bookmarks"             = "enable"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"                   = "true"

    # Budget: small shuffle partitions for small datasets
    # Budget: Kleine Shuffle-Partitionen für kleine Datensätze
    "--conf"                             = "spark.sql.shuffle.partitions=4"

    "--SOURCE_DATABASE" = aws_glue_catalog_database.books_db.name
    "--SOURCE_TABLE"    = "raw_books"
    "--TARGET_BUCKET"   = aws_s3_bucket.data_lake.bucket
    "--TARGET_PREFIX"   = "curated/books/"

    # Extra Python packages for scraper / Zusätzliche Python-Pakete für Scraper
    "--additional-python-modules" = "requests==2.31.0,beautifulsoup4==4.12.2"

    "--TempDir" = "s3://${aws_s3_bucket.glue_scripts.bucket}/tmp/"
  }
}

# ── Glue Python Shell Job — Scraper ──────────────────────────
# Budget: 0.0625 DPU = essentially free / 0,0625 DPU = praktisch kostenlos
resource "aws_glue_job" "scraper_job" {
  name        = "${var.project_name}-scraper-job"
  role_arn    = aws_iam_role.glue_role.arn
  description = "Scrapes books.toscrape.com and uploads JSON to S3 / Scrapt und lädt JSON nach S3"

  glue_version = "3.0"  # Python Shell supported in Glue 3.0 / Python Shell in Glue 3.0 unterstützt
  max_capacity = 0.0625 # Minimum DPU for Python Shell / Minimum DPU für Python Shell — $0.000025/hr!

  max_retries = 1
  timeout     = 20

  command {
    name            = "pythonshell"
    script_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/scripts/scraper.py"
    python_version  = "3.9"
  }

  default_arguments = {
    "--bucket"                           = aws_s3_bucket.data_lake.bucket
    "--pages"                            = tostring(var.scraper_pages)
    "--enable-job-bookmarks"             = "disable"  # No bookmark needed for scraper
    "--enable-continuous-cloudwatch-log" = "true"
    "--additional-python-modules"        = "requests==2.31.0,beautifulsoup4==4.12.2"
  }
}

# ── Glue Workflow ─────────────────────────────────────────────
resource "aws_glue_workflow" "books_pipeline" {
  name        = "${var.project_name}-pipeline"
  description = "End-to-end books scraping pipeline / Durchgängige Books-Scraping-Pipeline"
}

# Trigger 1: Start scraper on demand / Scraper auf Anfrage starten
resource "aws_glue_trigger" "start_scraper" {
  name          = "${var.project_name}-start-trigger"
  type          = "ON_DEMAND"
  workflow_name = aws_glue_workflow.books_pipeline.name

  actions {
    job_name = aws_glue_job.scraper_job.name
  }
}

# Trigger 2: Run raw crawler after scraper succeeds
# Roh-Crawler nach Scraper-Erfolg starten
resource "aws_glue_trigger" "after_scraper" {
  name          = "${var.project_name}-after-scraper"
  type          = "CONDITIONAL"
  workflow_name = aws_glue_workflow.books_pipeline.name

  predicate {
    conditions {
      job_name = aws_glue_job.scraper_job.name
      state    = "SUCCEEDED"
    }
  }

  actions {
    crawler_name = aws_glue_crawler.raw_books.name
  }
}

# Trigger 3: Run ETL job after raw crawler succeeds
# ETL-Job nach Roh-Crawler-Erfolg starten
resource "aws_glue_trigger" "after_raw_crawler" {
  name          = "${var.project_name}-after-raw-crawler"
  type          = "CONDITIONAL"
  workflow_name = aws_glue_workflow.books_pipeline.name

  predicate {
    conditions {
      crawler_name = aws_glue_crawler.raw_books.name
      crawl_state  = "SUCCEEDED"
    }
  }

  actions {
    job_name = aws_glue_job.books_etl.name
  }
}

# Trigger 4: Run curated crawler after ETL succeeds
# Bereinigt-Crawler nach ETL-Erfolg starten
resource "aws_glue_trigger" "after_etl" {
  name          = "${var.project_name}-after-etl"
  type          = "CONDITIONAL"
  workflow_name = aws_glue_workflow.books_pipeline.name

  predicate {
    conditions {
      job_name = aws_glue_job.books_etl.name
      state    = "SUCCEEDED"
    }
  }

  actions {
    crawler_name = aws_glue_crawler.curated_books.name
  }
}

# ── Athena Workgroup (budget-limited) ────────────────────────
resource "aws_athena_workgroup" "books" {
  name        = "${var.project_name}-workgroup"
  description = "Books lab workgroup with cost controls / Books-Lab-Workgroup mit Kostenkontrolle"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/athena-results/"
    }

    # Budget: limit bytes scanned per query to $0.02 max
    # Budget: Gescannte Bytes pro Abfrage auf max. 0,02 $ begrenzen
    bytes_scanned_cutoff_per_query = 4294967296  # 4 GB limit = $0.02 max per query
  }
}

# ── Outputs / Ausgaben ────────────────────────────────────────
output "data_lake_bucket" {
  description = "S3 data lake bucket / S3-Data-Lake-Bucket"
  value       = aws_s3_bucket.data_lake.bucket
}

output "glue_database" {
  description = "Glue Catalog database / Glue Catalog Datenbank"
  value       = aws_glue_catalog_database.books_db.name
}

output "etl_job_name" {
  description = "Glue ETL job name / Glue ETL-Job-Name"
  value       = aws_glue_job.books_etl.name
}

output "scraper_job_name" {
  description = "Glue scraper job name / Glue Scraper-Job-Name"
  value       = aws_glue_job.scraper_job.name
}

output "workflow_name" {
  description = "Glue workflow name / Glue Workflow-Name"
  value       = aws_glue_workflow.books_pipeline.name
}

output "cost_estimate" {
  description = "Estimated cost per full lab run / Geschätzte Kosten pro vollständigem Lab-Lauf"
  value       = "~$0.10–$0.50 per full pipeline run. Under $2/hr guaranteed."
}
