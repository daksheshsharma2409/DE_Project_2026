# Baseline Query Timings

## Method

Each of the 30 statements in `queries/workload_30.sql` was run three times with
`EXPLAIN (ANALYZE, BUFFERS)` against the supplied seed data. Write queries ran
inside a transaction that was rolled back after each run. The database ran
PostgreSQL 18.6 on a temporary local instance; the schema had only its primary
key and unique-constraint indexes, with no workload-tuning indexes. Timings
below are the `Execution Time` values in milliseconds. Averages are the
arithmetic mean of the three runs; the total row sums each timing column.

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01: Continue Watching row for profile 7043 | READ | 6.603 | 6.490 | 6.558 | 6.550 |
| R02: Episode counts by season for series 2909 | READ | 0.048 | 0.048 | 0.046 | 0.047 |
| R03: Most-watched titles on 30 June 2026 | READ | 5.808 | 5.572 | 9.718 | 7.033 |
| R04: Kids-safe Comedy genre row | READ | 0.742 | 0.635 | 0.688 | 0.688 |
| R05: Search title names containing "love" | READ | 0.462 | 0.452 | 0.433 | 0.449 |
| R06: My List for profile 7393 | READ | 0.058 | 0.053 | 0.051 | 0.054 |
| R07: Next episode after S1E4 of series 2909 | READ | 0.023 | 0.023 | 0.023 | 0.023 |
| R08: June 2026 binge sessions | READ | 7.839 | 7.789 | 7.872 | 7.833 |
| R09: 2026 completion rate per genre | READ | 26.341 | 24.942 | 26.080 | 25.788 |
| R10: Sign in by case-insensitive email | READ | 2.152 | 2.171 | 1.995 | 2.106 |
| R11: Failed June invoices for active/on-hold accounts | READ | 7.085 | 6.785 | 7.100 | 6.990 |
| R12: 2026 monthly cancellations and average tenure | READ | 1.333 | 1.328 | 1.331 | 1.331 |
| R13: Unwatched episodes of series 2523 | READ | 17.659 | 17.652 | 18.423 | 17.911 |
| R14: Kids profiles watching above their maturity limit | READ | 21.049 | 21.273 | 21.247 | 21.190 |
| R15: Active accounts and monthly revenue per plan | READ | 4.096 | 4.096 | 4.056 | 4.083 |
| R16: Account-sharing check by hour | READ | 130.956 | 127.434 | 127.829 | 128.740 |
| R17: Share of LOVE ratings for originals vs licensed titles | READ | 5.339 | 5.297 | 5.210 | 5.282 |
| R18: 2026 viewing hours per device and month | READ | 23.528 | 23.286 | 23.336 | 23.383 |
| R19: Views and latest view for every Netflix Original | READ | 6373.165 | 6416.214 | 6434.265 | 6407.881 |
| R20: 10 titles added to most My Lists in June 2026 | READ | 2.660 | 2.772 | 2.971 | 2.801 |
| R21: Overdue billing dates for accounts on hold | READ | 1.091 | 1.155 | 1.094 | 1.113 |
| R22: Licensed titles leaving in July 2026 | READ | 0.169 | 0.156 | 0.186 | 0.170 |
| R23: Viewing activity page 6,001 | READ | 38.690 | 38.376 | 38.184 | 38.417 |
| R24: Profiles for account 1409 | READ | 1.888 | 1.873 | 1.835 | 1.865 |
| R25: Titles sharing at least two genres with series 2909 | READ | 0.634 | 0.601 | 0.772 | 0.669 |
| W01: Start episode S1E5 of series 2909 | WRITE | 0.352 | 0.355 | 0.316 | 0.341 |
| W02: Add series 2523 to My List | WRITE | 0.367 | 0.372 | 0.334 | 0.358 |
| W03: Downgrade account 1409 to STANDARD | WRITE | 0.251 | 0.235 | 0.244 | 0.243 |
| W04: Create July 2026 invoices for active accounts | WRITE | 69.939 | 86.348 | 81.783 | 79.357 |
| W05: Put accounts with failed latest invoice on hold | WRITE | 11.052 | 11.010 | 10.658 | 10.907 |
| **Total (sum of all 30)** | | **6761.379** | **6814.793** | **6834.638** | **6803.603** |

## Plan scans and baseline observations

Scan nodes below are from the third run's plan. Constraint-created primary-key
and unique indexes are included in those plans.

| Query | Scan type(s) | Why it is relatively slow or fast |
|---|---|---|
| R01 | Seq Scan on `viewing_activity`; Index Scan on `titles` | Reads the activity table to find one profile's unfinished plays; no profile/time workload index exists. |
| R02 | Index Scan on `episodes` | The unique `(title_id, season_no, episode_no)` index narrows the rows to one series. |
| R03 | Seq Scan on `viewing_activity`; Index Scan on `titles` | Scans activity to isolate one day's plays, then aggregates viewers by title. |
| R04 | Seq Scan on `titles`, `title_genres`, and `genres` | All three relations are small in the seed dataset, so sequential scans are inexpensive. |
| R05 | Seq Scan on `titles` | The leading-wildcard `ILIKE '%love%'` predicate cannot use a normal B-tree index. |
| R06 | Index Scans on `my_list` and `titles` | The My List primary key begins with `profile_id`, and title lookups use the title primary key. |
| R07 | Index Scan on `episodes` | The unique series/season/episode index supports the next-episode lookup and ordering. |
| R08 | Seq Scan on `viewing_activity` | Scans and groups activity records by profile, series, and day for the June binge report. |
| R09 | Seq Scans on `viewing_activity`, `title_genres`, and `genres` | Reads the year's activity and joins genre associations before aggregating completion rates. |
| R10 | Seq Scan on `accounts` | `lower(email)` does not match the ordinary unique index on `email`. |
| R11 | Seq Scans on `accounts` and `invoices` | Finds failed invoices and eligible account statuses without workload-specific indexes. |
| R12 | Seq Scan on `accounts` | Evaluates cancellation status and year, then groups and averages tenure. |
| R13 | Index Scan on `episodes`; Seq Scan on `viewing_activity` | The anti-subquery scans activity. Its `NOT IN` is also null-sensitive: movie rows have null `episode_id`, so the query returns no episodes. |
| R14 | Seq Scans on `viewing_activity`, `profiles`, and `titles` | Evaluates the maturity comparison for activity rows and joins both related tables. |
| R15 | Seq Scans on `accounts` and `plans` | Reads active accounts and aggregates their current plan prices. |
| R16 | Seq Scans on `viewing_activity`, `profiles`, `accounts`, and `plans` | Processes all plays, joins account/plan details, and groups by account and hour. |
| R17 | Seq Scans on `ratings` and `titles` | Reads the rating set and joins titles to calculate the two percentages. |
| R18 | Seq Scan on `viewing_activity` | Reads and aggregates viewing duration by month and device. |
| R19 | Seq Scans on `titles` and `viewing_activity` | Correlated count and max subqueries rescan the full activity table for each original title; this dominates baseline time. |
| R20 | Seq Scans on `my_list` and `titles` | Filters a date range, joins titles, then groups and sorts list additions. |
| R21 | Seq Scan on `accounts` | Searches the small account table for on-hold status and an overdue billing date. |
| R22 | Seq Scan on `titles` | Scans the small catalogue to find a month of departures. |
| R23 | Seq Scan on `viewing_activity` | Reads and orders the activity table, then discards 150,000 rows for the deep offset page. |
| R24 | Seq Scan on `profiles` | Finds the profiles for one account without an account lookup index. |
| R25 | Seq Scan and Index Only Scan on `title_genres` | Scans candidate associations and uses the composite primary-key index for the seed series' genres. |
| W01 | Index Scan on `episodes` | Locates the one target episode through the unique episode-position index before inserting. |
| W02 | No scan node | Inserts one row; the primary-key constraint checks a possible conflict. |
| W03 | Seq Scan on `plans`; Index Scan on `accounts` | Scans four plans to find STANDARD and locates the account by primary key. |
| W04 | Seq Scans on `accounts` and `plans` | Reads active accounts and their plans to insert the monthly invoice batch. |
| W05 | Seq Scans on `accounts` and `invoices` | Checks active accounts against June failed invoices to find dunning candidates. |

The three raw plans for each query are retained alongside
[`summary.csv`](../benchmarks/results/baseline/summary.csv).
