-- 01_explore.sql
-- A first tour of the database, one SQL idea at a time.
-- Run everything:  sqlite3 -header -column sec_financials.db < sql/01_explore.sql
-- Or open the database (sqlite3 sec_financials.db) and paste one query.
--
-- Tables:  companies   one row per company (ticker, name, sector)
--          financials  one row per company per year (revenue, profit, assets…)
--          ratios      a view: margins, growth and other ratios, ready to read
-- Amounts are in US dollars; divide by 1e9 for billions.


-- 1 ─ SELECT … FROM: look at a table.
-- "Show me every column (*) of the companies table, but only 10 rows."
SELECT *
FROM companies
LIMIT 10;


-- 2 ─ WHERE: keep only the rows you want.
-- "Apple's revenue and net income, year by year, in billions."
SELECT
    year,
    ROUND(revenue / 1e9, 1)    AS revenue_bn,
    ROUND(net_income / 1e9, 1) AS net_income_bn
FROM financials
WHERE ticker = 'AAPL'
  AND year BETWEEN 2019 AND 2025;


-- 3 ─ ORDER BY and LIMIT: rank.
-- "The ten largest companies by revenue in 2025."
SELECT
    ticker,
    ROUND(revenue / 1e9, 1) AS revenue_bn
FROM financials
WHERE year = 2025
ORDER BY revenue DESC
LIMIT 10;


-- 4 ─ JOIN: combine two tables that share a column.
-- financials only knows the ticker; companies knows the name and sector.
-- "Same top ten, with names and sectors."
SELECT
    c.name,
    c.sector,
    ROUND(f.revenue / 1e9, 1) AS revenue_bn
FROM financials AS f
JOIN companies  AS c ON c.ticker = f.ticker
WHERE f.year = 2025
ORDER BY f.revenue DESC
LIMIT 10;


-- 5 ─ GROUP BY: summarise many rows into one per group (like a pivot table).
-- "For each sector in 2025: how many companies, total revenue, average net
-- margin."
SELECT
    sector,
    COUNT(*)                     AS companies,
    ROUND(SUM(revenue) / 1e9)    AS total_revenue_bn,
    ROUND(AVG(net_margin_pct), 1) AS avg_net_margin_pct
FROM ratios
WHERE year = 2025
GROUP BY sector
ORDER BY avg_net_margin_pct DESC;


-- 6 ─ Calculations and CASE: create new columns from existing ones.
-- "Label each company's 2025 net margin."
SELECT
    ticker,
    net_margin_pct,
    CASE
        WHEN net_margin_pct >= 20 THEN 'High'
        WHEN net_margin_pct >= 10 THEN 'Medium'
        WHEN net_margin_pct >= 0  THEN 'Low'
        ELSE 'Loss-making'
    END AS margin_band
FROM ratios
WHERE year = 2025
ORDER BY net_margin_pct DESC;
