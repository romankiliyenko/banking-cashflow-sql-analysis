-- Banking Cash Flow & Account Monitoring
-- Source dataset is the Berka Financial Dataset (PKDD'99).

USE financial;

-- Business Question:
-- How common are negative monthly net cash flows across bank accounts?

-- Objective:
-- Calculate the number and percentage of observed account-months with negative net cash flow.

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
	COUNT(*) AS total_account_months, 
    SUM(CASE WHEN total_inflows - total_outflows < 0 THEN 1 ELSE 0 END) AS negative_months,
    ROUND(
        100.0 * SUM(CASE WHEN total_inflows - total_outflows < 0 THEN 1 ELSE 0 END)
        / COUNT(*),
        2
    ) AS negative_months_pct
FROM monthly_cash_flows;

-- Finding:
-- Approximately 39.2% of observed account-months have negative net cash flow.
--
-- Business Implication:
-- A single negative month is too common to serve as a standalone account monitoring signal.
--
-- Next Step:
-- Analyze the frequency of negative months at the individual account level.

-- Business Question:
-- How frequently does each bank account experience negative monthly net cash flow?

-- Objective:
-- Calculate the number and percentage of negative cash flow months for each individual account.

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
    COUNT(*) AS observed_months, 
    SUM(CASE WHEN total_inflows - total_outflows < 0 THEN 1 ELSE 0 END) AS negative_months,
    ROUND(
        100.0 * SUM(CASE WHEN total_inflows - total_outflows < 0 THEN 1 ELSE 0 END)
        / COUNT(*),
        2
    ) AS negative_months_pct
FROM monthly_cash_flows
GROUP BY account_id
ORDER BY negative_months_pct DESC, observed_months DESC
LIMIT 10;

-- Finding:
-- Accounts with high negative cash flow frequency show different lengths of transaction history.
--
-- Account 1056: 18 negative months out of 24 (75.00%).
-- Account 3554: 48 negative months out of 71 (67.61%).
--
-- Interpretation:
-- Negative cash flow frequency alone is insufficient to determine which accounts require priority review.
-- The duration, magnitude, and timing of negative cash flows should also be investigated.

-- Business Question:
-- How has account 3554's monthly cash flow evolved over its observed history?

-- Objective:
-- Examine monthly inflows, outflows, and net cash flow to understand whether negative months are isolated or persistent.

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
SELECT account_id, month, total_inflows, total_outflows, total_inflows - total_outflows AS net_cash_flow
FROM monthly_cash_flows
WHERE account_id = 3554
ORDER BY month;

-- Business Question:
-- Does account 3554 experience consecutive months of negative net cash flow?

-- Objective:
-- Identify periods where net cash flow remains negative for at least two consecutive calendar months.

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
cash_flow_history AS (
SELECT account_id, month, total_inflows - total_outflows AS net_cash_flow,
LAG(month) OVER(PARTITION BY account_id ORDER BY month) AS previous_month,
LAG(total_inflows - total_outflows) OVER(PARTITION BY account_id ORDER BY month) AS previous_net_cash_flow
FROM monthly_cash_flows)
SELECT account_id, month, net_cash_flow, previous_month, previous_net_cash_flow
FROM cash_flow_history
WHERE account_id = 3554
AND net_cash_flow < 0
AND previous_net_cash_flow < 0
AND PERIOD_DIFF(
    REPLACE(month, '-', ''),
    REPLACE(previous_month, '-', '')
) = 1;

-- Business Question:
-- How can we identify the beginning of each consecutive negative cash flow period?

-- Objective:
-- Flag the first month of every negative cash flow streak, accounting for missing calendar months.

WITH monthly_cash_flows AS (
	SELECT 
		account_id,
		DATE_FORMAT(date, '%Y-%m') AS month,
		SUM(
			CASE
				WHEN type = 'PRIJEM' THEN amount
				ELSE 0
			END
		) AS total_inflows,
		SUM(
			CASE
				WHEN type IN ('VYDAJ' , 'VYBER') THEN amount
				ELSE 0
			END
		) AS total_outflows,
    COUNT(trans_id) AS transaction_count
	FROM trans
	GROUP BY account_id , month
),

cash_flow_history AS (
	SELECT 
		account_id, 
        month, 
        total_inflows - total_outflows AS net_cash_flow,
		LAG(month) OVER(
			PARTITION BY account_id
			ORDER BY month
		) AS previous_month,
		LAG(total_inflows - total_outflows) OVER(
			PARTITION BY account_id 
            ORDER BY month
		) AS previous_net_cash_flow
	FROM monthly_cash_flows
),

streak_flags AS (
	SELECT 
		account_id, 
        month, 
        net_cash_flow, 
        previous_month, 
        previous_net_cash_flow,
		CASE 
			WHEN net_cash_flow < 0 
				AND (
					previous_month IS NULL 
                    OR previous_net_cash_flow >= 0 
                    OR PERIOD_DIFF(
						REPLACE(month, '-', ''),
                        REPLACE(previous_month, '-', '')
                        ) > 1
				)
			THEN 1
			ELSE 0
		END AS is_new_negative_streak
	FROM cash_flow_history
    ),
    
numbered_streaks AS (
	SELECT 
		*, 
        SUM(is_new_negative_streak) OVER (
			PARTITION BY account_id 
            ORDER BY month
		) AS streak_id
    FROM streak_flags
)
SELECT
    account_id,
    month,
    net_cash_flow,
    is_new_negative_streak,
    CASE
        WHEN net_cash_flow < 0 THEN streak_id
        ELSE NULL
    END AS negative_streak_id
FROM numbered_streaks
WHERE account_id = 3554
ORDER BY month;

-- Business Question:
-- How long does each consecutive negative cash flow period last?

-- Objective:
-- Calculate the start month, end month, and duration of each negative cash flow streak.

WITH monthly_cash_flows AS (
	SELECT 
		account_id,
		DATE_FORMAT(date, '%Y-%m') AS month,
		SUM(
			CASE
				WHEN type = 'PRIJEM' THEN amount
				ELSE 0
			END
		) AS total_inflows,
		SUM(
			CASE
				WHEN type IN ('VYDAJ' , 'VYBER') THEN amount
				ELSE 0
			END
		) AS total_outflows,
    COUNT(trans_id) AS transaction_count
	FROM trans
	GROUP BY account_id , month
),

cash_flow_history AS (
	SELECT 
		account_id, 
        month, 
        total_inflows - total_outflows AS net_cash_flow,
		LAG(month) OVER(
			PARTITION BY account_id
			ORDER BY month
		) AS previous_month,
		LAG(total_inflows - total_outflows) OVER(
			PARTITION BY account_id 
            ORDER BY month
		) AS previous_net_cash_flow
	FROM monthly_cash_flows
),

streak_flags AS (
	SELECT 
		account_id, 
        month, 
        net_cash_flow, 
        previous_month, 
        previous_net_cash_flow,
		CASE 
			WHEN net_cash_flow < 0 
				AND (
					previous_month IS NULL 
                    OR previous_net_cash_flow >= 0 
                    OR PERIOD_DIFF(
						REPLACE(month, '-', ''),
                        REPLACE(previous_month, '-', '')
                        ) > 1
				)
			THEN 1
			ELSE 0
		END AS is_new_negative_streak
	FROM cash_flow_history
    ),
    
numbered_streaks AS (
	SELECT 
		*, 
        SUM(is_new_negative_streak) OVER (
			PARTITION BY account_id 
            ORDER BY month
		) AS streak_id
    FROM streak_flags
)
SELECT
    account_id,
    streak_id,
    MIN(month) AS start_month,
    MAX(month) AS end_month, 
	COUNT(*) AS duration_months
FROM numbered_streaks
WHERE account_id = 3554
AND net_cash_flow < 0
GROUP BY account_id, streak_id
ORDER BY start_month;

-- Business Question:
-- Which bank accounts experience the longest consecutive periods of negative net cash flow?

-- Objective:
-- Identify and rank the longest negative cash flow streaks across all bank accounts.

WITH monthly_cash_flows AS (
	SELECT 
		account_id,
		DATE_FORMAT(date, '%Y-%m') AS month,
		SUM(
			CASE
				WHEN type = 'PRIJEM' THEN amount
				ELSE 0
			END
		) AS total_inflows,
		SUM(
			CASE
				WHEN type IN ('VYDAJ' , 'VYBER') THEN amount
				ELSE 0
			END
		) AS total_outflows,
    COUNT(trans_id) AS transaction_count
	FROM trans
	GROUP BY account_id , month
),

cash_flow_history AS (
	SELECT 
		account_id, 
        month, 
        total_inflows - total_outflows AS net_cash_flow,
		LAG(month) OVER(
			PARTITION BY account_id
			ORDER BY month
		) AS previous_month,
		LAG(total_inflows - total_outflows) OVER(
			PARTITION BY account_id 
            ORDER BY month
		) AS previous_net_cash_flow
	FROM monthly_cash_flows
),

streak_flags AS (
	SELECT 
		account_id, 
        month, 
        net_cash_flow, 
        previous_month, 
        previous_net_cash_flow,
		CASE 
			WHEN net_cash_flow < 0 
				AND (
					previous_month IS NULL 
                    OR previous_net_cash_flow >= 0 
                    OR PERIOD_DIFF(
						REPLACE(month, '-', ''),
                        REPLACE(previous_month, '-', '')
                        ) > 1
				)
			THEN 1
			ELSE 0
		END AS is_new_negative_streak
	FROM cash_flow_history
    ),
    
numbered_streaks AS (
	SELECT 
		*, 
        SUM(is_new_negative_streak) OVER (
			PARTITION BY account_id 
            ORDER BY month
		) AS streak_id
    FROM streak_flags
)
SELECT
    account_id,
    streak_id,
    MIN(month) AS start_month,
    MAX(month) AS end_month, 
	COUNT(*) AS duration_months
FROM numbered_streaks
WHERE net_cash_flow < 0
GROUP BY account_id, streak_id
ORDER BY duration_months DESC
LIMIT 20;

-- Business Question:
-- What is the longest consecutive negative cash flow period for each bank account?

-- Objective:
-- Calculate the maximum negative streak duration for each account.

WITH monthly_cash_flows AS (
	SELECT 
		account_id,
		DATE_FORMAT(date, '%Y-%m') AS month,
		SUM(
			CASE
				WHEN type = 'PRIJEM' THEN amount
				ELSE 0
			END
		) AS total_inflows,
		SUM(
			CASE
				WHEN type IN ('VYDAJ' , 'VYBER') THEN amount
				ELSE 0
			END
		) AS total_outflows,
    COUNT(trans_id) AS transaction_count
	FROM trans
	GROUP BY account_id , month
),

cash_flow_history AS (
	SELECT 
		account_id, 
        month, 
        total_inflows - total_outflows AS net_cash_flow,
		LAG(month) OVER(
			PARTITION BY account_id
			ORDER BY month
		) AS previous_month,
		LAG(total_inflows - total_outflows) OVER(
			PARTITION BY account_id 
            ORDER BY month
		) AS previous_net_cash_flow
	FROM monthly_cash_flows
),

streak_flags AS (
	SELECT 
		account_id, 
        month, 
        net_cash_flow, 
        previous_month, 
        previous_net_cash_flow,
		CASE 
			WHEN net_cash_flow < 0 
				AND (
					previous_month IS NULL 
                    OR previous_net_cash_flow >= 0 
                    OR PERIOD_DIFF(
						REPLACE(month, '-', ''),
                        REPLACE(previous_month, '-', '')
                        ) > 1
				)
			THEN 1
			ELSE 0
		END AS is_new_negative_streak
	FROM cash_flow_history
    ),
    
numbered_streaks AS (
	SELECT 
		*, 
        SUM(is_new_negative_streak) OVER (
			PARTITION BY account_id 
            ORDER BY month
		) AS streak_id
    FROM streak_flags
),

negative_streaks AS (
	SELECT
		account_id,
        streak_id,
        COUNT(*) AS duration_months
	FROM numbered_streaks
    WHERE net_cash_flow < 0
    GROUP BY account_id, streak_id
)
SELECT
    account_id,
    MAX(duration_months) AS longest_negative_streak
FROM negative_streaks
GROUP BY account_id
ORDER BY longest_negative_streak DESC
LIMIT 20;

-- Business Question:
-- How many bank accounts experience prolonged periods of negative monthly net cash flow?

-- Objective:
-- Count accounts with negative cash flow streaks lasting at least 3, 6, and 12 consecutive months.

WITH monthly_cash_flows AS (
	SELECT 
		account_id,
		DATE_FORMAT(date, '%Y-%m') AS month,
		SUM(
			CASE
				WHEN type = 'PRIJEM' THEN amount
				ELSE 0
			END
		) AS total_inflows,
		SUM(
			CASE
				WHEN type IN ('VYDAJ' , 'VYBER') THEN amount
				ELSE 0
			END
		) AS total_outflows,
    COUNT(trans_id) AS transaction_count
	FROM trans
	GROUP BY account_id , month
),

cash_flow_history AS (
	SELECT 
		account_id, 
        month, 
        total_inflows - total_outflows AS net_cash_flow,
		LAG(month) OVER(
			PARTITION BY account_id
			ORDER BY month
		) AS previous_month,
		LAG(total_inflows - total_outflows) OVER(
			PARTITION BY account_id 
            ORDER BY month
		) AS previous_net_cash_flow
	FROM monthly_cash_flows
),

streak_flags AS (
	SELECT 
		account_id, 
        month, 
        net_cash_flow, 
        previous_month, 
        previous_net_cash_flow,
		CASE 
			WHEN net_cash_flow < 0 
				AND (
					previous_month IS NULL 
                    OR previous_net_cash_flow >= 0 
                    OR PERIOD_DIFF(
						REPLACE(month, '-', ''),
                        REPLACE(previous_month, '-', '')
                        ) > 1
				)
			THEN 1
			ELSE 0
		END AS is_new_negative_streak
	FROM cash_flow_history
    ),
    
numbered_streaks AS (
	SELECT 
		*, 
        SUM(is_new_negative_streak) OVER (
			PARTITION BY account_id 
            ORDER BY month
		) AS streak_id
    FROM streak_flags
),

negative_streaks AS (
	SELECT
		account_id,
        streak_id,
        COUNT(*) AS duration_months
	FROM numbered_streaks
    WHERE net_cash_flow < 0
    GROUP BY account_id, streak_id
),

longest_streak_per_account AS (
	SELECT 
		account_id,
        MAX(duration_months) AS longest_negative_streak
	FROM negative_streaks
    GROUP BY account_id
)
SELECT
	COUNT(*) AS accounts_with_negative_streak,
    SUM(
		CASE
			WHEN longest_negative_streak >= 3 THEN 1
            ELSE 0
		END
	) AS accounts_3plus_months,
    SUM(
		CASE
			WHEN longest_negative_streak >= 6 THEN 1
            ELSE 0
		END
	) AS accounts_6plus_months,
    SUM(
		CASE
			WHEN longest_negative_streak >= 12 THEN 1
            ELSE 0
		END
	) AS accounts_12plus_months
FROM longest_streak_per_account;

-- Finding:
-- 4,494 out of 4,500 accounts experienced at least one month of negative net cash flow.
--
-- 3,307 accounts (73.49%) had negative streaks lasting at least 3 consecutive months.
--
-- 330 accounts (7.33%) had streaks of at least 6 months, while only 4 accounts (0.09%)
-- experienced streaks of at least 12 months.
--
-- Business Implication:
-- Three-month negative streaks are too common to provide strong account prioritization.
-- Longer streaks may help narrow the monitoring population for further investigation.
--
-- Limitation:
-- Accounts have different observation periods.
-- Negative cash flow alone does not establish financial distress or credit risk.   

-- Business Question:
-- How large was the net cash outflow during each negative cash flow
-- streak lasting at least six consecutive calendar months?

WITH monthly_cash_flows AS (
	SELECT 
		account_id,
		DATE_FORMAT(date, '%Y-%m') AS month,
		SUM(
			CASE
				WHEN type = 'PRIJEM' THEN amount
				ELSE 0
			END
		) AS total_inflows,
		SUM(
			CASE
				WHEN type IN ('VYDAJ' , 'VYBER') THEN amount
				ELSE 0
			END
		) AS total_outflows,
    COUNT(trans_id) AS transaction_count
	FROM trans
	GROUP BY account_id , month
),

cash_flow_history AS (
	SELECT 
		account_id, 
        month, 
        total_inflows - total_outflows AS net_cash_flow,
		LAG(month) OVER(
			PARTITION BY account_id
			ORDER BY month
		) AS previous_month,
		LAG(total_inflows - total_outflows) OVER(
			PARTITION BY account_id 
            ORDER BY month
		) AS previous_net_cash_flow
	FROM monthly_cash_flows
),

streak_flags AS (
	SELECT 
		account_id, 
        month, 
        net_cash_flow, 
        previous_month, 
        previous_net_cash_flow,
		CASE 
			WHEN net_cash_flow < 0 
				AND (
					previous_month IS NULL 
                    OR previous_net_cash_flow >= 0 
                    OR PERIOD_DIFF(
						REPLACE(month, '-', ''),
                        REPLACE(previous_month, '-', '')
                        ) > 1
				)
			THEN 1
			ELSE 0
		END AS is_new_negative_streak
	FROM cash_flow_history
    ),
    
numbered_streaks AS (
	SELECT 
		*, 
        SUM(is_new_negative_streak) OVER (
			PARTITION BY account_id 
            ORDER BY month
		) AS streak_id
    FROM streak_flags
)
SELECT
    account_id,
    streak_id,
    MIN(month) AS start_month,
    MAX(month) AS end_month, 
	COUNT(*) AS duration_months,
    SUM(net_cash_flow) AS streak_net_cash_flow
FROM numbered_streaks
WHERE net_cash_flow < 0
GROUP BY account_id, streak_id
HAVING duration_months >= 6
ORDER BY streak_net_cash_flow
;

-- Business Question:
-- Was the net cash outflow spread across the six-month streak, or concentrated in one or two months?

WITH monthly_cash_flows AS (
	SELECT 
		account_id,
		DATE_FORMAT(date, '%Y-%m') AS month,
		SUM(
			CASE
				WHEN type = 'PRIJEM' THEN amount
				ELSE 0
			END
		) AS total_inflows,
		SUM(
			CASE
				WHEN type IN ('VYDAJ' , 'VYBER') THEN amount
				ELSE 0
			END
		) AS total_outflows,
    COUNT(trans_id) AS transaction_count
	FROM trans
	GROUP BY account_id , month
)
SELECT 
	account_id, 
    month, 
    total_inflows, 
    total_outflows, 
    total_inflows - total_outflows AS net_cash_flow
FROM monthly_cash_flows
WHERE ((account_id = 3711 AND month BETWEEN '1998-01' AND '1998-06') OR (account_id = 5735 AND month BETWEEN '1995-08' AND '1996-01'))
ORDER BY account_id, month;

-- Business Question
-- What percentage of each streak's total net outflow occurred in its largest outflow month?

WITH monthly_cash_flows AS (
	SELECT 
		account_id,
		DATE_FORMAT(date, '%Y-%m') AS month,
		SUM(
			CASE
				WHEN type = 'PRIJEM' THEN amount
				ELSE 0
			END
		) AS total_inflows,
		SUM(
			CASE
				WHEN type IN ('VYDAJ' , 'VYBER') THEN amount
				ELSE 0
			END
		) AS total_outflows,
    COUNT(trans_id) AS transaction_count
	FROM trans
	GROUP BY account_id , month
),

cash_flow_history AS (
	SELECT 
		account_id, 
        month, 
        total_inflows - total_outflows AS net_cash_flow,
		LAG(month) OVER(
			PARTITION BY account_id
			ORDER BY month
		) AS previous_month,
		LAG(total_inflows - total_outflows) OVER(
			PARTITION BY account_id 
            ORDER BY month
		) AS previous_net_cash_flow
	FROM monthly_cash_flows
),

streak_flags AS (
	SELECT 
		account_id, 
        month, 
        net_cash_flow, 
        previous_month, 
        previous_net_cash_flow,
		CASE 
			WHEN net_cash_flow < 0 
				AND (
					previous_month IS NULL 
                    OR previous_net_cash_flow >= 0 
                    OR PERIOD_DIFF(
						REPLACE(month, '-', ''),
                        REPLACE(previous_month, '-', '')
                        ) > 1
				)
			THEN 1
			ELSE 0
		END AS is_new_negative_streak
	FROM cash_flow_history
    ),
    
numbered_streaks AS (
	SELECT 
		*, 
        SUM(is_new_negative_streak) OVER (
			PARTITION BY account_id 
            ORDER BY month
		) AS streak_id
    FROM streak_flags
)
SELECT
    account_id,
    streak_id,
    MIN(month) AS start_month,
    MAX(month) AS end_month, 
	COUNT(*) AS duration_months,
    SUM(net_cash_flow) AS streak_net_cash_flow,
    ROUND(100.0 * MIN(net_cash_flow) / SUM(net_cash_flow), 2) AS largest_month_share_pct
FROM numbered_streaks
WHERE net_cash_flow < 0
GROUP BY account_id, streak_id
HAVING duration_months >= 6
ORDER BY streak_net_cash_flow
;

-- Business Question
-- Which operations drove account 3711's outflows in January 1998?

SELECT 
    account_id,
    type,
    operation,
    COUNT(trans_id) AS number_of_transactions,
    SUM(amount) AS total_amount,
    MAX(amount) AS max_amount
FROM
    trans
WHERE
    account_id = 3711
        AND date >= '1998-01-01'
        AND date < '1998-02-01'
        AND type IN ('VYDAJ', 'VYBER')
GROUP BY account_id, type, operation
ORDER BY total_amount DESC;

-- January 1998 accounted for 77.92% of account 3711's six-month net outflow.
-- Nine withdrawals totaled 72,215 of the month's 79,898 in gross outflows.
-- The largest withdrawal accounted for 45.4% of monthly gross outflows.
