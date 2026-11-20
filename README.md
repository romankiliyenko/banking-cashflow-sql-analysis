# Banking Cash Flow & Account Monitoring

**A SQL case study on which accounts merit a closer look after several months of net outflows.**

I analyzed 1,056,320 transactions across 4,500 accounts from 1993 to 1998. I started by checking how often accounts had consecutive months of negative cash flow, then looked at how much of each streak's outflow came from a single month.

## Key findings

**Three consecutive negative months were common.** A six-month screen narrowed the historical review list to **330 accounts (7.33%)**. The thresholds below are exploratory and use all 4,500 accounts with recorded transactions as the denominator.

| Longest negative streak | Accounts | Share of accounts |
| --- | ---: | ---: |
| At least 3 consecutive months | 3,307 | 73.49% |
| At least 6 consecutive months | 330 | 7.33% |
| At least 12 consecutive months | 4 | 0.09% |

**Two six-month streaks had similar total net outflows but different monthly patterns.** The largest month accounted for about 78% of the net outflow on account `3711` and about 30% on account `5735`.

| Account | Streak | Net cash flow over the streak | Share of net outflow in the largest month |
| --- | --- | ---: | ---: |
| `3711` | Jan–Jun 1998 | −102,353 | 77.92% |
| `5735` | Aug 1995–Jan 1996 | −95,244 | 29.87% |

I traced account `3711`'s January spike back to the individual transactions. Nine withdrawals totaled **72,215** of the month's **79,898** in gross outflows. The largest withdrawal was **36,300**, or **45.4%** of January's gross outflows.

For manual review, I'd use duration to narrow the list, then compare the size and concentration of the outflow. The monthly breakdown helps decide whether to investigate a single month or look across the full period.

## Method and checks

1. **Classify and reconcile transactions.** I used `PRIJEM` for inflows and `VYDAJ` and `VYBER` for outflows, then reconciled the account-level totals against sums from the source transactions by type.
2. **Build monthly cash flows.** Each row represents one account in one month with recorded activity. Net cash flow is inflows minus outflows. The continuity check found **158 gaps across 103 accounts**, so month-over-month comparisons require adjacent calendar months.
3. **Measure streaks.** A streak is a run of consecutive calendar months with negative net cash flow. A missing or non-negative month breaks the run. I used `LAG()` to identify where runs started and a cumulative `SUM() OVER (...)` to assign streak IDs before aggregating duration and outflow.

Accounts have different lengths of observed history, which affects their opportunity to record a long streak. The results identify historical cases for manual review. Assessing financial distress or credit risk would require additional evidence.

## Reproduce the analysis

The source is the historical Berka Financial Dataset (PKDD’99). The scripts expect the CTU version in the `financial` schema and read transactions from `financial.trans`. Connection and download instructions are on the [CTU dataset page](https://relational.fel.cvut.cz/dataset/Financial).

Open the dataset in MySQL Workbench or another compatible client. For a local import, use a server that supports CTEs and window functions. Run the scripts in this order.

| Script | Output |
| --- | --- |
| [01_data_exploration.sql](sql/01_data_exploration.sql) | Transaction coverage, categories, and amount checks |
| [02_cash_flow_analysis.sql](sql/02_cash_flow_analysis.sql) | Account and monthly cash flows, reconciliation, and calendar gaps |
| [03_account_monitoring.sql](sql/03_account_monitoring.sql) | Streak durations, threshold counts, and the account case studies |
