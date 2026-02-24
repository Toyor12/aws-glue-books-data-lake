# 📚 AWS Glue Book Scraper Lab

> **🇬🇧 English** | **🇩🇪 Deutsch** — Bilingual Workshop Lab Project

---

## 🇬🇧 English

### What This Lab Does

This project demonstrates a complete AWS Glue ETL pipeline using real public data from [books.toscrape.com](https://books.toscrape.com) — a safe, legal practice scraping site.

**Pipeline flow:**
```
books.toscrape.com
        ↓  [Glue Python Shell job — scraper.py]
  S3 raw/books/  (newline-delimited JSON)
        ↓  [Glue Crawler — raw_crawler]
  Glue Data Catalog: books_db.raw_books
        ↓  [Glue ETL job — books_etl_job.py]
  S3 curated/books/  (Parquet, partitioned by rating_band)
        ↓  [Glue Crawler — curated_crawler]
  Glue Data Catalog: books_db.curated_books
        ↓  [Athena SQL]
  Query results (Top 10 books, avg price by rating, etc.)
```

### Budget

| Component | Cost |
|-----------|------|
| S3 storage (1 GB) | ~$0.023/month |
| Scraper (Python Shell 0.0625 DPU, ~5 min) | ~$0.000002 |
| ETL job (Flex, 2× G.1X, ~5 min) | ~$0.04 |
| Crawlers (× 2 runs, ~2 min each) | ~$0.03 |
| Athena queries (< 1 MB each) | ~$0.000005 each |
| **Total per lab session** | **~$0.10–$0.50** |

> ✅ **Well under $2/hr. The Flex execution class gives a 35% discount on ETL jobs.**

### Prerequisites

- AWS account with appropriate IAM permissions
- AWS CLI configured (`aws configure`)
- Terraform ≥ 1.5 (for infrastructure)
- Python 3.11+ (for local testing)
- Docker + Docker Compose (optional, for local dev)

### Quick Start

#### Option A: Deploy to AWS with Terraform

```bash
# 1. Clone / navigate to terraform directory
cd terraform/

# 2. Initialize Terraform
terraform init

# 3. Preview changes
terraform plan

# 4. Deploy (takes ~2 minutes)
terraform apply

# 5. Run the full pipeline workflow
aws glue start-workflow-run --name books-lab-pipeline

# 6. Monitor in AWS Glue console or CLI
aws glue get-workflow-run \
  --name books-lab-pipeline \
  --run-id <run-id>

# 7. Query results in Athena
# Open athena_queries.sql in the Athena console

# 8. ⚠️ CLEANUP — destroys all resources to avoid ongoing costs!
terraform destroy
```

#### Option B: Local Development (No AWS Cost)

```bash
# Start local MinIO S3 + scraper
cd docker/
docker-compose up -d

# Run scraper in dry-run mode (no upload)
docker-compose run scraper python scraper.py --dry-run --pages 3

# Run scraper against local MinIO
docker-compose run scraper python scraper.py \
  --bucket books-lab-lake \
  --pages 5

# View uploaded files in MinIO console
open http://localhost:9001  # minioadmin / minioadmin123
```

#### Option C: Run Scraper Manually

```bash
pip install -r scraper/requirements.txt

# Dry run — prints first 3 books
python scraper/scraper.py --dry-run --pages 2

# Real run — uploads to your S3 bucket
python scraper/scraper.py \
  --bucket your-books-lake-bucket \
  --pages 10 \
  --delay 1.5
```

### Lab Exercises

1. **Exercise 1** — Run the scraper locally with `--dry-run`. Inspect the JSON output.
2. **Exercise 2** — Deploy infrastructure with Terraform. Run the full workflow.
3. **Exercise 3** — Open the Glue Data Catalog. Find `books_db` and inspect the table schema.
4. **Exercise 4** — Run the Athena queries in `docs/athena_queries.sql`. Compare raw vs curated tables.
5. **Exercise 5** — Modify `books_etl_job.py` to add a new column: `price_category` (budget/mid/premium).
6. **Exercise 6** — Check CloudWatch for job metrics: bytes read, bytes written, DPU-hours consumed.

### Cost Controls Implemented

- **Flex execution class** on ETL job → 35% cost reduction
- **0.0625 DPU** Python Shell for scraper → near-zero cost
- **S3 Lifecycle rules** → auto-delete raw data after 30 days
- **Athena byte scan limit** → $0.02 max per query
- **30-minute job timeout** → prevents runaway costs
- **shuffle.partitions=4** → right-sized for small dataset

---

## 🇩🇪 Deutsch

### Was dieses Lab macht

Dieses Projekt demonstriert eine vollständige AWS Glue ETL-Pipeline mit echten öffentlichen Daten von [books.toscrape.com](https://books.toscrape.com) — eine sichere, legale Praxis-Scraping-Website.

**Pipeline-Ablauf:**
```
books.toscrape.com
        ↓  [Glue Python Shell Job — scraper.py]
  S3 raw/books/  (zeilengetrenntes JSON)
        ↓  [Glue Crawler — raw_crawler]
  Glue Data Catalog: books_db.raw_books
        ↓  [Glue ETL-Job — books_etl_job.py]
  S3 curated/books/  (Parquet, partitioniert nach rating_band)
        ↓  [Glue Crawler — curated_crawler]
  Glue Data Catalog: books_db.curated_books
        ↓  [Athena SQL]
  Abfrageergebnisse (Top-10-Bücher, Durchschnittspreis nach Bewertung, usw.)
```

### Budget

| Komponente | Kosten |
|-----------|------|
| S3-Speicher (1 GB) | ~0,023 $/Monat |
| Scraper (Python Shell 0,0625 DPU, ~5 Min.) | ~0,000002 $ |
| ETL-Job (Flex, 2× G.1X, ~5 Min.) | ~0,04 $ |
| Crawler (× 2 Läufe, ~2 Min. je) | ~0,03 $ |
| Athena-Abfragen (< 1 MB je) | ~0,000005 $ je |
| **Gesamt pro Lab-Sitzung** | **~0,10–0,50 $** |

> ✅ **Weit unter 2 $/Std. Die Flex-Ausführungsklasse gibt 35% Rabatt auf ETL-Jobs.**

### Voraussetzungen

- AWS-Konto mit entsprechenden IAM-Berechtigungen
- AWS CLI konfiguriert (`aws configure`)
- Terraform ≥ 1.5 (für Infrastruktur)
- Python 3.11+ (für lokale Tests)
- Docker + Docker Compose (optional, für lokale Entwicklung)

### Schnellstart

#### Option A: Auf AWS mit Terraform deployen

```bash
# 1. Zum terraform-Verzeichnis navigieren
cd terraform/

# 2. Terraform initialisieren
terraform init

# 3. Änderungen vorschau
terraform plan

# 4. Deployen (dauert ~2 Minuten)
terraform apply

# 5. Vollständige Pipeline-Workflow ausführen
aws glue start-workflow-run --name books-lab-pipeline

# 6. Ergebnis überwachen
aws glue get-workflow-run \
  --name books-lab-pipeline \
  --run-id <run-id>

# 7. Ergebnisse in Athena abfragen
# athena_queries.sql in der Athena-Konsole öffnen

# 8. ⚠️ AUFRÄUMEN — zerstört alle Ressourcen um laufende Kosten zu vermeiden!
terraform destroy
```

#### Option B: Lokale Entwicklung (Keine AWS-Kosten)

```bash
# Lokales MinIO S3 + Scraper starten
cd docker/
docker-compose up -d

# Scraper im Probelauf-Modus ausführen (kein Upload)
docker-compose run scraper python scraper.py --dry-run --pages 3

# Scraper gegen lokales MinIO ausführen
docker-compose run scraper python scraper.py \
  --bucket books-lab-lake \
  --pages 5

# Hochgeladene Dateien in MinIO-Konsole anzeigen
open http://localhost:9001  # minioadmin / minioadmin123
```

### Lab-Übungen

1. **Übung 1** — Scraper lokal mit `--dry-run` ausführen. JSON-Ausgabe inspizieren.
2. **Übung 2** — Infrastruktur mit Terraform deployen. Vollständigen Workflow ausführen.
3. **Übung 3** — Glue Data Catalog öffnen. `books_db` finden und Tabellenschema inspizieren.
4. **Übung 4** — Athena-Abfragen in `docs/athena_queries.sql` ausführen. Roh- vs. bereinigte Tabellen vergleichen.
5. **Übung 5** — `books_etl_job.py` modifizieren um neue Spalte hinzuzufügen: `price_category` (budget/mittel/premium).
6. **Übung 6** — CloudWatch nach Job-Metriken prüfen: gelesene Bytes, geschriebene Bytes, verbrauchte DPU-Stunden.

### Implementierte Kostenkontrolle

- **Flex-Ausführungsklasse** beim ETL-Job → 35% Kostenreduzierung
- **0,0625 DPU** Python Shell für Scraper → nahezu null Kosten
- **S3 Lifecycle-Regeln** → Rohdaten nach 30 Tagen automatisch löschen
- **Athena Byte-Scan-Limit** → max. 0,02 $ pro Abfrage
- **30-Minuten-Job-Timeout** → verhindert unkontrollierte Kosten
- **shuffle.partitions=4** → richtig dimensioniert für kleine Datensätze

---

## 📁 Project Structure / Projektstruktur

```
book-scraper-lab/
├── scraper/
│   ├── scraper.py          # 🕷️  Web scraper / Web-Scraper
│   ├── requirements.txt    # Python dependencies / Python-Abhängigkeiten
│   └── Dockerfile          # Container image / Container-Image
├── glue-job/
│   └── books_etl_job.py    # ⚙️  Glue ETL PySpark job / Glue ETL PySpark-Job
├── terraform/
│   └── main.tf             # 🏗️  All AWS infrastructure / Gesamte AWS-Infrastruktur
├── docker/
│   └── docker-compose.yml  # 🐳  Local dev environment / Lokale Entwicklungsumgebung
└── docs/
    └── athena_queries.sql  # 📊  Sample Athena queries / Beispiel-Athena-Abfragen
```

---

*Built for the AWS Glue Data Engineering Workshop — Bilingual Edition 🇬🇧🇩🇪*  
*Erstellt für den AWS Glue Data Engineering Workshop — Zweisprachige Ausgabe 🇬🇧🇩🇪*
