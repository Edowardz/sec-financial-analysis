-- 04_validate.sql
-- Checks that the cleaned data matches what the companies published.
-- Every row should say OK. Run after 02_build_financials.sql:
--   sqlite3 -header -column sec_financials.db < sql/04_validate.sql


-- Test 1 ─ Revenue and net income against the companies' annual reports
-- (US$ millions). Covers fiscal years ending in June, September, January and
-- December, so it also tests how fiscal years are mapped to calendar years.
WITH published (ticker, year, fiscal_year, revenue_m, net_income_m) AS (
    VALUES
        ('AAPL', 2023, 'FY ending Sep 2023', 383285, 96995),
        ('AAPL', 2024, 'FY ending Sep 2024', 391035, 93736),
        ('MSFT', 2023, 'FY ending Jun 2023', 211915, 72361),
        ('MSFT', 2024, 'FY ending Jun 2024', 245122, 88136),
        ('WMT',  2023, 'FY ending Jan 2024', 648125, 15511),
        ('NVDA', 2023, 'FY ending Jan 2024',  60922, 29760),
        ('AMZN', 2023, 'FY ending Dec 2023', 574785, 30425),
        ('TSLA', 2023, 'FY ending Dec 2023',  96773, 14997),
        ('KO',   2023, 'FY ending Dec 2023',  45754, 10714),
        ('XOM',  2023, 'FY ending Dec 2023', 344582, 36010),
        ('JNJ',  2023, 'FY ending Dec 2023',  85159, 35153)
)
SELECT
    p.ticker,
    p.fiscal_year,
    p.revenue_m,
    ROUND(f.revenue / 1e6)    AS revenue_m_in_db,
    p.net_income_m,
    ROUND(f.net_income / 1e6) AS net_income_m_in_db,
    CASE
        WHEN ABS(f.revenue / 1e6 - p.revenue_m) < 1
         AND ABS(f.net_income / 1e6 - p.net_income_m) < 1 THEN 'OK'
        ELSE 'MISMATCH'
    END AS result
FROM published AS p
LEFT JOIN financials AS f USING (ticker, year);


-- Test 2 ─ Capital expenditure (US$ millions), which companies tag in more
-- than one way. Companies whose capex uses a tag of their own (e.g. NextEra,
-- Verizon) are left empty rather than filled with a partial figure.
WITH published (ticker, year, capex_m) AS (
    VALUES
        ('AAPL', 2023, 10959),
        ('MSFT', 2024, 44477),
        ('AMZN', 2023, 52729),
        ('HD',   2023,  3226),
        ('PEP',  2023,  5518),
        ('F',    2023,  8236),
        ('CVX',  2023, 15829)
)
SELECT
    p.ticker,
    p.year,
    p.capex_m,
    ROUND(f.capex / 1e6) AS capex_m_in_db,
    CASE WHEN ABS(f.capex / 1e6 - p.capex_m) < 1 THEN 'OK' ELSE 'MISMATCH' END AS result
FROM published AS p
LEFT JOIN financials AS f USING (ticker, year);


-- Test 3 ─ Coverage: every company should have the core lines every year.
SELECT
    year,
    COUNT(*)                         AS companies,
    SUM(revenue IS NULL)             AS missing_revenue,
    SUM(net_income IS NULL)          AS missing_net_income,
    SUM(assets IS NULL)              AS missing_assets,
    SUM(operating_cash_flow IS NULL) AS missing_cash_flow,
    CASE WHEN COUNT(*) = 61
          AND SUM(revenue IS NULL) + SUM(net_income IS NULL)
            + SUM(assets IS NULL) + SUM(operating_cash_flow IS NULL) = 0
         THEN 'OK' ELSE 'GAPS' END   AS result
FROM financials
WHERE year BETWEEN 2019 AND 2025
GROUP BY year;


-- Test 4 ─ The balance sheet balances: assets = liabilities + equity.
-- Lists only the years that are off by more than 1% of assets. A positive gap
-- is expected where a company reports "temporary equity" (redeemable shares,
-- some convertible notes) between liabilities and equity, as Tesla and
-- UnitedHealth did; anything else would point to an error in the cleaning.
SELECT
    ticker,
    year,
    ROUND((assets - liabilities - total_equity) / 1e6)                AS gap_m,
    ROUND(100.0 * (assets - liabilities - total_equity) / assets, 2) AS gap_pct_of_assets,
    CASE WHEN ticker IN ('TSLA', 'UNH') AND assets - liabilities - total_equity > 0
         THEN 'OK (temporary equity)' ELSE 'CHECK' END                AS result
FROM financials
WHERE year BETWEEN 2019 AND 2025
  AND ABS(assets - liabilities - total_equity) / assets > 0.01
ORDER BY ABS(gap_pct_of_assets) DESC;
