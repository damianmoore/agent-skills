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
#   score_compute <R> <I> <C> <E> <radius> <type>   "<priority>\t<score>\t<Radius>" (see below)
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

# ---------- scoring (tracker.sh set-score) ----------
# The one home of the score arithmetic; the judging rubric (what each tier means) lives in the
# skill named by scoring.skill. Inputs are tiers, so a scorer picks a meaning, not a number:
#   reach R 1-5       -> 1 2 4 8 16      (doubling: tier 5 reaches ~16x as many as tier 1)
#   impact I          -> 3 2 1 0.5 0.25  (Intercom's massive/high/medium/low/minimal)
#   confidence C      -> 100 80 50       (percent)
#   effort E 1-5      -> 0.5 1 2 4 8     (doubling)
#   radius            -> critical | wide | limited | contained
# score = R*I*(C/100)/E, one decimal. Priority: P1 at score >= 10, P2 at >= 2, else P3. On a
# `fix` ticket the radius sets a floor, because live harm outranks the arithmetic: critical
# -> P0, wide -> at least P1. On any other type the radius is change risk and leaves the
# priority alone.
SCORE_P1=10
SCORE_P2=2
SCORE_RADII=(Critical Wide Limited Contained)

score_compute() {
  local r=$1 i=$2 c=$3 e=$4 radius=${5,,} type=$6 rv ev score p
  case "$r" in 1) rv=1 ;; 2) rv=2 ;; 3) rv=4 ;; 4) rv=8 ;; 5) rv=16 ;;
    *) die "reach must be a tier 1-5, got '$r'" ;; esac
  case "$i" in 3|2|1|0.5|0.25) ;; *) die "impact must be 3, 2, 1, 0.5 or 0.25, got '$i'" ;; esac
  case "$c" in 100|80|50) ;; *) die "confidence must be 100, 80 or 50, got '$c'" ;; esac
  case "$e" in 1) ev=0.5 ;; 2) ev=1 ;; 3) ev=2 ;; 4) ev=4 ;; 5) ev=8 ;;
    *) die "effort must be a tier 1-5, got '$e'" ;; esac
  case "$radius" in critical|wide|limited|contained) ;;
    *) die "radius must be critical, wide, limited or contained, got '$5'" ;; esac
  score=$(awk -v r="$rv" -v i="$i" -v c="$c" -v e="$ev" 'BEGIN { printf "%.1f", r * i * c / 100 / e }')
  p=$(awk -v s="$score" -v p1="$SCORE_P1" -v p2="$SCORE_P2" \
    'BEGIN { print (s >= p1 ? "P1" : (s >= p2 ? "P2" : "P3")) }')
  if [ "$type" = fix ]; then
    case "$radius" in
      critical) p=P0 ;;
      wide) [ "$p" = P0 ] || p=P1 ;;
    esac
  fi
  printf '%s\t%s\t%s\n' "$p" "$score" "${radius^}"
}
