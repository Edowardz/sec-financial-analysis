-- 03_insights.sql
-- Business questions answered from the cleaned data, 2019–2025.
-- Run:  sqlite3 -header -column sec_financials.db < sql/03_insights.sql
--
-- Each query starts with the question it answers and the SQL technique it
-- practices.


-- Q1 ─ Which sectors keep the most of each dollar of sales? (2025)
-- Technique: a CTE plus window functions to compute a median, which SQLite
-- has no built-in function for. Medians are used instead of averages so one
-- extreme company (NVIDIA, Boeing) cannot move a whole sector.
WITH ranked AS (
    SELECT
        sector,
        net_margin_pct,
        ROW_NUMBER() OVER (PARTITION BY sector ORDER BY net_margin_pct) AS position,
        COUNT(*)     OVER (PARTITION BY sector)                        AS companies
    FROM ratios
    WHERE year = 2025
)
SELECT
    sector,
    companies,
    ROUND(AVG(net_margin_pct), 1) AS median_net_margin_pct
FROM ranked
WHERE position IN ((companies + 1) / 2, (companies + 2) / 2)
GROUP BY sector
ORDER BY median_net_margin_pct DESC;


-- Q2 ─ Who grew fastest, and who shrank? Compound annual revenue growth,
-- 2019 → 2025.
-- Technique: joining a table to itself to put two years side by side.
SELECT
    c.ticker,
    c.name,
    c.sector,
    ROUND(start.revenue / 1e9, 1)                                     AS revenue_2019_bn,
    ROUND(latest.revenue / 1e9, 1)                                    AS revenue_2025_bn,
    ROUND(100 * (POWER(latest.revenue / start.revenue, 1.0 / 6) - 1), 1) AS cagr_pct
FROM financials AS start
JOIN financials AS latest ON latest.ticker = start.ticker AND latest.year = 2025
JOIN companies  AS c      ON c.ticker = start.ticker
WHERE start.year = 2019
ORDER BY cagr_pct DESC;


-- Q3 ─ How hard did COVID hit each sector, and how fast did it recover?
-- Sector revenue in 2020 and 2021 compared with 2019. Sector totals are
-- weighted by size (Amazon alone carries Consumer Discretionary), so the
-- middle column counts how many companies actually shrank.
-- Technique: conditional aggregation (CASE inside MAX) to pivot years into
-- columns, then a second aggregation by sector.
WITH by_company AS (
    SELECT
        c.sector,
        MAX(CASE WHEN f.year = 2019 THEN f.revenue END) AS revenue_2019,
        MAX(CASE WHEN f.year = 2020 THEN f.revenue END) AS revenue_2020,
        MAX(CASE WHEN f.year = 2021 THEN f.revenue END) AS revenue_2021
    FROM financials AS f
    JOIN companies  AS c USING (ticker)
    GROUP BY c.ticker, c.sector
)
SELECT
    sector,
    ROUND(100.0 * SUM(revenue_2020) / SUM(revenue_2019) - 100, 1) AS change_2020_pct,
    SUM(revenue_2020 < revenue_2019) || ' of ' || COUNT(*)        AS companies_down_2020,
    ROUND(100.0 * SUM(revenue_2021) / SUM(revenue_2019) - 100, 1) AS change_2021_vs_2019_pct
FROM by_company
GROUP BY sector
ORDER BY change_2020_pct;


-- Q4 ─ Whose margins moved the most? Net margin in 2019 vs 2025.
-- Technique: a self-join to compare two years, then the top and bottom five
-- combined with UNION ALL.
WITH change AS (
    SELECT
        a.ticker,
        a.name,
        a.net_margin_pct            AS margin_2019,
        b.net_margin_pct            AS margin_2025,
        b.net_margin_pct - a.net_margin_pct AS change_pts
    FROM ratios AS a
    JOIN ratios AS b ON b.ticker = a.ticker AND b.year = 2025
    WHERE a.year = 2019
)
SELECT * FROM (SELECT 'expanded' AS direction, * FROM change ORDER BY change_pts DESC LIMIT 5)
UNION ALL
SELECT * FROM (SELECT 'compressed', * FROM change ORDER BY change_pts ASC LIMIT 5);


-- Q5 ─ Who turns profit into cash? Free cash flow divided by net income,
-- summed over 2021–2025 so one unusual year does not dominate.
-- Above 1 means the company generates more cash than its reported profit.
-- Only companies with free cash flow in all five years are ranked; a partial
-- sum would compare different periods.
-- Technique: HAVING to filter on aggregates.
SELECT
    c.ticker,
    c.name,
    ROUND(SUM(f.free_cash_flow) / 1e9, 1)                 AS fcf_2021_2025_bn,
    ROUND(SUM(f.net_income) / 1e9, 1)                     AS net_income_2021_2025_bn,
    ROUND(SUM(f.free_cash_flow) / SUM(f.net_income), 2)   AS cash_conversion
FROM financials AS f
JOIN companies  AS c USING (ticker)
WHERE f.year BETWEEN 2021 AND 2025
GROUP BY c.ticker, c.name
HAVING SUM(f.net_income) > 0
   AND COUNT(f.free_cash_flow) = 5
ORDER BY cash_conversion DESC;


-- Q6 ─ Negative shareholders' equity: distress, or a sign of strength?
-- Several profitable companies owe more than they own on paper, because years
-- of share buybacks and dividends returned more than their accumulated
-- profits. Comparing cumulative profit with the equity gap separates
-- buyback-driven cases from loss-driven ones.
-- Technique: filtering on a condition across years with EXISTS.
SELECT
    c.ticker,
    c.name,
    ROUND(f.equity / 1e9, 1)                                  AS equity_2025_bn,
    ROUND((SELECT SUM(net_income) FROM financials AS n
           WHERE n.ticker = f.ticker AND n.year BETWEEN 2019 AND 2025) / 1e9, 1)
                                                              AS net_income_2019_2025_bn,
    ROUND(r.current_ratio, 2)                                 AS current_ratio_2025
FROM financials AS f
JOIN companies  AS c USING (ticker)
JOIN ratios     AS r USING (ticker, year)
WHERE f.year = 2025
  AND EXISTS (SELECT 1 FROM financials AS x
              WHERE x.ticker = f.ticker AND x.year BETWEEN 2019 AND 2025 AND x.equity < 0)
ORDER BY f.equity;


-- Q7 ─ Short-term liquidity: who has less in current assets than they owe in
-- the next twelve months (current ratio below 1) in 2025?
-- Below 1 is a warning sign for most companies, but normal for businesses
-- paid in cash before they pay suppliers (retailers, restaurants) and for
-- regulated utilities.
SELECT
    ticker,
    name,
    sector,
    current_ratio
FROM ratios
WHERE year = 2025 AND current_ratio < 1
ORDER BY current_ratio;
