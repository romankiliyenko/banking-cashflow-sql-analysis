-- Project: Banking Cash Flow & Account Monitoring
-- File: 01_data_exploration.sql
-- Dataset: Berka Financial Dataset (PKDD'99)
-- Purpose: Explore the banking data and validate transaction fields
--          before calculating account-level cash flows.

USE financial;

-- ============================================================
-- 1. DATABASE OVERVIEW
-- ============================================================

-- Inspect available tables and the structure of key tables.
SHOW TABLES;

DESCRIBE trans;
DESCRIBE account;
DESCRIBE loan;

-- Preview a small sample without retrieving the entire dataset.
SELECT *
FROM trans
ORDER BY trans_id
LIMIT 10;

-- ============================================================
-- 2. TRANSACTION PROFILING
-- ============================================================

-- Business Question: How many transactions are recorded?
SELECT
    COUNT(trans_id) AS no_of_trans
FROM trans;

-- Business Question: How many unique accounts have transactions?
SELECT
    COUNT(DISTINCT account_id) AS no_of_accounts
FROM trans;

-- Business Question: What is the earliest and latest transaction date?
SELECT
    MIN(date) AS earliest_date,
    MAX(date) AS latest_date
FROM trans;

-- Business Question: How are transactions distributed by type?
SELECT
    type,
    COUNT(trans_id) AS no_of_trans
FROM trans
GROUP BY type
ORDER BY no_of_trans DESC;

-- Business Question: Which transaction types and operations occur together?
SELECT
    type,
    operation,
    COUNT(trans_id) AS no_of_trans
FROM trans
GROUP BY type, operation
ORDER BY no_of_trans DESC;

-- ============================================================
-- 3. AMOUNT VALIDATION AND TRANSACTION PURPOSES
-- ============================================================

-- Business Question: Are there negative, zero or missing transaction amounts?
-- Objective: Examine amount ranges and count zero/NULL amounts by type.
SELECT
    type,
    COUNT(trans_id) AS no_of_trans,
    MIN(amount) AS min_amount,
    MAX(amount) AS max_amount,
    SUM(CASE WHEN amount = 0 THEN 1 ELSE 0 END) AS zero_amount_count,
    SUM(CASE WHEN amount IS NULL THEN 1 ELSE 0 END) AS null_amount_count
FROM trans
GROUP BY type
ORDER BY no_of_trans DESC;

-- Business Question: What transaction purposes are recorded by type?
SELECT
    type,
    k_symbol,
    COUNT(trans_id) AS no_of_trans
FROM trans
GROUP BY type, k_symbol
ORDER BY no_of_trans DESC;

-- ============================================================
-- 4. DATA EXPLORATION FINDINGS
-- ============================================================

-- Total transactions: 1,056,320.
-- Accounts with transactions: 4,500.
-- Observed transaction dates: 1993-01-01 through 1998-12-31.
--
-- Preliminary cash-flow classification:
--   PRIJEM = inflow.
--   VYDAJ = outflow.
--   VYBER = withdrawal (outflow).
--
-- Amount quality checks:
--   No negative or NULL amounts were observed.
--   162 transactions have an amount of zero.
--   Zero amounts are retained for now; they contribute nothing
--   to monetary totals but may affect transaction counts.
--
-- Transaction-purpose data:
--   k_symbol contains NULL and visually blank values.
--   Whether blank values are empty strings or whitespace
--   has not yet been checked.
--
-- Working assumption for the next analysis phase:
--   Amounts are non-negative in this dataset; classify inflows
--   and outflows using transaction type rather than amount sign.
--
-- Scope: This initial exploration does not yet validate account
-- relationships, transaction uniqueness or balance reconciliation.
