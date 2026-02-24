-- ============================================================
-- AWS Glue Book Scraper Lab — Athena Queries
-- AWS Glue Buch-Scraper Lab — Athena-Abfragen
--
-- Run these in the AWS Athena console after the Glue pipeline
-- completes. All queries work against the Glue Catalog tables.
--
-- Diese Abfragen im AWS Athena-Konsole ausführen, nachdem die
-- Glue-Pipeline abgeschlossen ist. Alle Abfragen funktionieren
-- gegen die Glue Catalog Tabellen.
--
-- Budget / Budget:
--   All queries against curated Parquet are tiny (< 1 MB).
--   Each query costs ~$0.000005. Essentially free!
--   Alle Abfragen gegen bereinigtes Parquet sind winzig (< 1 MB).
--   Jede Abfrage kostet ~0,000005 $. Praktisch kostenlos!
-- ============================================================

-- ── Query 1: Preview the raw table ──────────────────────────
-- Vorschau der rohen Tabelle
-- EN: Check the raw ingested data before ETL processing
-- DE: Rohe aufgenommene Daten vor der ETL-Verarbeitung prüfen
SELECT *
FROM books_db.raw_books
LIMIT 10;


-- ── Query 2: Preview the curated table ───────────────────────
-- Vorschau der bereinigten Tabelle
-- EN: Inspect the cleaned Parquet table
-- DE: Bereinigte Parquet-Tabelle inspizieren
SELECT
    title,
    price_gbp,
    rating,
    rating_band,
    in_stock,
    scraped_at
FROM books_db.curated_books
ORDER BY rating DESC, price_gbp ASC
LIMIT 20;


-- ── Query 3: Top 10 books by rating, price under £20 ────────
-- Top-10-Bücher nach Bewertung, Preis unter £20
-- EN: Find best-rated affordable books
-- DE: Am besten bewertete günstige Bücher finden
SELECT
    title,
    price_gbp,
    rating,
    rating_band
FROM books_db.curated_books
WHERE price_gbp < 20.00
  AND in_stock = true
ORDER BY rating DESC, price_gbp ASC
LIMIT 10;


-- ── Query 4: Average price by rating ─────────────────────────
-- Durchschnittspreis nach Bewertung
-- EN: How does price correlate with rating?
-- DE: Wie korreliert der Preis mit der Bewertung?
SELECT
    rating,
    COUNT(*)                          AS book_count,
    -- EN: average / DE: Durchschnitt
    ROUND(AVG(price_gbp), 2)          AS avg_price_gbp,
    ROUND(MIN(price_gbp), 2)          AS min_price_gbp,
    ROUND(MAX(price_gbp), 2)          AS max_price_gbp
FROM books_db.curated_books
GROUP BY rating
ORDER BY rating DESC;


-- ── Query 5: Books by rating band ────────────────────────────
-- Bücher nach Bewertungsband
-- EN: Distribution across Glue partition bands
-- DE: Verteilung über Glue-Partitionsbänder
SELECT
    rating_band,
    COUNT(*)                 AS total_books,
    ROUND(AVG(price_gbp), 2) AS avg_price,
    SUM(CASE WHEN in_stock THEN 1 ELSE 0 END) AS in_stock_count
FROM books_db.curated_books
GROUP BY rating_band
ORDER BY
    CASE rating_band
        WHEN 'high'   THEN 1
        WHEN 'medium' THEN 2
        WHEN 'low'    THEN 3
    END;


-- ── Query 6: Value for money (high rating, low price) ────────
-- Preis-Leistungs-Verhältnis (hohe Bewertung, niedriger Preis)
-- EN: Best value books — high rating AND cheap
-- DE: Beste Preis-Leistungs-Bücher — hohe Bewertung UND günstig
SELECT
    title,
    price_gbp,
    rating,
    -- EN: value score / DE: Preis-Leistungs-Score
    ROUND(CAST(rating AS DOUBLE) / price_gbp, 3) AS value_score
FROM books_db.curated_books
WHERE in_stock = true
  AND price_gbp > 0
ORDER BY value_score DESC
LIMIT 15;


-- ── Query 7: Check for data quality issues ───────────────────
-- Datenqualitätsprobleme prüfen
-- EN: Identify any rows with missing/null values
-- DE: Zeilen mit fehlenden/null-Werten identifizieren
SELECT
    COUNT(*)                                          AS total_rows,
    SUM(CASE WHEN title IS NULL THEN 1 ELSE 0 END)   AS null_titles,
    SUM(CASE WHEN price_gbp IS NULL THEN 1 ELSE 0 END) AS null_prices,
    SUM(CASE WHEN rating IS NULL THEN 1 ELSE 0 END)  AS null_ratings,
    SUM(CASE WHEN price_gbp <= 0 THEN 1 ELSE 0 END)  AS zero_prices
FROM books_db.curated_books;


-- ── Query 8: Partition pruning demo ──────────────────────────
-- Partition-Pruning-Demo
-- EN: This query ONLY scans the 'high' partition — much faster + cheaper!
-- DE: Diese Abfrage scannt NUR die 'high'-Partition — viel schneller + günstiger!
SELECT title, price_gbp, rating
FROM books_db.curated_books
WHERE rating_band = 'high'   -- Glue uses this to skip other partitions
ORDER BY price_gbp ASC
LIMIT 10;
