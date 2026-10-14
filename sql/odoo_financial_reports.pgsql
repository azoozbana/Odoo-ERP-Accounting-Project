/* ============================================================
   odoo_financial_reports.sql
   ------------------------------------------------------------
   Financial reports built directly from the Odoo 20 Community
   PostgreSQL database (database name: alnoor_erp).

   - Read-only: every query is a SELECT. Nothing here changes Odoo's data.
   - Only POSTED entries are counted (am.state = 'posted').
   - In Odoo 20, account codes and names are stored as jsonb:
         code_store ->> '1'  = account code for company id 1
         name ->> 'en_US'    = account name in English
     This project has one company (id 1). A multi-company database
     would need that key changed.
   - Chart numbering in this setup:
         1 = assets, 2 = liabilities, 4 = expenses, 5 = revenue, 6 = equity
   - Tested on Odoo 20 only. Table and column names can differ in
     other versions.
   ============================================================ */


-- =========================================================================
-- 0. GENERAL LEDGER LISTING
-- Every posted journal line in date order. Export this one to CSV
-- (docs/general_ledger_export.csv) so the repo has the raw ledger.
-- =========================================================================
SELECT
    aml.date                  AS posting_date,
    am.name                   AS document_number,
    aa.code_store ->> '1'     AS account_code,
    aa.name ->> 'en_US'       AS account_name,
    rp.name                   AS partner_name,
    aml.debit,
    aml.credit,
    aml.balance
FROM account_move_line AS aml
JOIN account_move AS am     ON aml.move_id = am.id
JOIN account_account AS aa  ON aml.account_id = aa.id
LEFT JOIN res_partner AS rp ON aml.partner_id = rp.id
WHERE am.state = 'posted'
ORDER BY aml.date, am.name, aml.id;


-- =========================================================================
-- 1. TRIAL BALANCE
-- The net balance column should total 0. That also confirms the joins
-- aren't duplicating any rows.
-- =========================================================================
WITH trial_balance_base AS (
    SELECT
        aa.code_store ->> '1'      AS account_code,
        aa.name ->> 'en_US'        AS account_name,
        ROUND(SUM(aml.debit), 2)   AS total_debit,
        ROUND(SUM(aml.credit), 2)  AS total_credit,
        ROUND(SUM(aml.balance), 2) AS net_balance
    FROM account_move_line AS aml
    JOIN account_move AS am    ON aml.move_id = am.id
    JOIN account_account AS aa ON aml.account_id = aa.id
    WHERE am.state = 'posted'
    GROUP BY aa.code_store ->> '1', aa.name ->> 'en_US'
)
SELECT account_code, account_name, total_debit, total_credit, net_balance
FROM trial_balance_base
UNION ALL
SELECT 'TOTAL', 'GRAND TOTAL',
       SUM(total_debit), SUM(total_credit), SUM(net_balance)
FROM trial_balance_base
ORDER BY account_code;


-- =========================================================================
-- 2. INCOME STATEMENT
-- Class 5 = revenue (credit minus debit), class 4 = expenses (debit minus
-- credit). Both show as positive numbers, and the result row is
-- revenue minus expenses, so a loss shows as negative.
-- sort_order keeps the layout: revenue, then expenses, then the result.
-- =========================================================================
WITH pnl_base AS (
    SELECT
        CASE WHEN LEFT(aa.code_store ->> '1', 1) = '5' THEN 1 ELSE 2 END AS sort_order,
        CASE WHEN LEFT(aa.code_store ->> '1', 1) = '5' THEN 'Revenue' ELSE 'Expense' END AS section,
        aa.code_store ->> '1'                     AS account_code,
        COALESCE(aa.name ->> 'en_US', 'Unknown')  AS account_name,
        CASE WHEN LEFT(aa.code_store ->> '1', 1) = '5'
             THEN SUM(aml.credit) - SUM(aml.debit)
             ELSE SUM(aml.debit) - SUM(aml.credit) END AS amount
    FROM account_move_line AS aml
    JOIN account_move AS am    ON aml.move_id = am.id
    JOIN account_account AS aa ON aml.account_id = aa.id
    WHERE am.state = 'posted'
      AND LEFT(aa.code_store ->> '1', 1) IN ('4', '5')
    GROUP BY aa.code_store ->> '1', aa.name ->> 'en_US'
)
SELECT section, account_code, account_name, ROUND(amount, 2) AS amount
FROM (
    SELECT sort_order, section, account_code, account_name, amount
    FROM pnl_base
    UNION ALL
    SELECT 3, 'Result', 'TOTAL', 'NET PROFIT / (LOSS)',
           SUM(CASE WHEN section = 'Revenue' THEN amount ELSE -amount END)
    FROM pnl_base
) AS x
ORDER BY sort_order, account_code;


-- =========================================================================
-- 3. BALANCE SHEET
-- Assets (class 1), liabilities (class 2), equity (class 6), plus the
-- current-period result from the income statement as an equity line.
-- The last row is a check: assets minus (liabilities + equity) must be 0.
-- =========================================================================
WITH balances AS (
    SELECT
        aa.code_store ->> '1'        AS account_code,
        aa.name ->> 'en_US'          AS account_name,
        SUM(aml.debit - aml.credit)  AS net_debit
    FROM account_move_line AS aml
    JOIN account_move AS am    ON aml.move_id = am.id
    JOIN account_account AS aa ON aml.account_id = aa.id
    WHERE am.state = 'posted'
    GROUP BY aa.code_store ->> '1', aa.name ->> 'en_US'
),
bs AS (
    SELECT
        CASE LEFT(account_code, 1)
            WHEN '1' THEN '1 Assets'
            WHEN '2' THEN '2 Liabilities'
            ELSE '3 Equity'
        END AS section,
        account_code,
        account_name,
        CASE WHEN LEFT(account_code, 1) = '1' THEN net_debit ELSE -net_debit END AS amount
    FROM balances
    WHERE LEFT(account_code, 1) IN ('1', '2', '6')
    UNION ALL
    SELECT '3 Equity', 'RESULT', 'Current period profit / (loss)', -SUM(net_debit)
    FROM balances
    WHERE LEFT(account_code, 1) IN ('4', '5')
)
SELECT section, account_code, account_name, ROUND(amount, 2) AS amount
FROM bs
UNION ALL
SELECT '4 Check', 'CHECK', 'Assets - (Liabilities + Equity), should be 0',
       ROUND(SUM(CASE WHEN section = '1 Assets' THEN amount ELSE -amount END), 2)
FROM bs
ORDER BY section, account_code;


-- =========================================================================
-- 4. VAT SUMMARY BY QUARTER
-- Output VAT (220200) vs input VAT (151100). A negative net figure means
-- input VAT is higher than output VAT, so a refund / carry-forward position.
-- No VAT settlement entry was posted in this project, so this is the
-- position, not a filed return.
-- =========================================================================
SELECT
    DATE_TRUNC('quarter', aml.date)::date AS quarter_start,
    ROUND(SUM(CASE WHEN aa.code_store ->> '1' = '220200'
                   THEN aml.credit - aml.debit ELSE 0 END), 2) AS output_vat,
    ROUND(SUM(CASE WHEN aa.code_store ->> '1' = '151100'
                   THEN aml.debit - aml.credit ELSE 0 END), 2) AS input_vat,
    ROUND(SUM(CASE WHEN aa.code_store ->> '1' = '220200'
                   THEN aml.credit - aml.debit ELSE 0 END)
        - SUM(CASE WHEN aa.code_store ->> '1' = '151100'
                   THEN aml.debit - aml.credit ELSE 0 END), 2) AS net_vat_payable
FROM account_move_line AS aml
JOIN account_move AS am    ON aml.move_id = am.id
JOIN account_account AS aa ON aml.account_id = aa.id
WHERE am.state = 'posted'
  AND aa.code_store ->> '1' IN ('220200', '151100')
GROUP BY DATE_TRUNC('quarter', aml.date)
ORDER BY quarter_start;


-- =========================================================================
-- 5. AGED RECEIVABLES (as of a fixed date)
-- Change the date in params to move the as-of date. A fixed date is used
-- because measuring against today's date would put everything in 90+ days.
-- Aging is measured from the DUE date, not the invoice date.
-- amount_residual is the CURRENT open balance, so the report is only
-- exact if no payments were posted after the as-of date.
-- 150100 is the Accounts Receivable account in this chart.
-- =========================================================================
WITH params AS (
    SELECT DATE '2026-03-31' AS as_of_date
),
open_items AS (
    SELECT
        am.name                                          AS invoice_number,
        rp.name                                          AS customer,
        am.invoice_date,
        COALESCE(aml.date_maturity, am.invoice_date_due) AS due_date,
        aml.amount_residual                              AS open_balance
    FROM account_move_line AS aml
    JOIN account_move AS am    ON aml.move_id = am.id
    JOIN account_account AS aa ON aml.account_id = aa.id
    JOIN res_partner AS rp     ON aml.partner_id = rp.id
    WHERE am.state = 'posted'
      AND aa.code_store ->> '1' = '150100'
      AND aml.amount_residual > 0
      AND aml.reconciled = false
)
SELECT
    o.invoice_number,
    o.customer,
    o.invoice_date,
    o.due_date,
    o.open_balance,
    GREATEST(p.as_of_date - o.due_date, 0) AS days_overdue,
    CASE
        WHEN p.as_of_date <= o.due_date          THEN 'Not yet due'
        WHEN p.as_of_date - o.due_date <= 30     THEN '1-30 days'
        WHEN p.as_of_date - o.due_date <= 60     THEN '31-60 days'
        WHEN p.as_of_date - o.due_date <= 90     THEN '61-90 days'
        ELSE '90+ days'
    END AS aging_bucket
FROM open_items AS o
CROSS JOIN params AS p
ORDER BY o.due_date;


-- =========================================================================
-- 6. CONTROL CHECKS
-- 6a. Debits must equal credits, and output VAT should be exactly 15% of
--     net sales (a VAT reasonableness test).
-- =========================================================================
WITH g AS (
    SELECT
        aa.code_store ->> '1' AS code,
        SUM(aml.debit)        AS d,
        SUM(aml.credit)       AS c
    FROM account_move_line AS aml
    JOIN account_move AS am    ON aml.move_id = am.id
    JOIN account_account AS aa ON aml.account_id = aa.id
    WHERE am.state = 'posted'
    GROUP BY aa.code_store ->> '1'
)
SELECT
    ROUND(SUM(d) - SUM(c), 2) AS trial_balance_difference,
    ROUND(SUM(CASE WHEN code = '220200' THEN c - d END)
        / NULLIF(SUM(CASE WHEN code = '500100' THEN c - d END), 0), 4) AS output_vat_to_sales_ratio
FROM g;

-- 6b. Any entries still in draft or cancelled? Draft entries are not counted
--     in any report above, so this shows what was left out.
SELECT state, COUNT(*) AS entries
FROM account_move
GROUP BY state
ORDER BY state;