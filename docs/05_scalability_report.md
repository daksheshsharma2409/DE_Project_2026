# Scalability Report (Phase 5)

## 1. Method

- PostgreSQL 18.6 on the same MacBook Pro M4 used for Phases 3 and 4.
- Fresh database `netflix_large`: `sql/01_schema.sql`, `large_data/` loaded with `sql/02_load_data.sql` (folder name changed only), then `sql/05_indexes.sql` and `VACUUM (ANALYZE)`.
- The **optimized** workload `sql/06_optimized_queries.sql` was run with `./benchmarks/run_benchmark.sh netflix_large large 3`. No query text changed for the large round.
- Three runs per query with `EXPLAIN (ANALYZE, BUFFERS)`; writes inside `BEGIN … ROLLBACK`; averages are the arithmetic mean. Raw plans and all three runs: `benchmarks/results/large/`.
- No server setting was changed. The 20× data has 11,124,198 rows: 500,000 accounts, 1,500,000 profiles, 60,000 titles, 4,012,819 viewing rows, 2,657,600 invoices.
- The recorded pass is the **first** pass on the freshly loaded and vacuumed database. A second pass without `VACUUM` was discarded: rolled-back writes left 1.27M dead invoice tuples and dead account tuples, which inflated R11 (27.8 → 162.5 ms), W04 (2,075 → 2,651 ms) and W05 (397 → 501 ms). This is the same rolled-back-benchmark artifact documented in `docs/04` §6; it is not index or query cost.

Reproduce:

```bash
createdb netflix_large
psql -d netflix_large -v ON_ERROR_STOP=1 -f sql/01_schema.sql
sed 's#seed_data/#large_data/#' sql/02_load_data.sql | psql -d netflix_large -v ON_ERROR_STOP=1
psql -d netflix_large -v ON_ERROR_STOP=1 -f sql/05_indexes.sql
./benchmarks/run_benchmark.sh netflix_large large 3 sql/06_optimized_queries.sql
```

## 2. Results: all 30 queries

Seed = Phase 4 optimized average (`benchmarks/results/optimized/summary.csv`). Growth = large ÷ seed. Targets are the Phase 5 targets in the brief.

| Query | Seed (ms) | Large (ms) | Growth | Target (ms) | Met? | If not, what changed |
|---|---:|---:|---:|---:|:---:|---|
| R01 | 0.060 | 0.124 | 2.07× | 5 | yes | — |
| R02 | 0.032 | 0.060 | 1.88× | 5 | yes | — |
| R03 | 0.476 | 11.497 | 24.15× | 250 | yes | — |
| R04 | 0.293 | 5.897 | 20.13× | 250 | yes | — |
| R05 | 0.126 | 2.545 | 20.20× | 250 | yes | — |
| R06 | 0.049 | 0.040 | 0.82× | 5 | yes | — |
| R07 | 0.020 | 0.022 | 1.10× | 5 | yes | — |
| R08 | 1.695 | 42.111 | 24.84× | 5,000 | yes | — |
| R09 | 10.032 | 163.974 | 16.35× | 5,000 | yes | — |
| R10 | 0.023 | 0.031 | 1.35× | 5 | yes | — |
| R11 | 2.474 | 27.819 | 11.24× | 250 | yes | — |
| R12 | 0.159 | 1.921 | 12.08× | 5,000 | yes | — |
| R13 | 0.062 | 0.027 | 0.44× | 250 | yes | — |
| R14 | 19.396 | 211.481 | 10.90× | 5,000 | yes | — |
| R15 | 3.823 | 32.701 | 8.55× | 5,000 | yes | — |
| R16 | 119.315 | 1,712.154 | 14.35× | 5,000 | yes | — |
| R17 | 4.833 | 45.836 | 9.48× | 5,000 | yes | — |
| R18 | 13.846 | 417.195 | 30.13× | 5,000 | yes | — |
| R19 | 22.837 | 187.940 | 8.23× | 5,000 | yes | — |
| R20 | 1.143 | 24.866 | 21.76× | 5,000 | yes | — |
| R21 | 0.252 | 8.623 | 34.22× | 250 | yes | — |
| R22 | 0.062 | 0.645 | 10.40× | 250 | yes | — |
| R23 | 12.996 | 17.941 | 1.38× | 250 | yes | — |
| R24 | 0.024 | 0.034 | 1.42× | 5 | yes | — |
| R25 | 0.360 | 3.704 | 10.29× | 250 | yes | — |
| W01 | 0.517 | 0.111 | 0.21× | 5 | yes | — |
| W02 | 0.509 | 0.758 | 1.49× | 5 | yes | — |
| W03 | 0.271 | 0.655 | 2.42× | 5 | yes | — |
| W04 | 90.694 | 2,075.196 | 22.88× | 2,000 | **no** | Cold relation extension; steady-state 1,906/1,897 ms (§4.1) |
| W05 | 7.265 | 396.795 | 54.62× | 2,000 | yes | — |

Group headroom:

| Group | Worst query | Worst large time | Target | Headroom |
|---|---|---:|---:|---:|
| Real-time | W02 | 0.758 ms | 5 ms | 6.6× |
| Interactive | R11 | 27.819 ms | 250 ms | 9.0× |
| Reports | R16 | 1,712.154 ms | 5,000 ms | 2.9× |
| Batch | W04 | 2,075.196 ms | 2,000 ms | **−3.8%** |

**29 of 30 queries meet their target.** W04 misses by 3.8% because its first run pays one-time relation extension; its second and third runs are under the target. §4.1 explains why no index change fixes this.

## 3. Growth analysis

### 3.1 Stayed about the same (about 1–2×)

`R01 2.07×, R02 1.88×, R06 0.82×, R07 1.10×, R10 1.35×, R23 1.38×, R24 1.42×, W01 0.21×, W02 1.49×`

These are index lookups whose cost grows with tree depth (`log n`), single-row writes, or fixed-size pages. R23 still walks a fixed `OFFSET 150000`; the table growing from 200k to 4M rows does not change the number of index entries skipped. W01 is noise-level (0.1–0.5 ms on both datasets).

### 3.2 Grew about 20× (15–25×)

`R03 24.15×, R04 20.13×, R05 20.20×, R08 24.84×, R09 16.35×, R20 21.76×, W04 22.88×`

These read a fixed **share** of the data, so the row count scales with the table:

- R03 reads one day (373 → 7,436 rows), R08 reads June 2026 onward (10,983 → 219,964; 2 and 121 rows fall after 1 July because the original query has no upper bound), R09/R18 the 2026 slice (66,546 → 1,326,799).
- R04 and R05 scan the catalogue (3,000 → 60,000 titles).
- R20 reads one month of My List adds (3,328 → 66,045).
- W04 inserts one row per active account (21,282 → 424,960).

R03/R08 are slightly above 20× because the hash join and aggregation work also grows; R09 is below 20× because its per-row aggregation is cheaper on the larger table (better sequential throughput), even though it reads 19.9× more 2026 rows.

### 3.3 Grew more than 20×

`R18 30.13×, R21 34.22×, W05 54.62×`

- **R18** scans 19.9× more 2026 rows (66,546 → 1,326,799), but per-row cost rises from 0.21 to 0.31 µs: a 175 MB index-only scan has more cache misses than a 9 MB one, and the aggregate is larger. The plan stays `Index Only Scan` with `Heap Fetches: 0`.
- **R21** reads 20.3× more ON_HOLD accounts (739 → 15,039); the average is inflated by the cold first run (14.4 ms vs 5.6/5.9 ms). Warm growth is ~22×.
- **W05** updates 20.3× more accounts (739 → 15,039). Each update also inserts into the partial `accounts_on_hold_billing_idx`; the first run is cold (714 ms vs 228/248 ms). Warm growth is ~31–34×, and the total is still only 20% of the 2 s target.

### 3.4 Grew less than 20×

`R11 11.24×, R12 12.08×, R13 0.44×, R14 10.90×, R15 8.55×, R16 14.35×, R17 9.48×, R19 8.23×, R22 10.40×, R25 10.29×, W03 2.42×`

The growing fact tables are joined to small dimension tables (`plans`, `genres`, `titles`) or filtered by a selective attribute, so fixed hash/aggregate overhead dominates. R19 is linear after the Phase 4 rewrite: 4M rows in one grouped scan is cheaper per row than 200k rows through a cold plan. R13 returns the same handful of unwatched episodes and is bound by the episode index, not the activity table. R22's 16× more departing titles (54 → 872) still fit in one small bitmap scan.

## 4. What broke at scale, and the fixes

### 4.1 W04: the only missed target

```
Run 1: 2,423.117 ms   buffers hit=2,134,152 read=11,578 written=4,929
Run 2: 1,905.933 ms   buffers hit=3,544,199 read=14,252 written=16,868
Run 3: 1,896.538 ms   buffers hit=3,424,517 read=18,512 written=18,458
Average: 2,075.196 ms (target 2,000 ms, 3.8% over)
```

The plan is `Seq Scan accounts` (500k) + `Seq Scan plans` (4) + `Insert on invoices` (424,960 rows). The first run is 27% slower than the other two even though it does the fewest buffer reads/writes. It is also the run during which the table grows by roughly 40 MB; runs 2–3 reuse the already-extended files. That points to one-time page allocation and cold-cache cost rather than index maintenance. The steady-state batch is **under** the target.

No index change helps. Both invoice indexes receive sequential appends: `accounts.account_id` has physical correlation 0.99999 (the load order is account order), and `invoice_id = 90,000,000 + account_id`. The partial `FAILED` index is not touched because every inserted row is `PAID`. The dominant remaining cost is 424,960 × (heap insert + two index inserts) plus the per-row FK check, which is close to the minimum for this SQL.

At 100× the same shape inserts ~2.1M rows and would take ~10 s. The fix is batch design, not SQL tuning:

1. Split the run into four account-id ranges and commit each (~106k rows per transaction); this bounds WAL, lock and relation-extension cost.
2. Partition `invoices` by `RANGE (billing_period_start)`: July rows land in a fresh partition with empty indexes, and the batch can run in parallel per account range.
3. Run the batch in one transaction only if the target is relaxed; the current 2 s target is at the edge of a 425k-row single transaction.

### 4.2 R16: the first report that breaks at 100×

R16 grows 14.35× to 1,712 ms at 20×, using 34% of the 5 s report budget. At 100× (5× large) it projects to ~8.5 s, over target. The plan is four sequential scans plus a `HashAggregate`; every play must be grouped by account and hour, so no index removes the work.

Fix for 100×: maintain an `account_hour_activity` summary (account_id, hour, distinct profiles, plan max_streams) during load or on a nightly/hourly refresh. R16 then filters a much smaller table for `profiles_watching > max_streams` instead of grouping 20M plays. Compliance can tolerate an hourly refresh; if not, maintain the summary incrementally per closed hour.

### 4.3 R23: OFFSET is acceptable at this page; keyset for depth

At 20× the original `OFFSET 150000` is 17.9 ms, well inside the 250 ms target, because the offset is fixed. On the partitioned copy it becomes 23.4 ms (warm) because the plan needs a `Merge Append` across partitions to preserve the global order.

Keyset pagination removes the walk. The client stores the last `(started_at, view_id)` pair of the previous page; for page 6,001 that pair is `('2026-06-10 12:56:32+05:30', 3862214)`:

```sql
SELECT view_id, profile_id, title_id, episode_id, started_at
FROM viewing_activity
WHERE (started_at, view_id) < ('2026-06-10 12:56:32+05:30', 3862214)
ORDER BY started_at DESC, view_id DESC
LIMIT 25;
```

| Plan | Rows walked | Warm time |
|---|---:|---:|
| `OFFSET 150000` | 150,025 | 17.9 ms (23.4 ms partitioned) |
| Keyset | 26 | **0.21–0.27 ms** |

```
-- OFFSET (partitioned)
Merge Append (actual time=0.103..20.802 rows=150025 loops=1)
Execution Time: 23.442 ms

-- Keyset
Merge Append (actual time=0.112..0.121 rows=26 loops=1)
Execution Time: 0.212 ms
```

The 25 returned rows are identical to the original page (`EXCEPT` in both directions returned 0). The original `ORDER BY started_at DESC` has no tiebreaker; the keyset form adds `view_id DESC`, which is what makes the page boundary deterministic. Raw plans: `benchmarks/results/large/partitioning/R23_keyset.txt` and `R23_after.txt`.

At 100× the fixed `OFFSET 150000` stays ~20 ms, but any deeper page grows linearly; keyset stays proportional to the page size.

### 4.4 Partitioning: pruning works, but it is a retention/maintenance win here

`sql/08_partitioning.sql` converts `viewing_activity` to `RANGE (started_at)` with one partition per month (Jan 2025–Jul 2026) plus a `DEFAULT`. It was tested on the full 4M-row table (`netflix_large_clean`); the conversion took 40 s and produced 20 partitions. The 20× benchmark results in §2 are from the unpartitioned schema; this section is the separate partitioning experiment.

**Pruning proof (R03):** the partitioned plan contains a single activity scan:

```
Index Only Scan using viewing_activity_2026_06_started_at_title_id_profile_id_com_idx
    on viewing_activity_2026_06 v
  Index Cond: (started_at >= '2026-06-30 00:00:00+05:30'
           AND started_at <  '2026-07-01 00:00:00+05:30')
  Index Searches: 1
```

The other 19 partitions do not appear in the plan. Raw plan: `benchmarks/results/large/partitioning/R03_after.txt`.

**But the end-to-end gain is small on this workload**, because the global `viewing_activity(started_at)` index already restricted every date-bounded query to the same rows:

| Query | Unpartitioned | Partitioned (warm) | Effect |
|---|---:|---:|---|
| R03 (one day) | 11.4–13.3 ms | 9.2–11.6 ms | 1 partition scanned; titles scan dominates |
| R18 (2026) | 417 ms | 444–457 ms | no row reduction; per-partition overhead |
| R09 (2026) | 164 ms | 171 ms | no row reduction |
| R01 (profile, no date) | 0.08–0.14 ms | 0.21–0.66 ms | probes all 20 partitions |
| R23 (no date, ORDER BY) | 18–22 ms | 23–74 ms | `Merge Append` across partitions |
| R16 (no date) | 1,712 ms | 1,742–2,846 ms | `Parallel Append`; cold first run |

R01/R03/R23 show the range of three re-measured runs on the unpartitioned copy; the other rows use the recorded large average. R01 and R23 remain far inside their targets, so the regression is acceptable. The real benefits are operational: `VACUUM`/`ANALYZE` and `REINDEX` operate per partition, old months can be detached and dropped for retention, and each partition is small enough to stay cache-friendly at 100×. Storage grows from 1,659 MB to 1,735 MB (+4.6%) because each partition carries its own index roots and catalog entries.

The primary-key rule is the important design constraint: PostgreSQL requires the partition key in every unique constraint, so the PK becomes `(view_id, started_at)`. `view_id` alone is no longer enforced by the database. A hash partition on `view_id` would preserve the single-column PK but lose time pruning and retention.

### 4.5 R19: the scale-only fix already in place

R19 is the clearest example of a problem that only becomes fatal at scale. The Phase 3 baseline plan ran two correlated subqueries per Original title:

```
Seq Scan on titles t (610 rows)
  SubPlan 1 -> Aggregate -> Seq Scan on viewing_activity (loops=610)
  SubPlan 2 -> Aggregate -> Seq Scan on viewing_activity (loops=610)
Buffers: shared hit=1,952,051
Execution Time: 6,373.165 ms
```

That is 610 × 2 × 200,401 ≈ 244M row visits for a 610-row answer. On the 20× data the same shape would be 12,164 Originals × 2 × 4,012,819 ≈ 97.6B row visits, or about **40 minutes**. The Phase 4 rewrite groups the activity table once:

```
Finalize HashAggregate (59,999 groups)
  Partial HashAggregate -> Parallel Seq Scan on viewing_activity (4,012,819 rows)
Hash Right Join with titles (12,164 Originals)
Execution Time: 189.429 ms
```

At 20× this is 188 ms instead of ~40 minutes, and it grows linearly (~0.9 s at 100×). No further change is needed for this query.

## 5. Storage

| Relation | Seed heap | Seed indexes | Large heap | Large indexes |
|---|---:|---:|---:|---:|
| `viewing_activity` | 12 MB | 26 MB | 249 MB | 524 MB |
| `invoices` | 8.2 MB | 6.9 MB | 153 MB | 133 MB |
| `profiles` | 4.9 MB | 5.2 MB | 95 MB | 102 MB |
| `accounts` | 2.5 MB | 4.1 MB | 50 MB | 88 MB |
| `my_list` | 2.6 MB | 3.2 MB | 51 MB | 62 MB |
| `ratings` | 2.0 MB | 1.8 MB | 38 MB | 35 MB |
| `episodes` | 1.4 MB | 1.4 MB | 27 MB | 26 MB |
| `titles` | 288 kB | 360 kB | 5.8 MB | 5.0 MB |
| `title_genres` | 216 kB | 304 kB | 4.2 MB | 5.3 MB |
| `genres` + `plans` | 16 kB | 64 kB | 16 kB | 64 kB |
| **All relations** | **34 MB** | **49 MB** | **673 MB** | **980 MB** |
| **Database** | **91 MB** | | **1,659 MB** | |

The database grew 18.2× for 20× the rows: indexes dominate both sizes, and the large database's indexes (980 MB) are now 1.46× its heap (673 MB). `viewing_activity` alone is 773 MB (47% of the database). After the rolled-back benchmark writes the database measured 1,768 MB; `VACUUM` removes the dead tuples but does not shrink the files, so 1,659 MB is the clean post-load size. The partitioned copy is 1,735 MB.

## 6. Architecture for 100×

100× means about 20.1M viewing rows, 2.5M accounts, 7.5M profiles, 300k titles and 13.3M invoices (5× the large dataset).

### 6.1 Partitioning

`RANGE (started_at)`, monthly, as in `sql/08_partitioning.sql`. At 100× a month is ~1.1M viewing rows (~70 MB heap + ~150 MB indexes, ~215 MB total), small enough for a single `VACUUM` and for partition-wise parallel scans. Keep 24 months hot (24 partitions); after that, detach and archive or drop the oldest month instead of deleting rows. If 60+ monthly partitions become too many, merge closed years into quarterly partitions; the pruning predicate does not change.

The DDL excerpt that matters:

```sql
CREATE TABLE viewing_activity (
    view_id INTEGER NOT NULL,
    profile_id INTEGER NOT NULL REFERENCES profiles(profile_id) ON DELETE RESTRICT,
    title_id INTEGER NOT NULL REFERENCES titles(title_id) ON DELETE RESTRICT,
    episode_id INTEGER,
    started_at TIMESTAMPTZ NOT NULL,
    duration_watched_sec INTEGER NOT NULL CHECK (duration_watched_sec > 0),
    device_type VARCHAR(10) NOT NULL CHECK (device_type IN ('TV','MOBILE','TABLET','LAPTOP')),
    completed BOOLEAN NOT NULL,
    PRIMARY KEY (view_id, started_at),
    CONSTRAINT viewing_episode_matches_title
        FOREIGN KEY (episode_id, title_id)
        REFERENCES episodes(episode_id, title_id) ON DELETE RESTRICT
) PARTITION BY RANGE (started_at);

CREATE TABLE viewing_activity_2026_07 PARTITION OF viewing_activity
    FOR VALUES FROM ('2026-07-01 00:00:00+05:30')
                 TO ('2026-08-01 00:00:00+05:30');
```

The four activity indexes are created on the parent and PostgreSQL builds one per partition. Bounds carry `+05:30` so an IST row cannot fall into the previous month under a UTC session.

A second candidate is `invoices` by `RANGE (billing_period_start)`: it makes W04 write into a fresh month partition and makes retention/archival trivial. It changes the invoice PK to `(invoice_id, billing_period_start)` for the same reason as above.

### 6.2 Sharding

Shard **by account** (and co-locate `profiles`, `my_list`, `ratings`, `invoices` by `account_id`):

- Single-shard (account/profile scoped): R01, R06, R24, W01, W02, W03.
- All-shard batches and global reports: R12, R14, R15, R16, R21, R23, W04, W05. Run them per shard and merge; W04/W05 become parallel per-shard batches.
- Catalogue queries (R02, R04, R05, R07, R13, R22, R25) run against a replicated catalogue on every shard; titles (60k), episodes (400k) and genres (15) are small enough to copy.
- Title-centric reports (R03, R09, R17, R19, R20) aggregate across all shards; serve them from a warehouse/replica with a global title aggregate.
- R10 (sign-in by email) needs a global email→account directory, or a scatter-gather lookup.
- Sharding by title would localize the reports but make Continue Watching and My List cross-shard for every profile, which is the wrong trade for member-facing latency.

Write volume at 100× is ~20M views / 18 months ≈ 37k rows/day (≈0.4 rows/s), which one primary handles comfortably. Shard for isolation, geography and maintenance windows, not because the write rate demands it.

### 6.3 Read replicas and caching

| Traffic | Where | Why |
|---|---|---|
| W01–W05 | primary | writes |
| R10, R24 | primary or <1 s replica | sign-in and profile switching must see the latest account/profile state |
| R01, R06 | low-lag replica, 30 s per-profile cache | Continue Watching and My List tolerate seconds of staleness |
| R03, R04, R05, R15, R22 | replica + cache | Top 10 5 min; genre/search/plan/last-chance rows 1 h (catalogue changes slowly) |
| R08, R09, R12, R14, R16–R20, R23 | replica | reports and console reads; no writes |

R19/R17 can be refreshed nightly into a summary table. Cache keys must include the profile or account id for R01/R06; a shared cache for Top 10 is safe because it is the same for all viewers.

### 6.4 Maintenance

- **Autovacuum per partition:** `scale_factor = 0.02`, `cost_limit = 2000`, `cost_delay = 2ms` on `viewing_activity` partitions; monitor `pg_stat_user_tables.n_dead_tup`. The rolled-back benchmark artifact shows how quickly dead tuples distort reads.
- **Partition lifecycle:** create the next month ahead of time (a scheduled job); detach and archive/drop months older than the retention window. Never `DELETE` a month from a 20M-row table.
- **Bulk loads:** load into the current partition, then `ANALYZE`; run `VACUUM (ANALYZE)` after a batch job so index-only scans keep `Heap Fetches: 0`.
- **Indexes:** `REINDEX CONCURRENTLY` per partition after heavy churn; drop the global `started_at` index only if pruning plus per-partition scans prove faster for the actual mix.
- **Summary tables:** refresh `account_hour_activity` (R16) and daily title views (R03/R19) after each load; state the refresh lag in the product contract.
- **Invoices:** run W04 in chunks or into the new month partition, then `VACUUM` the partition; keep the partial `FAILED` index small.

### 6.5 100× projection

Assumes linear growth from 20× to 100× (5× large) with the same plans and indexes; index lookups grow slower than linear, so these are conservative.

| Group | Worst at 20× | Projected 100× | Target | Verdict |
|---|---:|---:|---:|---|
| Real-time | W02 0.758 ms | ~3.8 ms | 5 ms | pass (W02 is the tightest) |
| Interactive | R11 27.8 ms | ~139 ms | 250 ms | pass |
| Interactive (R03) | 11.5 ms | ~58 ms | 250 ms | pass |
| Reports (R16) | 1,712 ms | ~8,560 ms | 5,000 ms | **fails → summary table** |
| Reports (R18) | 417 ms | ~2,085 ms | 5,000 ms | pass, watch |
| Reports (R09/R14/R19) | 164/211/188 ms | ~0.8/1.1/0.9 s | 5,000 ms | pass |
| Batch (W04) | 2,075 ms | ~10,375 ms | 2,000 ms | **fails → chunk/partition invoices** |
| Batch (W05) | 397 ms | ~1,985 ms | 2,000 ms | borderline → partition invoices |
| Storage | 1.66 GB | ~8.3 GB | — | manageable; 5 years ≈ 25 GB |

## 7. Conclusion

The database is ready for the 20× dataset: 29 of 30 targets are met with 2.9×–9× headroom, and the one miss (W04, 3.8%) is a cold relation-extension cost whose steady-state runs meet the target. The Phase 4 rewrite of R19 is what keeps the Originals report linear at scale; without it the 20× run would have taken about 40 minutes (6.4 s × 20× rows × 20× Original titles).

For 100× the design is clear: partition `viewing_activity` by month (already written and tested), add an `account_hour_activity` summary for R16, chunk or partition the monthly invoice batch, shard by account for member-facing traffic, and serve title-centric reports from a replica or summary tables. The remaining risks are operational — partition creation and retention, vacuum/bloat on the activity table, and the freshness contract for cached rows — not query correctness.
