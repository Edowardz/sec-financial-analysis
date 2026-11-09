# Financial Health of 61 US Companies, 2019–2025

**Live project:** [edoardodeglinnocenti.com/sec-financials](https://edoardodeglinnocenti.com/sec-financials/index.html):
the charts, the SQL behind each one, and an editor to query the data in your
browser.

A SQL analysis of the annual reports that 61 large US companies filed with the
Securities and Exchange Commission (SEC). It covers seven years: before COVID,
the shock, the recovery, and the inflation and interest-rate years after it.

The data comes straight from the SEC's public XBRL API, the machine-readable
version of every 10-K. The project downloads the raw numbers, cleans and
validates them in SQL, and answers business questions about profitability,
growth, cash generation and balance-sheet strength.

**Tools:** SQL (SQLite), Python (standard library only), SEC EDGAR XBRL data.

## Key findings

1. **Technology keeps the most of each dollar of sales.** In 2025 the median
   technology company in the sample turned 21.7% of revenue into net profit,
   against 6.7% in consumer discretionary (retail, restaurants, autos).
2. **NVIDIA grew revenue 64% a year**, from $10.9bn in 2019 to $215.9bn in
   2025. Tesla (25% a year) and Eli Lilly (20%) follow. Intel shrank 5% a year
   and its net margin fell from 29.2% to a small loss.
3. **COVID hit unevenly.** Energy revenue fell 34% in 2020. Consumer
   discretionary grew 12.7% as a sector, but 4 of its 9 companies shrank:
   Amazon carried the total. No health care company lost revenue.
4. **Negative equity is not always distress.** Philip Morris, Lowe's,
   Starbucks, Altria, AbbVie and McDonald's report negative shareholders'
   equity while earning $22–60bn of combined profit from 2019 to 2025: they
   returned more cash through buybacks and dividends than they kept. Boeing's
   weak equity, by contrast, follows $33.5bn of losses.
5. **Profit and cash can diverge.** Bristol-Myers Squibb generated 3.4 times
   more free cash flow than reported profit in 2021–2025, as large non-cash
   charges reduced earnings without using cash. Intel's free cash flow was
   negative while it built new factories.
6. **A current ratio below 1 is common among giants.** 22 of the 61 companies,
   including Apple, Walmart and Procter & Gamble, owed more in the next twelve
   months than they held in current assets in 2025. For businesses that collect
   cash before paying suppliers, that signals bargaining power, not a liquidity
   problem.

## How the data is built

| Step | What happens | Where |
|---|---|---|
| 1. Download | Every annual-report fact for each company, from the SEC API | `scripts/build_database.py` |
| 2. Map tags | Companies label the same line differently (five tags for revenue alone); `tag_map.csv` lists them in priority order | `data/tag_map.csv` |
| 3. Align years | Fiscal years ending June–December keep their year, January–May count as the previous one (Walmart's year to January 2024 is 2023) | `sql/02_build_financials.sql` |
| 4. Deduplicate | Each 10-K repeats and sometimes restates earlier years; the latest filing wins, and a balance sheet always comes from a single filing | `sql/02_build_financials.sql` |
| 5. Derive | Gross profit, total liabilities and equity are filled from related lines when not reported; ratios computed with window functions | `sql/02_build_financials.sql` |
| 6. Validate | Revenue, net income and capex match the published reports; no core line is missing; every balance sheet balances | `sql/04_validate.sql` |

## Data notes

- **Banks and insurers are excluded.** Their balance sheets have no current
  assets or cost of goods sold, so the ratios used here do not apply.
- **Spin-offs break like-for-like trends.** GE (GE HealthCare, GE Vernova), 3M
  (Solventum), AT&T (WarnerMedia) and Johnson & Johnson (Kenvue) shrank by
  design; their growth rates describe the remaining company, not a decline.
- **Not every company reports every line.** Many service, telecom and utility
  companies show no gross profit; several pharma and energy companies show no
  operating income. Those ratios are left empty.
- **Capital expenditure** is missing where a company uses its own custom tag
  (NextEra, Verizon, NVIDIA 2019–20, ConocoPhillips 2023–25). Free-cash-flow
  rankings only include companies with all years available.
- **Temporary equity.** Tesla and UnitedHealth report redeemable interests
  between liabilities and equity, so their assets exceed liabilities plus
  equity by 1–2%. This is correct accounting, not a data error.
- **Sectors** are assigned by the author in a GICS-like scheme.

## Run it yourself

Requires Python 3 and SQLite, both preinstalled on macOS.

```bash
python3 scripts/build_database.py                              # download, ~1 minute
sqlite3 sec_financials.db < sql/02_build_financials.sql        # clean
sqlite3 -header -column sec_financials.db < sql/04_validate.sql  # check
sqlite3 -header -column sec_financials.db < sql/03_insights.sql  # answers
```

New to SQL? Start with `sql/01_explore.sql`, which introduces one idea per
query on this data. `exports/` holds clean CSVs for Excel, Tableau or Power BI.

## Project structure

```
data/companies.csv         the 61 companies, SEC identifiers and sectors
data/tag_map.csv           which XBRL tags feed each metric
scripts/build_database.py  download and load into SQLite
scripts/export_web.py      chart data and a small database for the web page
sql/01_explore.sql         SQL basics on this data
sql/02_build_financials.sql  cleaning, the financials table, the ratios view
sql/03_insights.sql        the business questions behind the findings
sql/04_validate.sql        tests against published figures
exports/                   financials and ratios, 2019–2025, as CSV
```

Source: SEC EDGAR, company facts API (public domain). Figures in the exports
are in US$ millions.
