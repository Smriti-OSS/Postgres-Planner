---
name: Platform baseline
about: Cluster-wide PostgreSQL readiness, done once before the pilot cuts over
title: "[Platform] PostgreSQL platform baseline"
labels: platform
---

Cluster-wide work done once in Phase 1 and reused by every application. Config starting points are in [docs/GUIDELINES.md](../blob/main/docs/GUIDELINES.md). The DR and restore-drill items must be done before Wave 3 starts.

### Provisioning
- [ ] HA cluster (≥2 members) sized from the Cloudant inventory plus 2× headroom
- [ ] Separate dev / stage / prod; tenancy model decided (shared cluster with a DB per app, or a dedicated cluster for critical apps)
- [ ] Parameter baseline kept in IaC (Terraform)
- [ ] Extensions approved: `pg_stat_statements`, `pg_partman`, `pgcrypto`
- [ ] Storage and IOPS headroom; disk alert at 70%

### Connection management (PgBouncer)
- [ ] PgBouncer deployed with HA (≥2 replicas), transaction pooling
- [ ] Prepared-statement strategy decided (PgBouncer ≥1.21 `max_prepared_statements`, or driver setting)
- [ ] Pool sizing documented (`default_pool_size × pools < max_connections − reserved`)
- [ ] Developer guide on what transaction pooling breaks (`SET`, advisory locks, `LISTEN/NOTIFY`, temp tables)
- [ ] Direct (non-pooled) path for migrations, batch jobs and `pg_dump`

### Vacuum & maintenance
- [ ] Global autovacuum tuned (workers, naptime, cost limit, scale factors)
- [ ] `idle_in_transaction_session_timeout` set
- [ ] Monthly job: `VACUUM (FREEZE, ANALYZE)` on the partition that just closed
- [ ] Alerts: XID age, dead-tuple ratio, long-running transactions, bloat

### Backup & DR
- [ ] Daily backups plus PITR enabled; retention agreed with compliance
- [ ] Quarterly restore drill, with measured restore time recorded
- [ ] Cross-region replica or documented DR plan (required before Wave 3)
- [ ] Closed partitions archived to COS as Parquet

### Logical replication / CDC
- [ ] CDC approach chosen (`pgoutput` publications, or Debezium → Event Streams)
- [ ] `max_slot_wal_keep_size` set; slot lag and retained-WAL alerts
- [ ] Standard: `publish_via_partition_root = true`, replica identity on every table
- [ ] DDL change procedure agreed with CDC consumers
- [ ] DuckLake / reporting feed wired from CDC

### Security & compliance
- [ ] TLS enforced (`sslmode=verify-full`)
- [ ] Role model: owner / app read-write / read-only / migration
- [ ] Credentials in Secrets Manager, with rotation tested
- [ ] Audit logging (pgaudit) where compliance requires it
- [ ] Private endpoints only

### Shared toolkit
- [ ] Backfill tool: Cloudant `_all_docs` → transform → `COPY` into staging partition, with dead-letter table
- [ ] Changes-feed tailer with a saved `since` seq checkpoint
- [ ] Reconciler: counts, per-key checksums, business aggregates
- [ ] Partition manager (`pg_partman` or cron) creating partitions 3 months ahead
- [ ] Schema migration tool in CI (Flyway / Liquibase / golang-migrate)
- [ ] Cutover runbook and rollback templates published

### Observability
- [ ] Dashboards: QPS, p95/p99 latency, connections (PgBouncer and Postgres), cache hit ratio, replication lag, disk, locks
- [ ] `pg_stat_statements` top-20 reviewed weekly
- [ ] Slow query logging (`log_min_duration_statement`)
- [ ] Alerts routed to each app team's on-call
