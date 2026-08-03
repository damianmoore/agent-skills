#!/usr/bin/env bash
# Manage cards on the GitHub Projects v2 board configured in .agent/project.yml.
#
# Usage:
#   board.sh add <issue-number>                Put the issue on the board (idempotent)
#   board.sh status <issue-number> <column>    Set its column (adds the card first if needed)
#   board.sh show <issue-number>               Print the card's current column
#
# Columns: Draft | Ready | In progress | In review | Merged | Released | Parked
#
# The board owner, repo, and title come from .agent/project.yml in the repo you are working
# in (github.owner / github.repo / github.project_title) — see project-config.sh.
#
# Requires the gh 'project' scope. If the commands below fail with a scope error:
#   gh auth refresh -s project,read:project
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

die() { echo "board.sh: $*" >&2; exit 1; }

[ $# -ge 2 ] || { grep '^#' "$0" | tail -n +2 | sed 's/^# \{0,1\}//' | head -14; exit 1; }
cmd=$1 issue=$2 column="${3:-}"

OWNER=$("$HERE/project-config.sh" github.owner)
REPO=$("$HERE/project-config.sh" github.repo)
PROJECT_TITLE=$("$HERE/project-config.sh" github.project_title)

projects=$(gh project list --owner "$OWNER" --format json 2>&1) \
  || die "cannot list projects — token likely lacks the 'project' scope; run: gh auth refresh -s project,read:project"
proj_number=$(jq -r --arg t "$PROJECT_TITLE" '.projects[] | select(.title == $t) | .number' <<<"$projects")
proj_id=$(jq -r --arg t "$PROJECT_TITLE" '.projects[] | select(.title == $t) | .id' <<<"$projects")
[ -n "$proj_number" ] || die "project '$PROJECT_TITLE' not found — run bootstrap-board.sh first"

item_id_for() {
  # --limit bounds how many cards are fetched: a board with more than 500 items would need it raised.
  gh project item-list "$proj_number" --owner "$OWNER" --format json --limit 500 \
    | jq -r --argjson n "$1" '.items[] | select(.content.number == $n) | .id' | head -1
}

add_card() {
  local id
  id=$(item_id_for "$issue")
  if [ -z "$id" ]; then
    # Take the id from item-add's own output — item-list can lag right after an add.
    id=$(gh project item-add "$proj_number" --owner "$OWNER" \
      --url "https://github.com/$REPO/issues/$issue" --format json | jq -r '.id // empty')
  fi
  [ -n "$id" ] || die "failed to add issue #$issue to the board"
  echo "$id"
}

# The lifecycle field is "Stage" if bootstrap had to fall back, otherwise the built-in "Status".
fields=$(gh project field-list "$proj_number" --owner "$OWNER" --format json)
field_name=$(jq -r 'if any(.fields[]; .name == "Stage") then "Stage" else "Status" end' <<<"$fields")
field_id=$(jq -r --arg f "$field_name" '.fields[] | select(.name == $f) | .id' <<<"$fields")

case "$cmd" in
  add)
    add_card >/dev/null
    echo "issue #$issue is on the board"
    ;;
  status)
    [ -n "$column" ] || die "usage: board.sh status <issue-number> <column>"
    option_id=$(jq -r --arg f "$field_name" --arg c "$column" \
      '.fields[] | select(.name == $f) | .options[] | select(.name == $c) | .id' <<<"$fields")
    [ -n "$option_id" ] || die "no column '$column' on field '$field_name' (check spelling/case)"
    item_id=$(add_card)
    gh project item-edit --id "$item_id" --project-id "$proj_id" \
      --field-id "$field_id" --single-select-option-id "$option_id" >/dev/null
    echo "issue #$issue -> $column"
    ;;
  show)
    item_id=$(item_id_for "$issue")
    [ -n "$item_id" ] || die "issue #$issue is not on the board"
    gh project item-list "$proj_number" --owner "$OWNER" --format json --limit 500 \
      | jq -r --argjson n "$issue" --arg f "$field_name" \
        '.items[] | select(.content.number == $n) | (.[$f | ascii_downcase] // .status // "(no column)")'
    ;;
  *)
    die "unknown command '$cmd'"
    ;;
esac
