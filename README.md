# Postgres Planner

Roadmap, guidelines and tracked checklists for moving our applications' monthly Cloudant databases to PostgreSQL.

Progress is tracked in **GitHub Issues**:

- one **Platform baseline** issue for cluster-wide work that is done once (PgBouncer, autovacuum, backups/PITR, logical replication, security, shared toolkit), and
- one **migration issue per application**, holding the per-app checklist (discovery → schema → migration → cutover → decommission).

Each issue's checklist is a task list, so GitHub shows progress like "12 of 35 tasks" on the issue and in any Project board it is added to.

## Live tracker

**https://smriti-oss.github.io/Postgres-Planner/** is a dashboard built from the issues. It has the roadmap timeline, an app-by-section progress matrix, the platform baseline, the per-app checklists and the guidelines. It re-reads the issues every 90 seconds.

- **Anyone can view it**; no sign-in needed.
- **To tick items from the page**, choose *Turn on editing* and paste a [fine-grained personal access token](https://github.com/settings/personal-access-tokens/new) scoped to this repository only, with **Issues: Read and write**. Each click updates the checklist in the issue body, so the page and the issue always agree. Status cycles To do → Done → N/A; N/A is written as a struck-through item.
- The token stays in your browser (this tab only, unless you tick *Remember*) and is sent only to `api.github.com`.

The page lives in [site/](site/) and is deployed by [pages.yml](.github/workflows/pages.yml) on every push to `site/`.

## What's in the repo

| Path | Purpose |
|---|---|
| [docs/ROADMAP.md](docs/ROADMAP.md) | Phases, waves, timeline and exit criteria |
| [docs/GUIDELINES.md](docs/GUIDELINES.md) | Principles, per-app playbook, config baselines, risks, governance |
| [apps.txt](apps.txt) | The list of applications, their wave and lead: the input for the bootstrap |
| [.github/ISSUE_TEMPLATE/](.github/ISSUE_TEMPLATE/) | Checklist templates (per app and platform baseline) |
| [scripts/bootstrap-issues.sh](scripts/bootstrap-issues.sh) | Creates labels, phase milestones and all issues (safe to re-run) |
| [.github/workflows/bootstrap-issues.yml](.github/workflows/bootstrap-issues.yml) | Runs the bootstrap from the Actions tab |

## Getting started

1. **Edit [apps.txt](apps.txt)**: replace the placeholder names with your real applications, set each one's wave, and optionally a lead as `@github-username`.
2. **Create the issues**, by either method:
   - **From GitHub**: Actions → *Bootstrap migration issues* → *Run workflow*. Leave *dry run* ticked the first time to preview what it will create, then run it again with *dry run* unticked.
   - **Locally** (needs the [GitHub CLI](https://cli.github.com/) and `gh auth login`):
     ```bash
     DRY_RUN=1 scripts/bootstrap-issues.sh   # preview
     scripts/bootstrap-issues.sh             # create
     ```
3. *(Optional)* Create a GitHub Project, add all issues labelled `migration`, and group by milestone to get a board across all apps.

The bootstrap is idempotent: it skips any issue whose title already exists. To add an application later, append it to `apps.txt` and run the bootstrap again, or open a new issue from the **Application migration** template.

## Working the checklists

- Tick items directly on the issue. Put evidence (reconciliation reports, PR links, decisions) in a comment, and link it from the item where useful.
- Strike through an item that doesn't apply to an app (`~~item~~`) and add a note on why, instead of deleting it.
- Cutover needs a go/no-go from the DB guild: every item in *Migration execution* and *Cutover readiness* ticked.
