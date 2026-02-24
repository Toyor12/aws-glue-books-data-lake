FROM python:3.11-slim

# EN: Minimal image for budget-conscious development
# DE: Minimales Image für kostenorientierte Entwicklung

WORKDIR /app

# Install dependencies / Abhängigkeiten installieren
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY scraper.py .

CMD ["python", "scraper.py", "--help"]
