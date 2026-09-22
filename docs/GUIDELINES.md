# Guidelines

## Guiding principles

1. **Build the platform once and reuse it for every app.** One migration toolkit, one schema template, one runbook and one ops baseline. Each app adds only its own data mapping.
2. **Closed months never change.** Past monthly Cloudant DBs are read-only: copy them in bulk once and verify them once. Only the current month needs live sync.
3. **One monthly DB maps to one monthly partition.** A DB like `usage_2026_08` becomes a partition of `usage PARTITION BY RANGE (month)`. Delete old data with `DETACH`/`DROP PARTITION`, never `DELETE`.
4. **Keep a way back at every step.** Cloudant stays the source of truth until cutover.
5. **Postgres handles transactions; reporting runs elsewhere.** Heavy reports run on DuckLake/COS via CDC, or on a read replica, never on the primary.

## Per-app playbook

1. **Inventory.** Document types, field variance (sample ~10k docs per type), views / MapReduce / search indexes, attachments, conflict counts, and every `_changes` consumer (check Cloudant access logs for unknown readers).
2. **Schema design** (reviewed by the DB guild):
   - Stable, queried fields become typed columns. Sparse or variable fields go in a `JSONB` column (`attrs`).
   - Cloudant `_id` becomes a natural/unique key. Drop `_rev`, or keep it as `legacy_rev` during the migration only.
   - Views become B-tree/GIN indexes or materialized views. Reduce views become aggregates or rollup tables.
   - Attachments go to COS, with the object key stored in the row.
   - Every table written by events gets an idempotency key and `UNIQUE` constraint, so replays are safe.
3. **Backfill the closed months.** `_all_docs` per monthly DB → transform → `COPY` into a staging table → `ATTACH PARTITION`. Load months in parallel. Bad docs go to a dead-letter table and are never dropped silently.
4. **Verify the closed months.** Row counts, per-key checksums and business aggregates (e.g. quantity or cost per account per month) between Cloudant and Postgres. Sign off month by month.
5. **Sync the current month.** Tail `_changes` from a saved `since` seq, or dual-write behind a feature flag. Run continuous reconciliation.
6. **Shadow reads.** Serve reads from Cloudant, query Postgres in parallel, compare and log mismatches. Target 0 mismatches for N days.
7. **Cutover at a month boundary.** Freeze writes → drain the tail → final reconcile → flip the flag → Cloudant read-only.
8. **Decommission.** After 1–2 billing cycles: export to COS (Parquet) with checksums, remove dual-write code, delete Cloudant.

## Partitioning

- Native declarative partitioning by month, automated with `pg_partman` or a cron job that creates partitions 3 months ahead.
- Every partitioned table has a **default partition**, with an alert on any rows that land in it.
- The partition key must be in every primary key and unique constraint.
- Hot queries must filter on the partition key so Postgres can skip other partitions (check with `EXPLAIN`).

```sql
CREATE TABLE usage (
  account_id  text        NOT NULL,
  resource_id text        NOT NULL,
  month       date        NOT NULL,
  event_key   text        NOT NULL,      -- idempotency key
  quantity    numeric     NOT NULL,
  attrs       jsonb       NOT NULL DEFAULT '{}',
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (month, event_key)
) PARTITION BY RANGE (month);

CREATE TABLE usage_default PARTITION OF usage DEFAULT;   -- alert if non-empty
```

## Autovacuum

The global defaults are too lazy for high-churn tables. Starting point:

```ini
autovacuum_max_workers              = 6
autovacuum_naptime                  = 15s
autovacuum_vacuum_cost_limit        = 2000
autovacuum_vacuum_scale_factor      = 0.05
autovacuum_analyze_scale_factor     = 0.02
idle_in_transaction_session_timeout = 60s
```

```sql
-- hot current-month partition
ALTER TABLE usage_2026_09 SET (
  autovacuum_vacuum_scale_factor = 0.01,
  autovacuum_vacuum_threshold    = 5000);

-- once a month closes, so it never triggers a wraparound vacuum later
VACUUM (FREEZE, ANALYZE) usage_2026_08;
```

Monitor dead tuples (`n_dead_tup`), the oldest transaction ID age (`age(datfrozenxid)`), long-running transactions and bloat.

## PgBouncer

- **Transaction pooling** by default, run as its own deployment with ≥2 replicas.
- PgBouncer ≥1.21 with `max_prepared_statements`, or turn off server-side prepared statements in the drivers.
- Transaction pooling breaks session features: session `SET` (use `SET LOCAL`), session advisory locks, `LISTEN/NOTIFY`, and temp tables across transactions.
- Keep `default_pool_size × pools` below `max_connections − reserved`. Keep Postgres `max_connections` modest (a few hundred).
- Migrations, batch jobs and `pg_dump` connect directly, not through the pooler.

```ini
[pgbouncer]
pool_mode               = transaction
max_client_conn         = 5000
default_pool_size       = 20
reserve_pool_size       = 5
max_prepared_statements = 200
server_idle_timeout     = 300
query_wait_timeout      = 30
```

## Backups & DR

- Daily base backups plus **PITR** (continuous WAL archiving). Retention agreed with compliance; billing data often needs ≥30 days of PITR plus long-term exports.
- **Quarterly restore drill**, recording the restore time actually achieved against the RTO/RPO targets. A backup that has never been restored is not proven.
- Cross-region replica or documented DR plan before Wave 3.
- Closed partitions exported to COS as Parquet, for archive and for DuckLake.

## Logical replication / CDC

- `pgoutput` publications or Debezium → Event Streams. These replace the Cloudant `_changes` consumers and feed DuckLake.
- `REPLICA IDENTITY` on every published table (primary key, or `FULL` where needed).
- Set `max_slot_wal_keep_size` and **alert on slot lag**: an abandoned slot keeps WAL forever and will fill the disk.
- `publish_via_partition_root = true`, so consumers see one table rather than monthly partitions.
- DDL is not replicated, so coordinate schema changes with consumers.
- Logical replication also enables near-zero-downtime major version upgrades later.

```sql
CREATE PUBLICATION usage_pub FOR TABLE usage
  WITH (publish_via_partition_root = true);

SELECT slot_name,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal
FROM pg_replication_slots;
```

## Schema changes & query hygiene

- Migrations run from CI (Flyway / Liquibase / golang-migrate) using **expand → migrate → contract**.
- `CREATE INDEX CONCURRENTLY`. Add `NOT NULL` via `CHECK ... NOT VALID` followed by `VALIDATE CONSTRAINT`.
- Role-level `statement_timeout`, `lock_timeout` and `idle_in_transaction_session_timeout`.
- `pg_stat_statements` enabled; top-20 queries reviewed weekly during migration.
- GIN indexes on `JSONB` only for paths you actually query.

## Top risks

| Risk | Mitigation |
|---|---|
| Schema drift or dirty docs break the backfill | Profile doc shapes in Phase 0; dead-letter table, never drop silently |
| Hidden `_changes` consumers break at cutover | Consumer inventory plus Cloudant access-log review |
| Connection storms from many pods | PgBouncer mandatory from day 1; per-role connection limits |
| Abandoned replication slot fills the disk | `max_slot_wal_keep_size` plus a slot-lag alert |
| Reporting queries slow the transactional workload | Reports on DuckLake via CDC, or a read replica |
| XID wraparound on large, rarely touched partitions | Freeze partitions when a month closes; alert on `age(datfrozenxid)` |

## Governance

- **DB guild** (2–3 senior engineers plus a DBA): reviews every schema, owns the platform baseline, gives go/no-go for each cutover.
- **Shared toolkit**: backfill tool, changes-feed tailer, reconciler, partition manager, Terraform modules and runbook templates. Each app contributes back what it learns.
- **Definition of done per app**: its migration issue is fully ticked (or items struck through with a reason), 2 weeks stable in production, and Cloudant deleted.
- **Weekly migration standup** across app leads, working from the migration issues or Project board.
