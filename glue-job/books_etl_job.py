"""
AWS Glue ETL Job — Book Scraper Pipeline
AWS Glue ETL-Job — Book-Scraper-Pipeline

Reads raw scraped JSON from Glue Catalog → cleans and transforms →
writes curated Parquet to S3, partitioned by rating band.

Rohe JSON-Daten aus Glue Catalog lesen → bereinigen und transformieren →
bereinigtes Parquet in S3 schreiben, partitioniert nach Bewertungsband.

Budget / Budget:
  2× G.1X workers (default) = $0.88/hr
  Use Flex execution class for 35% discount → ~$0.57/hr
  Typical run time for 1000 books: ~4 minutes → ~$0.04 per run
  
  2× G.1X Worker (Standard) = 0,88 $/Std.
  Mit Flex-Ausführungsklasse 35% Rabatt → ~0,57 $/Std.
  Typische Laufzeit für 1000 Bücher: ~4 Minuten → ~0,04 $ pro Lauf
"""

import sys

from awsglue.context import GlueContext
from awsglue.dynamicframe import DynamicFrame
from awsglue.job import Job
from awsglue.transforms import ApplyMapping
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql.functions import (
    col,
    regexp_replace,
    round,
    trim,
    when,
    lit,
    current_timestamp,
)

# ── Job initialisation / Job-Initialisierung ──────────────────
args = getResolvedOptions(sys.argv, [
    "JOB_NAME",
    "SOURCE_DATABASE",   # Glue Catalog database / Glue Catalog Datenbank
    "SOURCE_TABLE",      # Raw books table / Rohe Bücher-Tabelle
    "TARGET_BUCKET",     # Output S3 bucket / Ausgabe-S3-Bucket
    "TARGET_PREFIX",     # Output path prefix / Ausgabe-Pfad-Präfix
])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args["JOB_NAME"], args)

# Budget tip: small shuffle partitions for small datasets
# Budget-Tipp: Kleine Shuffle-Partitionen für kleine Datensätze
spark.conf.set("spark.sql.shuffle.partitions", "4")

print("[EN] Job started successfully.")
print("[DE] Job erfolgreich gestartet.")

# ── 1. Read from Glue Catalog / Aus Glue Catalog lesen ───────
print("\n[EN] Step 1: Reading raw books from Glue Data Catalog...")
print("[DE] Schritt 1: Rohe Bücher aus dem Glue Data Catalog lesen...")

raw_dyf = glueContext.create_dynamic_frame.from_catalog(
    database=args["SOURCE_DATABASE"],
    table_name=args["SOURCE_TABLE"],
    transformation_ctx="raw_dyf",
    # Job bookmark: skip already-processed partitions
    # Job-Bookmark: Bereits verarbeitete Partitionen überspringen
    additional_options={"jobBookmarkKeys": ["scraped_at"]},
)

count_raw = raw_dyf.count()
print(f"[EN] Read {count_raw} raw book records.")
print(f"[DE] {count_raw} rohe Buchdatensätze gelesen.")

# ── 2. Schema mapping / Schema-Mapping ───────────────────────
print("\n[EN] Step 2: Applying schema mapping...")
print("[DE] Schritt 2: Schema-Mapping anwenden...")

mapped_dyf = ApplyMapping.apply(
    frame=raw_dyf,
    mappings=[
        # (source_col, source_type, target_col, target_type)
        ("title",        "string", "title",        "string"),
        ("price_raw",    "string", "price_raw",    "string"),
        ("rating",       "int",    "rating",       "int"),
        ("availability", "string", "availability", "string"),
        ("detail_url",   "string", "detail_url",   "string"),
        ("page",         "int",    "source_page",  "int"),
        ("scraped_at",   "string", "scraped_at",   "string"),
    ],
    transformation_ctx="mapped_dyf",
)

# ── 3. Convert to Spark DataFrame for transforms ──────────────
# Zu Spark DataFrame konvertieren für Transformationen
df = mapped_dyf.toDF()

print("\n[EN] Step 3: Cleaning and transforming data...")
print("[DE] Schritt 3: Daten bereinigen und transformieren...")

df_clean = df_clean = (
    df
    .withColumn(
        "price_gbp",
        round(regexp_replace(col("price_raw"), r"[£\s,]", "").cast("double"), 2)
    )
    .withColumn("in_stock", when(trim(col("availability")) == "In stock", True).otherwise(False))
    .withColumn(
        "rating_band",
        when(col("rating") >= 4, lit("high"))
        .when(col("rating") >= 3, lit("medium"))
        .otherwise(lit("low"))
    )
    .withColumn(
        "price_category",
        when(col("price_gbp") < 20, lit("budget"))
        .when(col("price_gbp") <= 40, lit("mid"))
        .otherwise(lit("premium"))
    )
    .withColumn("processed_at", current_timestamp())
    .drop("price_raw")
    .filter(col("price_gbp").isNotNull() & (col("price_gbp") > 0))
)

count_clean = df_clean.count()
print(f"[EN] Cleaned records: {count_clean} (dropped {count_raw - count_clean} invalid rows)")
print(f"[DE] Bereinigte Datensätze: {count_clean} ({count_raw - count_clean} ungültige Zeilen entfernt)")

# Show sample / Stichprobe anzeigen
print("\n[EN] Sample output / [DE] Stichprobenausgabe:")
df_clean.select("title", "price_gbp", "price_category", "rating", "rating_band", "in_stock").show(5, truncate=40)

# ── 4. Write curated Parquet to S3 ───────────────────────────
# Bereinigtes Parquet in S3 schreiben
print("\n[EN] Step 4: Writing curated Parquet to S3...")
print("[DE] Schritt 4: Bereinigtes Parquet in S3 schreiben...")

target_path = f"s3://{args['TARGET_BUCKET']}/{args['TARGET_PREFIX']}"

# Repartition for optimal file size (avoid small files problem)
# Neupartitionierung für optimale Dateigröße (Small-Files-Problem vermeiden)
df_output = df_clean.repartition(1)  # 1 file since dataset is small / 1 Datei da Datensatz klein

clean_dyf = DynamicFrame.fromDF(df_output, glueContext, "clean_dyf")

glueContext.write_dynamic_frame.from_options(
    frame=clean_dyf,
    connection_type="s3",
    connection_options={
        "path": target_path,
        "partitionKeys": ["rating_band"],  # Partition by rating band / Partitionierung nach Bewertungsband
    },
    format="parquet",
    format_options={
        "compression": "snappy",  # Snappy: good balance of speed and size / Gutes Gleichgewicht aus Geschwindigkeit und Größe
    },
    transformation_ctx="clean_dyf_write",
)

print(f"\n[EN] ✅ Written curated data to: {target_path}")
print(f"[DE] ✅ Bereinigte Daten geschrieben nach: {target_path}")
print(f"[EN]    Partitioned by: rating_band (high/medium/low)")
print(f"[DE]    Partitioniert nach: rating_band (hoch/mittel/niedrig)")

# ── 5. Commit job bookmark / Job-Bookmark festschreiben ──────
job.commit()
print("\n[EN] Job completed and bookmark committed.")
print("[DE] Job abgeschlossen und Bookmark festgeschrieben.")
