"""Download SEC XBRL financial data and load it into a SQLite database.

For every company in data/companies.csv this fetches the "company facts" file
from the SEC's public API (every number the company has reported in its
filings), keeps the annual-report (10-K) values for the tags listed in
data/tag_map.csv, and writes them to sec_financials.db.

The cleaning and analysis happen afterwards in SQL (see the sql/ folder).

Usage:  python3 scripts/build_database.py
Only the Python standard library is needed. Downloads are cached in data/raw/.
"""

import csv
import gzip
import json
import sqlite3
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw"
DB = ROOT / "sec_financials.db"
API = "https://data.sec.gov/api/xbrl/companyfacts/CIK{cik:010d}.json"
# The SEC asks automated tools to identify themselves; edit this to your own.
USER_AGENT = "Edoardo Degl'Innocenti portfolio research (edoardodeglinnocenti.com)"
ANNUAL_FORMS = ("10-K", "10-K/A", "10-KT", "10-KT/A")


def read_csv(name):
    with open(ROOT / "data" / name, newline="") as f:
        return list(csv.DictReader(f))


def fetch_company_facts(cik):
    """Return the parsed company-facts JSON, downloading it once."""
    RAW.mkdir(parents=True, exist_ok=True)
    cached = RAW / f"CIK{cik:010d}.json.gz"
    if not cached.exists():
        request = urllib.request.Request(
            API.format(cik=cik),
            headers={"User-Agent": USER_AGENT, "Accept-Encoding": "gzip"},
        )
        with urllib.request.urlopen(request, timeout=60) as response:
            body = response.read()
        if not body.startswith(b"\x1f\x8b"):
            body = gzip.compress(body)
        cached.write_bytes(body)
        time.sleep(0.2)  # stay well under the SEC's 10 requests per second
    return json.loads(gzip.decompress(cached.read_bytes()))


def main():
    companies = read_csv("companies.csv")
    tag_map = read_csv("tag_map.csv")
    wanted_tags = {row["tag"] for row in tag_map}

    DB.unlink(missing_ok=True)
    db = sqlite3.connect(DB)
    db.executescript(
        """
        CREATE TABLE companies (
            ticker   TEXT PRIMARY KEY,
            cik      INTEGER NOT NULL,
            name     TEXT NOT NULL,
            sector   TEXT NOT NULL,
            sec_name TEXT           -- the legal name the SEC has on file
        );
        CREATE TABLE tag_map (
            metric   TEXT NOT NULL,  -- our name for the line item
            tag      TEXT NOT NULL,  -- the US-GAAP XBRL tag companies use
            priority INTEGER NOT NULL,
            kind     TEXT NOT NULL   -- 'flow' (a period) or 'instant' (a date)
        );
        CREATE TABLE facts_raw (
            cik    INTEGER NOT NULL,
            tag    TEXT NOT NULL,
            start  TEXT,             -- period start; NULL for balance-sheet items
            end    TEXT NOT NULL,    -- period end, or the balance-sheet date
            val    REAL NOT NULL,    -- US dollars
            accn   TEXT NOT NULL,    -- accession number of the filing
            fy     INTEGER,          -- fiscal year of the filing, not of the fact
            fp     TEXT,
            form   TEXT NOT NULL,
            filed  TEXT NOT NULL,
            frame  TEXT
        );
        """
    )
    db.executemany(
        "INSERT INTO tag_map VALUES (:metric, :tag, :priority, :kind)", tag_map
    )

    for company in companies:
        cik = int(company["cik"])
        facts = fetch_company_facts(cik)
        sec_name = facts.get("entityName", "")
        db.execute(
            "INSERT INTO companies VALUES (?, ?, ?, ?, ?)",
            (company["ticker"], cik, company["name"], company["sector"], sec_name),
        )
        rows = []
        for tag, detail in facts.get("facts", {}).get("us-gaap", {}).items():
            if tag not in wanted_tags:
                continue
            for fact in detail.get("units", {}).get("USD", []):
                if fact.get("form") not in ANNUAL_FORMS:
                    continue
                rows.append((
                    cik, tag, fact.get("start"), fact["end"], fact["val"],
                    fact["accn"], fact.get("fy"), fact.get("fp"), fact["form"],
                    fact["filed"], fact.get("frame"),
                ))
        db.executemany(
            "INSERT INTO facts_raw VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", rows
        )
        print(f"{company['ticker']:<6} {sec_name:<45} {len(rows):>6} facts")

    db.execute("CREATE INDEX facts_raw_lookup ON facts_raw (cik, tag, end)")
    db.commit()
    db.close()
    print(f"\nSaved {DB.name}")


if __name__ == "__main__":
    main()
