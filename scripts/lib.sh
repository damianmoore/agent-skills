#!/usr/bin/env bash
# Shared helpers for tracker.sh, forge.sh and their adapters. Source it; don't run it.
#
# Provides:
#   cfg <default> <key> [<fallback-key>...]   first key that is set, else <default>
#   cfg_req <key> [<fallback-key>...]          first key that is set, else die
#   status_column <key>                        board column a lifecycle key maps to
#   resolve_status <key-or-column>             column name for either form, or die
#   status_key <column>                        first lifecycle key mapping to a column
#   print_statuses                             "key<TAB>column" for the whole lifecycle
#   die <message>
#
# The lifecycle is fixed; the column each stage lands in is not. `statuses.<key>` in
# .agent/project.yml renames a column, and two keys may share one (merged + released both
# "Done") — moving between them is then a no-op, and status_key reports the earlier stage.

PLUGIN_SCRIPTS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=project-config.sh
source "$PLUGIN_SCRIPTS/project-config.sh"   # also turns on `set -euo pipefail`

die() { echo "$(basename "$0"): $*" >&2; exit 1; }

_CFG_UNSET=$'\x1f__unset__'

cfg() {
  local default=$1 key value
  shift
  for key; do
    value=$(project_config "$key" "$_CFG_UNSET") || exit 1   # missing file: already reported
    [ "$value" = "$_CFG_UNSET" ] || { printf '%s\n' "$value"; return 0; }
  done
  printf '%s\n' "$default"
}

cfg_req() {
  local value
  value=$(cfg "$_CFG_UNSET" "$@")
  [ "$value" != "$_CFG_UNSET" ] || die "none of: $* is set in $(project_config_file) — see the agent-skills README"
  printf '%s\n' "$value"
}

LIFECYCLE_KEYS=(draft ready in_progress in_review merged released parked)
declare -A LIFECYCLE_DEFAULT=(
  [draft]="Draft" [ready]="Ready" [in_progress]="In progress" [in_review]="In review"
  [merged]="Merged" [released]="Released" [parked]="Parked"
)
declare -A LIFECYCLE_MEANING=(
  [draft]="Plan being written or under review"
  [ready]="Plan locked; implementation not started"
  [in_progress]="Branch cut, milestones underway"
  [in_review]="Code milestones done, review request open"
  [merged]="In main; production rollout pending"
  [released]="Released to prod / complete / superseded-closed"
  [parked]="Deliberately not scheduled"
)

status_column() {
  [ -n "${LIFECYCLE_DEFAULT[$1]+x}" ] || die "unknown lifecycle key '$1' (${LIFECYCLE_KEYS[*]})"
  cfg "${LIFECYCLE_DEFAULT[$1]}" "statuses.$1"
}

resolve_status() {
  local arg=$1 key
  if [ -n "${LIFECYCLE_DEFAULT[$arg]+x}" ]; then status_column "$arg"; return; fi
  for key in "${LIFECYCLE_KEYS[@]}"; do
    # Accept a mapped column name, or the default name for a key (so "In review" still works
    # on a board that calls it "Code Review").
    if [ "$(status_column "$key")" = "$arg" ] || [ "${LIFECYCLE_DEFAULT[$key]}" = "$arg" ]; then
      status_column "$key"; return
    fi
  done
  die "'$arg' is neither a lifecycle key (${LIFECYCLE_KEYS[*]}) nor a configured column"
}

status_key() {
  local key
  for key in "${LIFECYCLE_KEYS[@]}"; do
    [ "$(status_column "$key")" = "$1" ] && { echo "$key"; return 0; }
  done
  echo "?"
}

print_statuses() {
  local key
  for key in "${LIFECYCLE_KEYS[@]}"; do printf '%s\t%s\n' "$key" "$(status_column "$key")"; done
}

# Distinct columns in lifecycle order (a shared column appears once).
distinct_columns() {
  local key col seen=$'\n'
  for key in "${LIFECYCLE_KEYS[@]}"; do
    col=$(status_column "$key")
    case "$seen" in *$'\n'"$col"$'\n'*) continue ;; esac
    seen+="$col"$'\n'
    printf '%s\t%s\n' "$key" "$col"
  done
}
