"""Export the figures and a small database for the portfolio web page.

Writes, into the folder given as the first argument (default: web/):
  data.json            the numbers behind each chart on the page
  sec_2019_2025.sqlite companies, financials and ratios for 2019–2025, the same
                       schema as sec_financials.db, for the in-browser SQL box

Run after sql/02_build_financials.sql:
  python3 scripts/export_web.py ../Edoardo_Degl_Innocenti/public/sec-financials
"""

import json
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "web"


def rows(db, sql):
    cursor = db.execute(sql)
    names = [c[0] for c in cursor.description]
    return [dict(zip(names, r)) for r in cursor.fetchall()]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(ROOT / "sec_financials.db")

    data = {
        "summary": rows(db, """
            SELECT COUNT(DISTINCT ticker) AS companies,
                   COUNT(DISTINCT sector) AS sectors,
                   (SELECT COUNT(*) FROM financials WHERE year BETWEEN 2019 AND 2025) AS company_years,
                   (SELECT COUNT(*) FROM facts_raw) AS raw_facts
            FROM companies JOIN financials USING (ticker)
            WHERE year BETWEEN 2019 AND 2025
        """)[0],
        # Median 2025 net margin by sector (same method as sql/03_insights.sql Q1).
        "sector_margin": rows(db, """
            WITH ranked AS (
                SELECT sector, net_margin_pct,
                       ROW_NUMBER() OVER (PARTITION BY sector ORDER BY net_margin_pct) AS position,
                       COUNT(*) OVER (PARTITION BY sector) AS companies
                FROM ratios WHERE year = 2025
            )
            SELECT sector, companies, ROUND(AVG(net_margin_pct), 1) AS value
            FROM ranked
            WHERE position IN ((companies + 1) / 2, (companies + 2) / 2)
            GROUP BY sector ORDER BY value DESC
        """),
        # Compound annual revenue growth 2019 → 2025 (Q2).
        "growth": rows(db, """
            SELECT c.ticker, c.name, c.sector,
                   ROUND(s.revenue / 1e9, 1) AS revenue_2019_bn,
                   ROUND(e.revenue / 1e9, 1) AS revenue_2025_bn,
                   ROUND(100 * (POWER(e.revenue / s.revenue, 1.0 / 6) - 1), 1) AS value
            FROM financials s
            JOIN financials e ON e.ticker = s.ticker AND e.year = 2025
            JOIN companies c ON c.ticker = s.ticker
            WHERE s.year = 2019
            ORDER BY value DESC
        """),
        # Revenue change in 2020 vs 2019 by sector (Q3).
        "covid": rows(db, """
            WITH by_company AS (
                SELECT c.sector,
                       MAX(CASE WHEN f.year = 2019 THEN f.revenue END) AS r19,
                       MAX(CASE WHEN f.year = 2020 THEN f.revenue END) AS r20,
                       MAX(CASE WHEN f.year = 2021 THEN f.revenue END) AS r21
                FROM financials f JOIN companies c USING (ticker)
                GROUP BY c.ticker, c.sector
            )
            SELECT sector,
                   ROUND(100.0 * SUM(r20) / SUM(r19) - 100, 1) AS value,
                   SUM(r20 < r19) AS companies_down,
                   COUNT(*) AS companies,
                   ROUND(100.0 * SUM(r21) / SUM(r19) - 100, 1) AS change_2021_vs_2019
            FROM by_company GROUP BY sector ORDER BY value
        """),
        # Companies with negative equity at some point in 2019–2025 (Q6).
        "negative_equity": rows(db, """
            SELECT c.ticker, c.name,
                   ROUND(f.equity / 1e9, 1) AS value,
                   ROUND((SELECT SUM(net_income) FROM financials n
                          WHERE n.ticker = f.ticker AND n.year BETWEEN 2019 AND 2025) / 1e9, 1)
                       AS net_income_2019_2025_bn
            FROM financials f JOIN companies c USING (ticker)
            WHERE f.year = 2025
              AND EXISTS (SELECT 1 FROM financials x
                          WHERE x.ticker = f.ticker AND x.year BETWEEN 2019 AND 2025 AND x.equity < 0)
            ORDER BY f.equity
        """),
        # Free cash flow ÷ net income, 2021–2025, complete years only (Q5).
        "cash_conversion": rows(db, """
            SELECT c.ticker, c.name,
                   ROUND(SUM(f.free_cash_flow) / 1e9, 1) AS fcf_bn,
                   ROUND(SUM(f.net_income) / 1e9, 1) AS net_income_bn,
                   ROUND(SUM(f.free_cash_flow) / SUM(f.net_income), 2) AS value
            FROM financials f JOIN companies c USING (ticker)
            WHERE f.year BETWEEN 2021 AND 2025
            GROUP BY c.ticker, c.name
            HAVING SUM(f.net_income) > 0 AND COUNT(f.free_cash_flow) = 5
            ORDER BY value DESC
        """),
        "current_ratio_below_one": rows(db, """
            SELECT ticker, name, sector, current_ratio AS value
            FROM ratios WHERE year = 2025 AND current_ratio < 1
            ORDER BY current_ratio
        """),
    }
    (OUT / "data.json").write_text(json.dumps(data, indent=1, ensure_ascii=False))

    web_db = OUT / "sec_2019_2025.sqlite"
    web_db.unlink(missing_ok=True)
    db.execute("ATTACH DATABASE ? AS web", (str(web_db),))
    db.executescript("""
        CREATE TABLE web.companies AS SELECT ticker, name, sector FROM companies;
        CREATE TABLE web.financials AS SELECT * FROM financials WHERE year BETWEEN 2019 AND 2025;
        CREATE TABLE web.ratios AS SELECT * FROM ratios WHERE year BETWEEN 2019 AND 2025;
    """)
    db.execute("DETACH DATABASE web")
    db.close()
    small = sqlite3.connect(web_db)
    small.execute("VACUUM")
    small.close()
    print(f"Wrote {OUT / 'data.json'} and {web_db.name} ({web_db.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
