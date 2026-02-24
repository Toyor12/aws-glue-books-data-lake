#!/usr/bin/env python3
"""
Book Scraper — AWS Glue Lab Project
Buch-Scraper — AWS Glue Lab-Projekt

Scrapes books.toscrape.com and saves raw JSON to S3.
Scrapt books.toscrape.com und speichert rohes JSON in S3.

Usage / Verwendung:
  python scraper.py --bucket my-books-lake --pages 5

Cost note / Kostenhinweis:
  This script runs locally (no AWS cost) or as a Glue Python Shell job
  at 0.0625 DPU = $0.000025/hr — essentially free.
"""

import argparse
import json
import logging
import time
from datetime import datetime
from typing import Optional

import boto3
import requests
from bs4 import BeautifulSoup

# ── Logging ──────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)s  %(message)s"
)
log = logging.getLogger(__name__)

BASE_URL = "https://books.toscrape.com/catalogue"

# Star rating words → numeric / Sternebewertung Wörter → Zahl
RATING_MAP = {
    "One": 1, "Two": 2, "Three": 3,
    "Four": 4, "Five": 5,
}


def scrape_page(page_num: int) -> list[dict]:
    """
    Fetch one catalogue page and extract book data.
    Eine Katalogseite abrufen und Buchdaten extrahieren.
    """
    url = f"{BASE_URL}/page-{page_num}.html"
    log.info(f"[EN] Scraping page {page_num}  |  [DE] Scrappe Seite {page_num}")

    resp = requests.get(url, timeout=15)
    resp.raise_for_status()

    soup = BeautifulSoup(resp.text, "html.parser")
    articles = soup.select("article.product_pod")

    books = []
    for article in articles:
        # Title / Titel
        title_tag = article.select_one("h3 > a")
        title = title_tag["title"] if title_tag else "Unknown"

        # Price / Preis
        price_tag = article.select_one("p.price_color")
        price_raw = price_tag.text.strip() if price_tag else "£0.00"

        # Rating / Bewertung
        rating_tag = article.select_one("p.star-rating")
        rating_word = rating_tag["class"][1] if rating_tag else "Zero"
        rating = RATING_MAP.get(rating_word, 0)

        # Availability / Verfügbarkeit
        avail_tag = article.select_one("p.availability")
        availability = avail_tag.text.strip() if avail_tag else "Unknown"

        # Detail URL
        link = title_tag["href"].lstrip("../") if title_tag else ""
        detail_url = f"{BASE_URL}/{link}"

        books.append({
            "title": title,
            "price_raw": price_raw,
            "rating": rating,
            "availability": availability,
            "detail_url": detail_url,
            "page": page_num,
            "scraped_at": datetime.utcnow().isoformat() + "Z",
        })

    log.info(f"  → Found {len(books)} books on page {page_num} / {len(books)} Bücher auf Seite {page_num}")
    return books


def upload_to_s3(books: list[dict], bucket: str, prefix: str = "raw/books/") -> str:
    """
    Upload scraped books as newline-delimited JSON to S3.
    Gescrapte Bücher als zeilengetrenntes JSON in S3 hochladen.
    """
    s3 = boto3.client("s3")
    date_partition = datetime.utcnow().strftime("year=%Y/month=%m/day=%d")
    key = f"{prefix}{date_partition}/books_{datetime.utcnow().strftime('%H%M%S')}.json"

    # Newline-delimited JSON (one book per line) — Glue can read this natively
    # Zeilengetrenntes JSON (ein Buch pro Zeile) — Glue kann dies nativ lesen
    body = "\n".join(json.dumps(b, ensure_ascii=False) for b in books)

    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=body.encode("utf-8"),
        ContentType="application/x-ndjson",
    )
    s3_path = f"s3://{bucket}/{key}"
    log.info(f"[EN] Uploaded {len(books)} books to {s3_path}")
    log.info(f"[DE] {len(books)} Bücher hochgeladen nach {s3_path}")
    return s3_path


def main():
    parser = argparse.ArgumentParser(
        description="Scrape books.toscrape.com and upload to S3 / books.toscrape.com scrapen und in S3 hochladen"
    )
    parser.add_argument("--bucket", required=False, help="S3 bucket name / S3-Bucket-Name")
    parser.add_argument("--prefix", default="raw/books/", help="S3 key prefix / S3-Schlüssel-Präfix")
    parser.add_argument("--pages", type=int, default=5, help="Number of pages to scrape / Anzahl der Seiten")
    parser.add_argument("--delay", type=float, default=1.0, help="Delay between requests (s) / Pause zwischen Anfragen (s)")
    parser.add_argument("--dry-run", action="store_true", help="Print books without uploading / Bücher ausgeben ohne Upload")

    # Glue adds extra args (e.g. --WORKFLOW_NAME, --TempDir). Ignore unknown args.
    args, _ = parser.parse_known_args()

    if not args.dry_run and not args.bucket:
        parser.error("--bucket is required unless --dry-run is set")

    all_books = []

    for page in range(1, args.pages + 1):
        try:
            books = scrape_page(page)
            all_books.extend(books)
            time.sleep(args.delay)
        except requests.HTTPError as e:
            if e.response is not None and e.response.status_code == 404:
                log.info(f"[EN] Page {page} not found — reached end of catalogue.")
                log.info(f"[DE] Seite {page} nicht gefunden — Ende des Katalogs erreicht.")
                break
            raise

    log.info(f"\n[EN] Total books scraped: {len(all_books)}")
    log.info(f"[DE] Gesamtzahl gescrapte Bücher: {len(all_books)}\n")

    if args.dry_run:
        print(json.dumps(all_books[:3], indent=2, ensure_ascii=False))
        log.info("[EN] Dry run — no upload. [DE] Probelauf — kein Upload.")
    else:
        path = upload_to_s3(all_books, args.bucket, args.prefix)
        log.info(f"[EN] Done! Data at: {path}")
        log.info(f"[DE] Fertig! Daten unter: {path}")



if __name__ == "__main__":
    main()
