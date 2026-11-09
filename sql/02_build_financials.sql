-- 02_build_financials.sql
-- Turns the raw XBRL facts into one clean row per company per year
-- (table: financials), then adds the ratios analysts use (view: ratios).
--
-- Run:  sqlite3 sec_financials.db < sql/02_build_financials.sql

DROP VIEW IF EXISTS ratios;
DROP VIEW IF EXISTS annual_facts;
DROP TABLE IF EXISTS financials;


-- Step 1 ─ Keep only full-year numbers and give them our metric names.
--
-- Balance-sheet items ("instant") are a snapshot on one date, so they have no
-- start date. Income-statement and cash-flow items ("flow") cover a period;
-- we keep periods of about a year (52/53-week years run 364 or 371 days).
--
-- Companies close their books in different months, so each fiscal year is
-- given the calendar year it mostly covers: years ending June–December keep
-- their year, years ending January–May count as the previous one. Apple's
-- year ending September 2023 and Walmart's ending January 2024 are both 2023.
CREATE VIEW annual_facts AS
SELECT
    c.ticker,
    m.metric,
    m.kind,
    m.priority,
    f.end,
    f.val,
    f.accn,
    f.filed,
    CAST(strftime('%Y', f.end) AS INTEGER)
        - (CAST(strftime('%m', f.end) AS INTEGER) < 6) AS year
FROM facts_raw AS f
JOIN tag_map   AS m ON m.tag = f.tag
JOIN companies AS c ON c.cik = f.cik
WHERE (m.kind = 'instant' AND f.start IS NULL)
   OR (m.kind = 'flow' AND julianday(f.end) - julianday(f.start) BETWEEN 350 AND 380);


-- Step 2 ─ Pick one value per company, metric and year.
--
-- The same number appears in several filings: each 10-K repeats the prior
-- years, and sometimes restates them. ROW_NUMBER() ranks the candidates and we
-- keep the first: the preferred tag, then the latest period end, then the most
-- recent filing (so restated figures replace the originals).
--
-- Balance-sheet lines all come from one filing: the last one that presented
-- that year's balance sheet. Restatements can touch a single line later on
-- (GE re-presented its equity after its spin-offs, but not the rest of the
-- balance sheet), and mixing versions would make it stop balancing.
--
-- Step 3 ─ Pivot from one row per metric to one column per metric, and fill
-- gaps some companies leave: total liabilities and gross profit are not always
-- reported, but can be derived from lines that are.
CREATE TABLE financials AS
WITH balance_sheet_source AS (
    SELECT ticker, year, accn
    FROM (
        SELECT
            ticker, year, accn,
            ROW_NUMBER() OVER (
                PARTITION BY ticker, year
                ORDER BY end DESC, filed DESC
            ) AS pick
        FROM annual_facts
        WHERE metric = 'assets'
    )
    WHERE pick = 1
),
ranked AS (
    SELECT
        a.*,
        ROW_NUMBER() OVER (
            PARTITION BY a.ticker, a.metric, a.year
            ORDER BY
                a.kind = 'instant' AND a.accn IS NOT b.accn,  -- same filing first
                a.priority,
                a.end DESC,
                a.filed DESC
        ) AS pick
    FROM annual_facts AS a
    LEFT JOIN balance_sheet_source AS b USING (ticker, year)
),
wide AS (
    SELECT
        ticker,
        year,
        MAX(end) AS period_end,
        MAX(CASE WHEN metric = 'revenue'                THEN val END) AS revenue,
        MAX(CASE WHEN metric = 'cost_of_revenue'        THEN val END) AS cost_of_revenue,
        MAX(CASE WHEN metric = 'gross_profit'           THEN val END) AS gross_profit_reported,
        MAX(CASE WHEN metric = 'operating_income'       THEN val END) AS operating_income,
        MAX(CASE WHEN metric = 'net_income'             THEN val END) AS net_income,
        MAX(CASE WHEN metric = 'rnd'                    THEN val END) AS rnd,
        MAX(CASE WHEN metric = 'operating_cash_flow'    THEN val END) AS operating_cash_flow,
        MAX(CASE WHEN metric = 'capex'                  THEN val END) AS capex,
        MAX(CASE WHEN metric = 'assets'                 THEN val END) AS assets,
        MAX(CASE WHEN metric = 'current_assets'         THEN val END) AS current_assets,
        MAX(CASE WHEN metric = 'liabilities'            THEN val END) AS liabilities_reported,
        MAX(CASE WHEN metric = 'current_liabilities'    THEN val END) AS current_liabilities,
        MAX(CASE WHEN metric = 'liabilities_and_equity' THEN val END) AS liabilities_and_equity,
        MAX(CASE WHEN metric = 'equity'                 THEN val END) AS equity,
        MAX(CASE WHEN metric = 'equity_incl_nci'        THEN val END) AS equity_incl_nci,
        MAX(CASE WHEN metric = 'cash'                   THEN val END) AS cash,
        MAX(CASE WHEN metric = 'long_term_debt'         THEN val END) AS long_term_debt
    FROM ranked
    WHERE pick = 1
    GROUP BY ticker, year
)
SELECT
    ticker,
    year,
    period_end,
    revenue,
    cost_of_revenue,
    COALESCE(gross_profit_reported, revenue - cost_of_revenue)    AS gross_profit,
    operating_income,
    net_income,
    rnd,
    operating_cash_flow,
    capex,
    operating_cash_flow - capex                                   AS free_cash_flow,
    assets,
    current_assets,
    COALESCE(liabilities_reported,
             liabilities_and_equity - COALESCE(equity_incl_nci, equity)) AS liabilities,
    current_liabilities,
    -- Shareholders' equity of the parent company. A few companies (UnitedHealth)
    -- only report the total including minority interests; use that instead.
    COALESCE(equity, equity_incl_nci)                             AS equity,
    COALESCE(equity_incl_nci, equity)                             AS total_equity,
    cash,
    long_term_debt
FROM wide;

CREATE UNIQUE INDEX financials_key ON financials (ticker, year);


-- Step 4 ─ Ratios. A window (w) lines up each company's years in order so
-- LAG() can look at the previous year, for growth and average assets. Ratios
-- that divide by equity or profit are left empty when the divisor is zero or
-- negative, because the result would mislead (see README: negative equity).
CREATE VIEW ratios AS
SELECT
    f.ticker,
    c.name,
    c.sector,
    f.year,
    f.revenue,
    f.net_income,
    ROUND(100.0 * f.gross_profit     / f.revenue, 1)             AS gross_margin_pct,
    ROUND(100.0 * f.operating_income / f.revenue, 1)             AS operating_margin_pct,
    ROUND(100.0 * f.net_income       / f.revenue, 1)             AS net_margin_pct,
    ROUND(100.0 * f.free_cash_flow   / f.revenue, 1)             AS fcf_margin_pct,
    ROUND(100.0 * f.rnd              / f.revenue, 1)             AS rnd_pct,
    CASE WHEN LAG(f.year) OVER w = f.year - 1
         THEN ROUND(100.0 * (f.revenue / LAG(f.revenue) OVER w - 1), 1)
    END                                                          AS revenue_growth_pct,
    ROUND(f.current_assets / f.current_liabilities, 2)          AS current_ratio,
    CASE WHEN f.equity > 0
         THEN ROUND(f.liabilities / f.equity, 2) END            AS liabilities_to_equity,
    CASE WHEN f.equity > 0
         THEN ROUND(100.0 * f.net_income / f.equity, 1) END     AS roe_pct,
    CASE WHEN LAG(f.year) OVER w = f.year - 1
         THEN ROUND(100.0 * f.net_income / ((f.assets + LAG(f.assets) OVER w) / 2), 1)
    END                                                          AS roa_pct,
    CASE WHEN f.net_income > 0
         THEN ROUND(f.free_cash_flow / f.net_income, 2) END     AS cash_conversion,
    f.equity < 0                                                 AS negative_equity
FROM financials AS f
JOIN companies  AS c USING (ticker)
WINDOW w AS (PARTITION BY f.ticker ORDER BY f.year);
