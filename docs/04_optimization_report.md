# Optimization Report

## 1. Method

Every number below comes from the same harness the Phase 3 baseline used:

- PostgreSQL 18.6 on the supplied seed data (200,401 viewing rows, 133,057 invoices).
- Each query was run **3 times** with `EXPLAIN (ANALYZE, BUFFERS)`; §3 reports the arithmetic mean `Execution Time` and §3.1 lists all three optimized runs individually, in the same format as the Phase 3 baseline table.
- Write queries ran inside `BEGIN; … ROLLBACK;`, so no data changed.
- `sql/05_indexes.sql` was applied and `VACUUM (ANALYZE)` was run before the optimized benchmark, so index-only scans see an up-to-date visibility map.
- No server setting was changed (`work_mem`, `enable_seqscan`, parallel settings all stay at their defaults).
- Script: `./benchmarks/run_benchmark.sh <db> optimized 3 sql/06_optimized_queries.sql`.
- Raw plans: `benchmarks/results/baseline/` and `benchmarks/results/optimized/`.
- Improvement % = (before − after) / before × 100.

The baseline numbers are the Phase 3 record in `benchmarks/results/baseline/summary.csv`; the after numbers are `benchmarks/results/optimized/summary.csv`.

## 2. Headline result

**6,803.6 ms → 313.6 ms, a 95.4% reduction (21.7×).**

Two facts keep this honest:

- **R19 alone was 6,407.9 ms (94.2% of the baseline).** Removing its correlated subqueries is most of the total gain.
- **Excluding R19, the other 29 queries went 395.7 ms → 290.8 ms (1.36×).** Of that remaining time, R16 (119.3 ms) and W04 (90.7 ms) are 72%. Those two read every viewing row and insert 21,282 invoices respectively; no index removes that work.

Five queries clear 20× individually: **R01 109×, R10 91.6×, R13 288.9×, R19 280.6×, R24 77.7×**. R03 is next at 14.8×. The rest are bounded by full scans, already-sub-millisecond baselines, or insert cost, and are explained in §8.

## 3. Before and after: all 30 queries

| Query | Type | Before (ms) | Problem found in the plan | Optimization applied | After (ms) | Improvement | Same result? |
|---|---|---:|---|---|---:|---:|:---:|
| R01 | READ | 6.550 | Parallel Seq Scan of 200k activity rows, 100,200 removed per worker, to return 1 row | `viewing_activity(profile_id, title_id, started_at DESC)` | 0.060 | 99.1% (109×) | ✅ |
| R02 | READ | 0.047 | Unique `(title_id, season_no, episode_no)` already returns the series in order | No change; run-to-run noise | 0.032 | 31.9% (1.5×) | ✅ |
| R03 | READ | 7.033 | Seq Scan of 200k rows to find 373 rows from one day | `viewing_activity(started_at)` + INCLUDE `title_id, profile_id` (index-only) | 0.476 | 93.2% (14.8×) | ✅ |
| R04 | READ | 0.688 | Seq Scans on titles, title_genres and genres | `title_genres(genre_id, title_id)` (index-only) | 0.293 | 57.4% (2.3×) | ✅ |
| R05 | READ | 0.449 | Seq Scan on titles; leading wildcard cannot use a B-tree | `pg_trgm` GIN on `titles(name)` | 0.126 | 71.9% (3.6×) | ✅ |
| R06 | READ | 0.054 | PK `(profile_id, title_id)` already finds this profile's six rows | No change; run-to-run noise | 0.049 | 9.3% (1.1×) | ✅ |
| R07 | READ | 0.023 | Unique episode-position index already answers the row comparison | No change; run-to-run noise | 0.020 | 13.0% (1.1×) | ✅ |
| R08 | READ | 7.833 | Seq Scan of 200k rows; June is 5.5% of the table | `viewing_activity(started_at)`; **no partial index** (not selective enough) | 1.695 | 78.4% (4.6×) | ✅ |
| R09 | READ | 25.788 | `EXTRACT(YEAR FROM started_at)` is not sargable; parallel Seq Scan of 200k | `started_at >= '2026-01-01' AND < '2027-01-01'`; index-only scan | 10.032 | 61.1% (2.6×) | ✅ |
| R10 | READ | 2.106 | Seq Scan of 25,000 accounts; plain email index cannot serve `lower(email)` | Expression index `accounts(lower(email))` | 0.023 | 98.9% (91.6×) | ✅ |
| R11 | READ | 6.990 | Seq Scans of 25k accounts and 133k invoices | Partial `invoices(billing_period_start, account_id) INCLUDE (amount_inr) WHERE status='FAILED'` | 2.474 | 64.6% (2.8×) | ✅ |
| R12 | READ | 1.331 | Seq Scan of 25k accounts; `EXTRACT(YEAR FROM cancelled_on)` hides any index | Sargable date range + partial `accounts(cancelled_on) INCLUDE (signup_date) WHERE status='CANCELLED'` | 0.159 | 88.1% (8.4×) | ✅ |
| R13 | READ | 17.911 | Seq Scan of 200k rows for `NOT IN`; **returned 0 rows because 93,056 movie plays have NULL `episode_id`** | `NOT EXISTS` (NULL-safe) + partial `viewing_activity(episode_id) WHERE episode_id IS NOT NULL` | 0.062 | 99.7% (288.9×) | ⚠️ **fixed: 0 → 8 rows** |
| R14 | READ | 21.190 | Seq Scans of activity, profiles and titles; filter is on joined attributes | None; full-table compliance report (§8) | 19.396 | 8.5% (1.1×) | ✅ |
| R15 | READ | 4.083 | Seq Scans of accounts and plans; 21,282 of 25,000 accounts are ACTIVE | None; scanning is cheaper than an 85%-selective index | 3.823 | 6.4% (1.1×) | ✅ |
| R16 | READ | 128.740 | Four Seq Scans + HashAggregate; every play must be grouped by account and hour | None; no index removes the read/aggregation (§8) | 119.315 | 7.3% (1.1×) | ✅ |
| R17 | READ | 5.282 | Seq Scans of ratings and titles; the report reads every rating | `ratings(title_id) INCLUDE (rating)` (FK/join support; planner still scans) | 4.833 | 8.5% (1.1×) | ✅ |
| R18 | READ | 23.383 | Seq Scan; `started_at::date` cast is not sargable | Drop the cast, range on `started_at`, index-only scan | 13.846 | 40.8% (1.7×) | ✅ |
| R19 | READ | 6,407.881 | Two correlated subqueries per Original title: 610 × 2 full scans = 244M row visits | One `GROUP BY title_id` aggregate + `LEFT JOIN` | 22.837 | 99.6% (280.6×) | ✅ |
| R20 | READ | 2.801 | Seq Scan of 60k My List rows for 3,328 June additions | `my_list(added_at) INCLUDE (title_id)` | 1.143 | 59.2% (2.5×) | ✅ |
| R21 | READ | 1.113 | Seq Scan of 25k accounts for 739 ON_HOLD rows | Partial `accounts(next_billing_date) INCLUDE (email) WHERE status='ON_HOLD'` | 0.252 | 77.4% (4.4×) | ✅ |
| R22 | READ | 0.170 | Seq Scan of 3,000 titles for 54 departing titles | Partial `titles(leaving_on) WHERE leaving_on IS NOT NULL` | 0.062 | 63.5% (2.7×) | ✅ |
| R23 | READ | 38.417 | Seq Scan + Sort of 200k rows, then discard 150,000 for the offset | `started_at` index allows a backward index scan | 12.996 | 66.2% (3.0×) | ✅ |
| R24 | READ | 1.865 | Seq Scan of 75,000 profiles for 4 rows | `profiles(account_id, created_at) INCLUDE (profile_name, is_kids, maturity_limit)` | 0.024 | 98.7% (77.7×) | ✅ |
| R25 | READ | 0.669 | Seq Scan of title_genres on both sides of the self-join | `title_genres(genre_id, title_id)`, index-only on both sides | 0.360 | 46.2% (1.9×) | ✅ |
| W01 | WRITE | 0.341 | Insert already used the episode index | Now maintains four new activity indexes | 0.517 | −51.6% (0.7×) | ✅ |
| W02 | WRITE | 0.358 | Insert with `ON CONFLICT` | Now maintains the new My List index | 0.509 | −42.2% (0.7×) | ✅ |
| W03 | WRITE | 0.243 | Plans subquery is an InitPlan over four rows | No index benefit; measured difference is noise | 0.271 | −11.5% (0.9×) | ✅ |
| W04 | WRITE | 79.357 | 21,282 inserts; Seq Scans of accounts and plans | Insert-bound; the new invoice index is partial on FAILED, so PAID rows do not touch it | 90.694 | −14.3% (0.9×) | ✅ |
| W05 | WRITE | 10.907 | Seq Scan of 133k invoices for the EXISTS probe | Same partial invoice index as R11 | 7.265 | 33.4% (1.5×) | ✅ |
| **Total** | | **6,803.603** | | | **313.644** | **95.4% (21.7×)** | |

"Same result?" for unchanged queries means the SQL is byte-for-byte the original. For R09, R12, R18 and R19 it means the `EXCEPT` proof in §5 returned zero differences in both directions.

### 3.1 All three optimized runs

The baseline format, repeated for the optimized file. Each row is one query; writes ran inside a rolled-back transaction. R19 run 1 is slower than runs 2–3 (32.3 vs 18.0 ms) because it reads a cold cache after `VACUUM`; W04 drifts upward because each rolled-back run leaves dead entries at the same invoice keys, so later uniqueness checks do more work (see §6). The `Average` column and the improvement use the same rounded averages as §3 and `summary.csv`.

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Before avg (ms) | Improvement |
|---|---|---:|---:|---:|---:|---:|---:|
| R01 | READ | 0.060 | 0.054 | 0.067 | 0.060 | 6.550 | 99.1% |
| R02 | READ | 0.035 | 0.031 | 0.029 | 0.032 | 0.047 | 31.9% |
| R03 | READ | 0.490 | 0.444 | 0.493 | 0.476 | 7.033 | 93.2% |
| R04 | READ | 0.292 | 0.311 | 0.277 | 0.293 | 0.688 | 57.4% |
| R05 | READ | 0.132 | 0.120 | 0.127 | 0.126 | 0.449 | 71.9% |
| R06 | READ | 0.050 | 0.044 | 0.052 | 0.049 | 0.054 | 9.3% |
| R07 | READ | 0.020 | 0.020 | 0.019 | 0.020 | 0.023 | 13.0% |
| R08 | READ | 1.853 | 1.633 | 1.598 | 1.695 | 7.833 | 78.4% |
| R09 | READ | 10.222 | 10.146 | 9.728 | 10.032 | 25.788 | 61.1% |
| R10 | READ | 0.025 | 0.025 | 0.020 | 0.023 | 2.106 | 98.9% |
| R11 | READ | 2.472 | 2.388 | 2.562 | 2.474 | 6.990 | 64.6% |
| R12 | READ | 0.158 | 0.164 | 0.155 | 0.159 | 1.331 | 88.1% |
| R13 | READ | 0.058 | 0.065 | 0.063 | 0.062 | 17.911 | 99.7% |
| R14 | READ | 19.455 | 19.470 | 19.262 | 19.396 | 21.190 | 8.5% |
| R15 | READ | 3.758 | 3.905 | 3.807 | 3.823 | 4.083 | 6.4% |
| R16 | READ | 118.417 | 119.678 | 119.850 | 119.315 | 128.740 | 7.3% |
| R17 | READ | 4.841 | 4.762 | 4.896 | 4.833 | 5.282 | 8.5% |
| R18 | READ | 13.763 | 13.902 | 13.872 | 13.846 | 23.383 | 40.8% |
| R19 | READ | 32.346 | 18.002 | 18.163 | 22.837 | 6407.881 | 99.6% |
| R20 | READ | 1.181 | 1.125 | 1.124 | 1.143 | 2.801 | 59.2% |
| R21 | READ | 0.262 | 0.232 | 0.262 | 0.252 | 1.113 | 77.4% |
| R22 | READ | 0.063 | 0.061 | 0.061 | 0.062 | 0.170 | 63.5% |
| R23 | READ | 13.273 | 13.077 | 12.638 | 12.996 | 38.417 | 66.2% |
| R24 | READ | 0.026 | 0.023 | 0.024 | 0.024 | 1.865 | 98.7% |
| R25 | READ | 0.363 | 0.347 | 0.369 | 0.360 | 0.669 | 46.2% |
| W01 | WRITE | 0.541 | 0.480 | 0.530 | 0.517 | 0.341 | -51.6% |
| W02 | WRITE | 0.570 | 0.497 | 0.461 | 0.509 | 0.358 | -42.2% |
| W03 | WRITE | 0.289 | 0.243 | 0.281 | 0.271 | 0.243 | -11.5% |
| W04 | WRITE | 78.990 | 87.998 | 105.093 | 90.694 | 79.357 | -14.3% |
| W05 | WRITE | 6.819 | 7.183 | 7.793 | 7.265 | 10.907 | 33.4% |
| **Total (sum of all 30)** | | **310.824** | **306.430** | **323.676** | **313.644** | **6803.603** | **95.4%** |

## 4. Why it got faster

### 4.1 The missing-index problem

PostgreSQL indexes PRIMARY KEY and UNIQUE constraints, but **not foreign-key child columns**. The baseline schema therefore had no index on `viewing_activity.profile_id`, `viewing_activity.title_id`, `viewing_activity.episode_id`, `profiles.account_id`, `title_genres.genre_id`, `ratings.title_id` or `my_list.title_id`. That is the root cause of R01, R13, R19, R24, R04, R17, R20 and R25.

`sql/05_indexes.sql` adds 14 indexes:

| Index | Serves | Why this type and order |
|---|---|---|
| `viewing_activity(profile_id, title_id, started_at DESC)` | R01, FK; the natural access path for the profile lookups in R14/R16 | Equality on profile, then the `DISTINCT ON` order; no sort needed |
| `viewing_activity(started_at) INCLUDE (title_id, profile_id, completed, device_type, duration_watched_sec)` | R03, R08, R09, R18, R23 | Range/sort column leads; INCLUDE turns R03/R09/R18 index-only |
| `viewing_activity(title_id, started_at)` | R19, FK | Per-title count/max, and keeps a title delete from scanning 200k rows |
| `viewing_activity(episode_id) WHERE episode_id IS NOT NULL` | R13, FK | Only real episodes (107,345 of 200,401); probes are index hits |
| `profiles(account_id, created_at) INCLUDE (profile_name, is_kids, maturity_limit)` | R24, FK | One account's profiles, already in display order, index-only |
| `title_genres(genre_id, title_id)` | R04, R25, FK | Reverses the PK order so lookups by genre work |
| `ratings(title_id) INCLUDE (rating)` | R17, FK | PK starts with profile_id; this serves the title join |
| `my_list(added_at) INCLUDE (title_id)` | R20 | PK starts with profile_id; this serves the date range |
| `invoices(billing_period_start, account_id) INCLUDE (amount_inr) WHERE status='FAILED'` | R11, W05 | Only 4,764 FAILED rows; period + account order, covering |
| `accounts(lower(email))` | R10 | Expression index must match the expression used in WHERE |
| `accounts(cancelled_on) INCLUDE (signup_date) WHERE status='CANCELLED'` | R12 | 2,979 cancellations only; covering for tenure |
| `accounts(next_billing_date) INCLUDE (email) WHERE status='ON_HOLD'` | R21 | 739 on-hold rows only; already in output order |
| `titles USING gin (name gin_trgm_ops)` | R05 | Leading-wildcard `ILIKE` needs trigrams |
| `titles(leaving_on) WHERE leaving_on IS NOT NULL` | R22 | Only titles that can ever depart |

Two indexes are deliberately **not** created, and the reasons are part of the result:

- **No partial index on `started_at` for R08.** June is 5.5% of the table, which is not selective enough for a partial index to beat the plain time index.
- **No index on `accounts.status` for R15.** 85% of accounts are ACTIVE, so an index would read more entries than a sequential scan.

Partial indexes also decide the write cost: `WHERE status='FAILED'` is not maintained by W04's PAID inserts, and the CANCELLED/ON_HOLD indexes only change when an account changes status.

### 4.2 The five rewrites

**R13 — `NOT IN` over a nullable column (the wrong-answer query).**

```sql
-- before: always 0 rows
AND e.episode_id NOT IN (SELECT v.episode_id FROM viewing_activity v)

-- after: 8 rows
AND NOT EXISTS (SELECT 1 FROM viewing_activity v WHERE v.episode_id = e.episode_id)
```

93,056 movie plays have `episode_id = NULL`. For every episode, `e.episode_id = NULL` evaluates to UNKNOWN, so the whole `NOT IN` is UNKNOWN and the query returns no rows. `NOT EXISTS` is null-safe. This is a correctness fix, not just a speed-up; the report says so explicitly instead of pretending the result was unchanged.

**R19 — correlated subqueries to one grouped scan.**

```sql
-- before: two subqueries, re-executed once per Original title
(SELECT count(*) FROM viewing_activity v WHERE v.title_id = t.title_id),
(SELECT max(v.started_at) FROM viewing_activity v WHERE v.title_id = t.title_id)

-- after: one pass over activity, then a join
LEFT JOIN (
    SELECT title_id, count(*) AS total_views, max(started_at) AS last_viewed_at
    FROM viewing_activity GROUP BY title_id
) v USING (title_id)
```

`coalesce(v.total_views, 0)` preserves the original `count(*) = 0` for titles with no views, and `max` stays NULL.

**R09, R12, R18 — make the predicate sargable.** `EXTRACT(YEAR FROM col) = 2026` and `col::date >= …` hide the column from the index. They become plain ranges, which produce identical rows on this data (verified with `EXCEPT`):

```sql
v.started_at >= '2026-01-01' AND v.started_at < '2027-01-01'      -- R09
cancelled_on  >= '2026-01-01' AND cancelled_on  < '2027-01-01'    -- R12
started_at    >= '2026-01-01'                                     -- R18
```

### 4.3 Five biggest before/after plans

Plan excerpts are run 1; the averages are in §3.

**R13 — 17.659 ms → 0.058 ms**

```
Baseline:
  Index Scan using episodes_position_unique on episodes e  (rows=0)
    Filter: (NOT (ANY (episode_id = (hashed SubPlan 1).col1)))
    SubPlan 1
      ->  Seq Scan on viewing_activity v  (rows=200401)
Execution Time: 17.659 ms

Optimized:
  Nested Loop Anti Join  (rows=8)
    ->  Index Scan using episodes_position_unique on episodes e  (rows=31)
    ->  Index Only Scan using viewing_episode_idx on viewing_activity v  (loops=31)
Execution Time: 0.058 ms
```

**R19 — 6,373.165 ms → 32.346 ms (run 1; 22.837 ms average)**

```
Baseline:
  Seq Scan on titles t  (rows=610)
    SubPlan 1
      ->  Aggregate  (loops=610)
            ->  Seq Scan on viewing_activity v  (Filter: title_id = t.title_id)
                  Rows Removed by Filter: 200336
    SubPlan 2
      ->  Aggregate  (loops=610)
            ->  Seq Scan on viewing_activity v_1
    Buffers: shared hit=1952051
Execution Time: 6373.165 ms

Optimized:
  Sort  (rows=610)
    ->  Hash Right Join
          ->  HashAggregate  (rows=3000)
                ->  Seq Scan on viewing_activity  (rows=200401)
          ->  Seq Scan on titles t  (Filter: is_netflix_original, rows=610)
Execution Time: 32.346 ms
```

**R01 — 6.603 ms → 0.060 ms**

```
Baseline:
  Parallel Seq Scan on viewing_activity v
    Filter: ((NOT completed) AND (profile_id = 7043))
    Rows Removed by Filter: 100200   (×2 workers)
Execution Time: 6.603 ms

Optimized:
  Bitmap Heap Scan on viewing_activity v
    ->  Bitmap Index Scan on viewing_profile_title_started_idx  (rows=5)
Execution Time: 0.060 ms
```

**R10 — 2.152 ms → 0.025 ms**

```
Baseline:
  Seq Scan on accounts
    Filter: (lower(email) = 'arjun.chopra1409@yahoo.com')
    Rows Removed by Filter: 24999
Execution Time: 2.152 ms

Optimized:
  Index Scan using accounts_lower_email_idx on accounts  (rows=1)
Execution Time: 0.025 ms
```

**R24 — 1.888 ms → 0.026 ms**

```
Baseline:
  Seq Scan on profiles
    Filter: (account_id = 1409)
    Rows Removed by Filter: 74996
Execution Time: 1.888 ms

Optimized:
  Index Scan using profiles_account_created_idx on profiles  (rows=4)
Execution Time: 0.026 ms
```

## 5. Proof that the results did not change

For every rewritten read query, the original and the optimized form were run through `EXCEPT` in **both** directions on the loaded database. All returned 0 differing rows:

| Query | Original EXCEPT optimized | Optimized EXCEPT original | Row count |
|---|---:|---:|---:|
| R09 | 0 | 0 | 15 |
| R12 | 0 | 0 | 6 |
| R18 | 0 | 0 | 26 |
| R19 | 0 | 0 | 610 |

R19 was additionally checked on the full 610-row result set, including `last_viewed_at`, not just the count. Queries without a rewrite use the original SQL verbatim, so their results are unchanged by construction.

**R13 is the exception the brief asks for:** the original returns 0 rows and the fixed query returns 8. That difference is the bug, and it is reported as a fix, not as an equivalence.

One other semantic issue was found and deliberately **not** changed: R08's predicate is `started_at >= '2026-06-01'` with no upper bound, so "June 2026" also includes later rows (2 rows after 2026-07-01 in the seed data). Adding `AND started_at < '2026-07-01'` would be more correct but would change the result set, so the SQL is left as specified and the issue is documented here.

## 6. Write overhead

The new indexes are not free. To separate index cost from machine noise, the five writes were re-measured on the same machine against a second database with the same schema and data but **without** `05_indexes.sql`:

| Write | No new indexes (ms) | With indexes (ms) | Change |
|---|---:|---:|---:|
| W01 start episode | 0.410 | 0.517 | +26% |
| W02 add to My List | 0.370 | 0.509 | +38% |
| W03 downgrade account | 0.252 | 0.271 | +8% |
| W04 billing run | 81.801 | 90.694 | +11%* |
| W05 dunning | 10.558 | 7.265 | **−31%** |

\* W04 inserts only PAID invoices, and the new invoice index is partial on `status='FAILED'`, so W04 performs **no maintenance on any new index**. Its 79 → 88 → 105 ms drift has a different cause. The benchmark runs the same deterministic insert three times and rolls it back, so every run leaves 21,282 dead heap tuples and dead entries at the **same** `invoice_id` and `(account_id, billing_period_start)` keys. The next run's uniqueness checks must follow those dead entries to the heap before accepting the row: the Insert node's buffer hits rose from 107,717 in run 1 to 177,830 in run 2. A control run using fresh invoice ids and periods stayed at 107,663 buffers, and `VACUUM netflix.invoices` between runs returned the next run to 107,717 buffers / ~84 ms. The baseline shows the same artifact (69.9, 86.3, 81.8 ms). In production the monthly batch runs once and commits, so the drift is a benchmark artifact, not index cost. W05 gets faster because the same partial invoice index replaces a 133k-row scan.

The real write cost is on the activity insert path: W01 now maintains five indexes on `viewing_activity` instead of one (four new indexes plus the primary key), which is the +0.1–0.15 ms above. At one play per insert this is acceptable; the alternative (no index) costs 6.5 ms on every Continue Watching read and 128 ms on the sharing report. W02's +0.14 ms comes from the new `my_list(added_at)` index, which takes R20 from 2.8 ms to 1.1 ms.

Sub-millisecond writes are noisy on this machine: a separate writes-only run measured W01 at 0.760 ms and W03 at 0.538 ms, while the main run measured 0.517 ms and 0.271 ms. The table uses the harness summary from the main run. Treat W01–W03 as a 0.1–0.2 ms index-maintenance cost rather than exact percentages; the important point is that they stay sub-millisecond and are not on the critical path.

## 7. Index storage

Measured with `pg_relation_size` after a fresh build (accounts reindexed to remove rolled-back W05 bloat):

| Index | Size |
|---|---:|
| `viewing_started_idx` | 8,960 kB |
| `viewing_title_started_idx` | 6,192 kB |
| `viewing_profile_title_started_idx` | 6,184 kB |
| `profiles_account_created_idx` | 3,584 kB |
| `my_list_added_idx` | 1,856 kB |
| `accounts_lower_email_idx` | 1,224 kB |
| `viewing_episode_idx` | 1,136 kB |
| `ratings_title_idx` | 1,056 kB |
| `titles_name_trgm_idx` | 256 kB |
| `invoices_failed_period_account_idx` | 168 kB |
| `title_genres_genre_title_idx` | 152 kB |
| `accounts_cancelled_on_idx` | 88 kB |
| `accounts_on_hold_billing_idx` | 56 kB |
| `titles_leaving_on_idx` | 16 kB |
| **Total new indexes** | **≈30 MB** |

For comparison, the table heap is ≈35 MB, with `viewing_activity` at 12 MB and its indexes at 26 MB (including the four new ones). The three big activity indexes are the price of R01/R03/R19; the six sub-300 kB partial/expression indexes together are under 1 MB. There is no index on `episodes`, `plans`, `genres` or `invoices(account_id, period)` beyond what the constraints already create.

## 8. Queries that could not be sped up (and why)

An honest floor is worth more than a fake optimisation. These queries are already doing the minimum work their semantics allow:

- **R02, R06, R07** — 0.02–0.05 ms. The constraint indexes already answer them; 20× would be below the `EXPLAIN` timer resolution. No change.
- **R14 (19.4 ms)** — reads every viewing row, then checks the joined profile and title attributes. 26,393 of 200,401 plays belong to kids profiles; driving from a profile index would still touch a comparable share and the planner correctly prefers hash joins. At 20× data this is ≈400 ms, well inside the 5 s report target.
- **R15 (3.8 ms)** — 21,282 of 25,000 accounts are ACTIVE. A sequential scan of 25k rows is cheaper than any index that matches 85% of them. At 20× this is ≈80 ms, inside 5 s.
- **R16 (119.3 ms)** — groups every play by account and hour. The plan is four sequential scans plus a HashAggregate; no index can avoid reading 200,401 activity rows and grouping them by account and hour. The aggregation dominates, so an index on the join columns cannot remove the work. At 20× this is ≈2.4 s, inside the 5 s target. If compliance could accept a nightly refresh, a materialized view of account-hour sharing would make this query trivial; we did not add one because the report is classified as monitoring and the brief prefers honesty about full scans.
- **R17 (4.8 ms)** — reads all 33,900 ratings to split them into two groups. The new `ratings(title_id)` index serves the title FK and the join, but on this data the planner still scans the 2 MB ratings table, which is the right choice. At 20× this is ≈100 ms, inside 5 s.
- **W01–W04** — insert/update-bound, as shown in §6. W04's 21,282 inserts cost 78–91 ms before and after; the only way to make it substantially faster is to change the batch shape, which the query text does not allow.

R23 is also worth naming: the index removes the sort but the query must still walk 150,000 index entries for `OFFSET 150000`, so 13 ms is close to the floor for this SQL. For the large dataset we will document keyset pagination (`WHERE (started_at, view_id) < (last_seen, last_id)`), including how the last-seen pair is taken from the previous page; the submitted query keeps the original `OFFSET` so the page number keeps its meaning.

## 9. What this means for Phase 5

- The activity indexes are the ones to watch when data grows 20×. `viewing_activity` will be the partition candidate (`RANGE` on `started_at`), and the primary key must include the partition key.
- R19's rewrite changes its growth from quadratic (titles × rows) to linear (one scan), so it is the main scale-only fix already in place.
- R16 and W04 are the two queries that will sit closest to their targets at 20×; both are measured and explained above rather than hidden.
- `VACUUM`/`ANALYZE` after the bulk load matters: without fresh visibility maps the index-only scans in R03/R09/R12/R18 fall back to heap fetches.
