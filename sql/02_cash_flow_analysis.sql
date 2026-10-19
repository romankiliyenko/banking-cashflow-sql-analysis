-- Banking Cash Flow & Account Monitoring
-- File: 02_cash_flow_analysis.sql
-- Dataset: Berka Financial Dataset (PKDD'99)
-- Scope: Account-level cash flows, monthly analysis, reconciliations,
--        and quality checks for consecutive-month comparisons.
-- The queries are retained as sequential, independently runnable analysis steps.

USE financial;

-- Business Question:
-- How much money has flowed into and out of each bank account during the observed period?

-- Objective:
-- Calculate total inflows and total outflows for each account.

SELECT 
	account_id, 
    SUM(
		CASE 
			WHEN type = 'PRIJEM' THEN amount 
            ELSE 0 
		END
	) AS total_inflows, 
    SUM(
		CASE
			WHEN type IN ('VYDAJ','VYBER') THEN amount
            ELSE 0
		END
	) AS total_outflows
FROM trans
GROUP BY account_id;

-- Business Question:
-- What is the net cash flow of each bank account over the observed period?

-- Objective:
-- Calculate net cash flow as total inflows minus total outflows using a CTE.

WITH account_cash_flows AS (SELECT 
	account_id, 
    SUM(
		CASE 
			WHEN type = 'PRIJEM' THEN amount 
            ELSE 0 
		END
	) AS total_inflows, 
    SUM(
		CASE
			WHEN type IN ('VYDAJ','VYBER') THEN amount
            ELSE 0
		END
	) AS total_outflows
FROM trans
GROUP BY account_id)
SELECT 
	account_id, 
    total_inflows, 
    total_outflows, 
    total_inflows - total_outflows AS net_cash_flow
FROM account_cash_flows;

-- Business Question:
-- Do account-level cash flow totals reconcile with the underlying transaction data?

-- Objective:
-- Validate the number of accounts and aggregate inflows, outflows, and net cash flow.

WITH account_cash_flows AS (SELECT 
	account_id, 
    SUM(
		CASE 
			WHEN type = 'PRIJEM' THEN amount 
            ELSE 0 
		END
	) AS total_inflows, 
    SUM(
		CASE
			WHEN type IN ('VYDAJ','VYBER') THEN amount
            ELSE 0
		END
	) AS total_outflows
FROM trans
GROUP BY account_id)
SELECT COUNT(*) AS total_accounts, SUM(total_inflows) AS total_inflows, SUM(total_outflows) AS total_outflows, SUM(total_inflows) -  SUM(total_outflows) AS total_net_cash_flow
FROM account_cash_flows;

-- Observed reconciliation totals:
-- Accounts with transactions: 4,500
-- Total inflows: 3,227,482,664
-- Total outflows: 3,030,379,533
-- Net cash flow: +197,103,131

-- Business Question:
-- Do the calculated cash flow totals match the original transaction amounts?

-- Objective:
-- Independently calculate total transaction amounts by type and compare them with the account-level cash flow summary.

SELECT 
	type, 
    SUM(amount) AS total_amount
FROM trans
GROUP BY type;

SELECT
    SUM(amount) AS total_outflows
FROM trans
WHERE type IN ('VYDAJ', 'VYBER');

-- Business Question:
-- How do cash inflows and outflows vary by month for each bank account?

-- Objective:
-- Calculate monthly inflows, outflows, and transaction counts for each account.

SELECT 
    account_id,
    DATE_FORMAT(date, '%Y-%m') AS month,
    SUM(CASE
        WHEN type = 'PRIJEM' THEN amount
        ELSE 0
    END) AS total_inflows,
    SUM(CASE
        WHEN type IN ('VYDAJ' , 'VYBER') THEN amount
        ELSE 0
    END) AS total_outflows,
    COUNT(trans_id) AS transaction_count
FROM
    trans
GROUP BY account_id , month
ORDER BY account_id, month;

-- Business Question:
-- What is the monthly net cash flow of each bank account?

-- Objective:
-- Calculate monthly net cash flow as the difference between monthly inflows and outflows using a CTE.

WITH monthly_cash_flows AS (
SELECT 
    account_id,
    DATE_FORMAT(date, '%Y-%m') AS month,
    SUM(CASE
        WHEN type = 'PRIJEM' THEN amount
        ELSE 0
    END) AS total_inflows,
    SUM(CASE
        WHEN type IN ('VYDAJ' , 'VYBER') THEN amount
        ELSE 0
    END) AS total_outflows,
    COUNT(trans_id) AS transaction_count
FROM
    trans
GROUP BY account_id , month)
SELECT
	account_id,
    month,
    total_inflows,
    total_outflows,
    total_inflows - total_outflows AS net_cash_flow,
    transaction_count
FROM monthly_cash_flows
ORDER BY account_id, month;

-- Business Question:
-- How does each account's net cash flow change compared to its previous observed month?

-- Objective:
-- Compare monthly net cash flow with the previous observed month's value using LAG().

WITH monthly_cash_flows AS (
SELECT 
    account_id,
    DATE_FORMAT(date, '%Y-%m') AS month,
    SUM(CASE
        WHEN type = 'PRIJEM' THEN amount
        ELSE 0
    END) AS total_inflows,
    SUM(CASE
        WHEN type IN ('VYDAJ' , 'VYBER') THEN amount
        ELSE 0
    END) AS total_outflows,
    COUNT(trans_id) AS transaction_count
FROM
    trans
GROUP BY account_id , month)
SELECT 
	account_id, 
    month, 
    total_inflows - total_outflows AS net_cash_flow, 
    LAG(total_inflows - total_outflows) OVER(PARTITION BY account_id ORDER BY month) AS previous_net_cash_flow
FROM monthly_cash_flows;

-- Business Question:
-- How much has each account's net cash flow increased or decreased compared to the previous observed month?

-- Objective:
-- Calculate the difference from the previous observed month.
-- This is not necessarily a consecutive calendar-month comparison.

WITH monthly_cash_flows AS (
SELECT 
    account_id,
    DATE_FORMAT(date, '%Y-%m') AS month,
    SUM(CASE
        WHEN type = 'PRIJEM' THEN amount
        ELSE 0
    END) AS total_inflows,
    SUM(CASE
        WHEN type IN ('VYDAJ' , 'VYBER') THEN amount
        ELSE 0
    END) AS total_outflows,
    COUNT(trans_id) AS transaction_count
FROM
    trans
GROUP BY account_id , month),
cash_flow_comparison AS (
SELECT 
	account_id, 
    month, 
    total_inflows - total_outflows AS net_cash_flow, 
    LAG(total_inflows - total_outflows) OVER(PARTITION BY account_id ORDER BY month) AS previous_net_cash_flow
FROM monthly_cash_flows)
SELECT 
	account_id,
    month,
    net_cash_flow,
    previous_net_cash_flow,
    net_cash_flow - previous_net_cash_flow AS cash_flow_change
FROM cash_flow_comparison
ORDER BY account_id, month;

-- Business Question:
-- Are there gaps in the monthly transaction history of individual bank accounts?

-- Objective:
-- Identify accounts where consecutive observed months are more than one calendar month apart.

WITH monthly_cash_flows AS (
SELECT 
    account_id,
    DATE_FORMAT(date, '%Y-%m') AS month,
    SUM(CASE
        WHEN type = 'PRIJEM' THEN amount
        ELSE 0
    END) AS total_inflows,
    SUM(CASE
        WHEN type IN ('VYDAJ' , 'VYBER') THEN amount
        ELSE 0
    END) AS total_outflows,
    COUNT(trans_id) AS transaction_count
FROM
    trans
GROUP BY account_id , month),
month_history AS (
    SELECT
        account_id,
        month,
        LAG(month) OVER (
            PARTITION BY account_id
            ORDER BY month
        ) AS previous_month
    FROM monthly_cash_flows
)
SELECT 
	account_id,
	month, 
    previous_month,
    PERIOD_DIFF(REPLACE(month, '-', ''), REPLACE(previous_month, '-', '')) AS months_between
FROM month_history
WHERE PERIOD_DIFF(REPLACE(month, '-', ''), REPLACE(previous_month, '-', '')) > 1;

-- Business Question:
-- How widespread are gaps in the monthly transaction histories of bank accounts?

-- Objective:
-- Count observed-month gaps, affected accounts, and the largest gap.

WITH monthly_cash_flows AS (
SELECT 
    account_id,
    DATE_FORMAT(date, '%Y-%m') AS month,
    SUM(CASE
        WHEN type = 'PRIJEM' THEN amount
        ELSE 0
    END) AS total_inflows,
    SUM(CASE
        WHEN type IN ('VYDAJ' , 'VYBER') THEN amount
        ELSE 0
    END) AS total_outflows,
    COUNT(trans_id) AS transaction_count
FROM
    trans
GROUP BY account_id , month),
month_history AS (
    SELECT
        account_id,
        month,
        LAG(month) OVER (
            PARTITION BY account_id
            ORDER BY month
        ) AS previous_month
    FROM monthly_cash_flows
),
month_difference AS (
SELECT 
	account_id,
	month, 
    previous_month,
    PERIOD_DIFF(REPLACE(month, '-', ''), REPLACE(previous_month, '-', '')) AS months_between
FROM month_history
WHERE PERIOD_DIFF(REPLACE(month, '-', ''), REPLACE(previous_month, '-', '')) > 1)
SELECT 
	COUNT(months_between) AS total_gaps,
	COUNT(DISTINCT account_id) AS affected_accounts,
    MAX(months_between) AS max_month_between
FROM month_difference;

-- Finding:
-- 158 gaps were identified across 103 bank accounts.
-- The largest gap between consecutive observed months was 17 months (16 missing calendar months).
--
-- Implication:
-- LAG() does not always refer to the previous calendar month.
--
-- Decision:
-- Month-over-month changes will only be evaluated when the observed months are consecutive.

-- Business Question:
-- How can we accurately measure month-over-month cash flow changes when some accounts have gaps
-- in their transaction histories?

-- Objective:
-- Calculate cash flow changes only for consecutive calendar months.

WITH monthly_cash_flows AS (
SELECT 
    account_id,
    DATE_FORMAT(date, '%Y-%m') AS month,
    SUM(CASE
        WHEN type = 'PRIJEM' THEN amount
        ELSE 0
    END) AS total_inflows,
    SUM(CASE
        WHEN type IN ('VYDAJ' , 'VYBER') THEN amount
        ELSE 0
    END) AS total_outflows,
    COUNT(trans_id) AS transaction_count
FROM
    trans
GROUP BY account_id , month),
cash_flow_comparison AS (
SELECT 
	account_id, 
    month, 
    total_inflows - total_outflows AS net_cash_flow, 
    LAG(total_inflows - total_outflows) OVER(PARTITION BY account_id ORDER BY month) AS previous_net_cash_flow,
    LAG(month) OVER(PARTITION BY account_id ORDER BY month) AS previous_month
FROM monthly_cash_flows)
SELECT
    account_id,
    month,
    previous_month,
    net_cash_flow,
    previous_net_cash_flow,
    PERIOD_DIFF(
        REPLACE(month, '-', ''),
        REPLACE(previous_month, '-', '')
    ) AS months_between,
    CASE
        WHEN PERIOD_DIFF(
            REPLACE(month, '-', ''),
            REPLACE(previous_month, '-', '')
        ) = 1
        THEN net_cash_flow - previous_net_cash_flow
        ELSE NULL
    END AS valid_cash_flow_change
FROM cash_flow_comparison
ORDER BY account_id, month;