---
name: Application migration
about: Per-app checklist for moving an application's monthly Cloudant databases to PostgreSQL
title: "[Migration] {{APP}}"
labels: migration
---

**Application:** {{APP}}
**Wave:** {{WAVE}}
**Lead:** {{LEAD}}

Playbook and config baselines: [docs/GUIDELINES.md](../blob/main/docs/GUIDELINES.md). Tick items as they're done; strike through (`~~item~~`) anything that doesn't apply and add a comment explaining why.

### Discovery
- [ ] Inventory: every monthly DB with size, doc count and write rate
- [ ] Doc shapes profiled (sample ~10k docs per type); field variance known
- [ ] Views, MapReduce, search indexes and attachments catalogued
- [ ] Every `_changes` consumer identified (including from Cloudant access logs)
- [ ] RTO/RPO and retention requirements defined
- [ ] Complexity scored and wave assigned

### Schema & data model
- [ ] Doc-type → table mapping reviewed by the DB guild
- [ ] Monthly range partitioning, one partition per former Cloudant DB; partition key in every PK/unique constraint
- [ ] Default partition created, with an alert on any rows in it
- [ ] Idempotency key plus `UNIQUE` constraint on event-driven tables
- [ ] Cloudant views mapped to B-tree/GIN indexes or materialized views
- [ ] Attachments moved to COS; object key stored in the row
- [ ] Per-table autovacuum overrides on the hot current-month partition
- [ ] App role, PgBouncer pool and per-role connection limit created
- [ ] Role-level `statement_timeout` and `lock_timeout` set
- [ ] Retention implemented as `DETACH`/`DROP PARTITION`, never `DELETE`
- [ ] Schema migrations run from CI (expand → migrate → contract)

### Migration execution
- [ ] Closed months backfilled via `COPY`
- [ ] Closed months verified month by month: counts, per-key checksums, business aggregates (report linked)
- [ ] Dead-letter table empty, or every row triaged
- [ ] Current month syncing (changes-feed tail or dual-write behind a flag)
- [ ] Continuous reconciliation green for N consecutive days
- [ ] Shadow reads with 0 mismatches for N days
- [ ] All hot queries filter on the partition key (pruning verified with `EXPLAIN`)
- [ ] Load test at 2× peak through PgBouncer
- [ ] Downstream consumers moved to CDC / DuckLake feed

### Cutover readiness
- [ ] Cutover runbook rehearsed in staging
- [ ] Rollback path tested end to end
- [ ] On-call briefed; dashboards and alerts live
- [ ] Go/no-go from DB guild recorded on this issue
- [ ] Cutover scheduled at a month boundary

### Cutover
- [ ] Freeze → drain tail → final reconcile → flip flag
- [ ] Cloudant set to read-only

### Decommission
- [ ] Stable in production for 2 weeks
- [ ] Cloudant kept read-only for 1–2 billing cycles
- [ ] Final export to COS (Parquet) with checksums stored
- [ ] Dual-write code, feature flags and Cloudant SDK removed
- [ ] Cloudant instances deleted; savings recorded
