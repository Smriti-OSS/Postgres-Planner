#!/usr/bin/env bash
# Creates labels, phase milestones, the platform baseline issue and one
# migration issue per application listed in apps.txt.
# Safe to re-run: existing labels are updated and existing issues (matched by title) are skipped.
#
# Env:
#   REPO     owner/name (default: the repo of the current directory)
#   DRY_RUN  1 = print what would be created, change nothing
set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true   # keep '&' literal in ${var//pat/rep} on bash ≥5.2

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
DRY_RUN="${DRY_RUN:-0}"
APP_TEMPLATE="$ROOT/.github/ISSUE_TEMPLATE/app-migration.md"
PLATFORM_TEMPLATE="$ROOT/.github/ISSUE_TEMPLATE/platform-baseline.md"

run() {
  if [[ "$DRY_RUN" == "1" ]]; then echo "  [dry-run] $*"; else "$@"; fi
}

trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

# Template body without its YAML front matter.
body_of() { awk 'NR==1 && /^---$/ {fm=1; next} fm && /^---$/ {fm=0; next} !fm' "$1"; }

# Relative doc links in templates point at ../blob/main/...; make them absolute for issues.
absolutize() { local b="$1"; printf '%s' "${b//"](../blob/main/"/"](https://github.com/$REPO/blob/main/"}"; }

milestone_for() {
  case "$1" in
    pilot) echo "Phase 2 - Pilot" ;;
    w1)    echo "Phase 3 - Wave 1" ;;
    w2)    echo "Phase 4 - Wave 2" ;;
    w3)    echo "Phase 5 - Wave 3" ;;
    *)     echo "" ;;
  esac
}
wave_label() {
  case "$1" in
    pilot) echo "wave:pilot" ;; w1) echo "wave:1" ;; w2) echo "wave:2" ;; w3) echo "wave:3" ;; *) echo "" ;;
  esac
}
wave_name() {
  case "$1" in
    pilot) echo "Pilot" ;; w1) echo "Wave 1" ;; w2) echo "Wave 2" ;; w3) echo "Wave 3" ;; *) echo "Unassigned" ;;
  esac
}

echo "Repository: $REPO"
[[ "$DRY_RUN" == "1" ]] && echo "Dry run: nothing will be changed."

echo "== Labels"
while IFS='|' read -r name color desc; do
  run gh label create "$name" --repo "$REPO" --color "$color" --description "$desc" --force >/dev/null
  echo "  $name"
done <<'EOF'
migration|1E6A73|Cloudant → PostgreSQL application migration
platform|5B6675|Cluster-wide PostgreSQL platform work
wave:pilot|0E8A16|Migration pilot
wave:1|C2E0C6|Migration wave 1
wave:2|FBCA04|Migration wave 2
wave:3|D93F0B|Migration wave 3 (critical / billing path)
EOF

echo "== Milestones"
existing_milestones="$(gh api "repos/$REPO/milestones?state=all&per_page=100" --jq '.[].title')"
while IFS='|' read -r title desc; do
  if grep -qxF "$title" <<<"$existing_milestones"; then
    echo "  exists: $title"
  else
    run gh api -X POST "repos/$REPO/milestones" -f title="$title" -f description="$desc" >/dev/null
    echo "  created: $title"
  fi
done <<'EOF'
Phase 0 - Discovery & inventory|Catalog DBs, doc shapes, views and _changes consumers; score and assign waves
Phase 1 - Platform foundation|HA Postgres, PgBouncer, PITR, monitoring, partition automation, toolkit
Phase 2 - Pilot|One medium-complexity app end to end
Phase 3 - Wave 1|Low-risk, low-coupling apps
Phase 4 - Wave 2|Medium complexity, more consumers
Phase 5 - Wave 3|Critical / billing-path apps; load test and DR drill first
Phase 6 - Decommission & optimize|Archive to COS, delete Cloudant, remove dual-write code
EOF

existing_issues="$(gh issue list --repo "$REPO" --state all --limit 1000 --json title --jq '.[].title')"

create_issue() {  # title body labels(comma) milestone assignee
  local title="$1" body="$2" labels="$3" milestone="$4" assignee="$5"
  if grep -qxF "$title" <<<"$existing_issues"; then
    echo "  exists: $title"; return
  fi
  local args=(--repo "$REPO" --title "$title" --body "$body" --label "$labels")
  [[ -n "$milestone" ]] && args+=(--milestone "$milestone")
  if [[ -n "$assignee" ]]; then
    run gh issue create "${args[@]}" --assignee "$assignee" >/dev/null \
      || { echo "  (could not assign @$assignee; creating unassigned)"; run gh issue create "${args[@]}" >/dev/null; }
  else
    run gh issue create "${args[@]}" >/dev/null
  fi
  echo "  created: $title"
}

echo "== Platform baseline"
create_issue "[Platform] PostgreSQL platform baseline" \
  "$(absolutize "$(body_of "$PLATFORM_TEMPLATE")")" "platform" "Phase 1 - Platform foundation" ""

echo "== Application issues"
app_body="$(absolutize "$(body_of "$APP_TEMPLATE")")"
while IFS= read -r line || [[ -n "$line" ]]; do
  line="$(trim "${line%%#*}")"
  [[ -z "$line" ]] && continue
  IFS='|' read -r name wave lead <<<"$line"
  name="$(trim "$name")"; wave="$(trim "${wave:-tbd}")"; lead="$(trim "${lead:-}")"
  [[ -z "$name" ]] && continue

  assignee=""
  [[ "$lead" == @* ]] && assignee="${lead#@}"

  body="${app_body//"{{APP}}"/$name}"
  body="${body//"{{WAVE}}"/$(wave_name "$wave")}"
  body="${body//"{{LEAD}}"/${lead:-_unassigned_}}"

  labels="migration"
  wl="$(wave_label "$wave")"; [[ -n "$wl" ]] && labels="$labels,$wl"

  create_issue "[Migration] $name" "$body" "$labels" "$(milestone_for "$wave")" "$assignee"
done < "$ROOT/apps.txt"

echo "Done."
