#!/usr/bin/env bash
# GitHub tracker adapter: issues are tickets, a Projects v2 board holds the cards.
#
# Tickets (REST — separate budget from GraphQL, and unaffected by the Projects-classic bug
# that breaks `gh issue view`/`edit` on older gh releases):
#   create <type> <title> <body-file> [label...]   file a ticket; prints "<id>\t<url>"
#   view <id>                                    JSON {id,title,state,state_reason,labels,body,url}
#   search [text] [--all]                        "<id>\t<title>\t<labels>\t<state>"; open only unless --all
#   get-body <id>                                print the body
#   set-body <id> <file>                         replace the body
#   comment <id> [text]                          add a comment (text from stdin when omitted)
#   add-label <id> <label>
#   close <id> <completed|not-planned>
#   url <id> | link <id>                         URL, or a markdown link "[#42](…)"
#   closing-ref <id> | mention-ref <id>          text for a review-request body that closes the
#                                                ticket on merge ("Closes #42"), or only mentions it
#   branch <type> <kebab-topic>                  branch name for the work ("feat/kebab-topic")
#   capabilities                                 key=value facts the skills branch on
# Board (GraphQL, needs the gh 'project' scope):
#   add <id>                                     put the ticket on the board (idempotent)
#   status <id>                                  "<lifecycle-key>\t<column>"
#   set-status <id> <key-or-column>              move the card (adds it first if needed)
#   list <key-or-column>                         "<ref>\t<title>" for the cards in a column
#   bootstrap                                    create/repair the board, columns and labels
#
# Config (.agent/project.yml): tracker.repo, tracker.board_owner, tracker.board_title —
# falling back to the legacy github.repo / github.owner / github.project_title.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib.sh"

usage() { awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0" | sed '/^Config/,$d'; exit 2; }
[ $# -ge 1 ] || usage
cmd=$1; shift

REPO=$(cfg_req tracker.repo github.repo)
OWNER=$(cfg "${REPO%%/*}" tracker.board_owner github.owner)
TITLE=$(cfg "" tracker.board_title github.project_title)

num() { local n=${1#\#}; [[ $n =~ ^[0-9]+$ ]] || die "expected an issue number, got '$1'"; echo "$n"; }
arg() { [ $# -ge "$1" ] || die "usage: $cmd — run with no arguments for the verbs"; }

# ---------- board plumbing (only the board verbs pay for these GraphQL calls) ----------
board_init() {
  [ -n "$TITLE" ] || die "tracker.board_title (or github.project_title) is not set"
  local projects
  projects=$(gh project list --owner "$OWNER" --format json --limit 100 2>&1) || {
    # The Projects API is GraphQL-only, with an hourly budget `gh api rate_limit` can misreport —
    # and an exhausted budget surfaces here as "unknown owner type". Ask GraphQL directly, so a
    # rate limit isn't misdiagnosed as a missing scope (which needs a re-auth).
    case "$projects $(gh api graphql -f query='{viewer{login}}' 2>&1 >/dev/null)" in
      *"rate limit"*) die "GitHub's GraphQL rate limit is exhausted; retry after it resets (\`gh api -i graphql -f query='{viewer{login}}'\` shows X-Ratelimit-Reset)" ;;
      *) die "cannot list projects — token likely lacks the 'project' scope; run: gh auth refresh -s project,read:project ($projects)" ;;
    esac
  }
  PROJECTS_JSON=$projects
  proj_number=$(jq -r --arg t "$TITLE" '.projects[] | select(.title == $t) | .number' <<<"$projects")
  proj_id=$(jq -r --arg t "$TITLE" '.projects[] | select(.title == $t) | .id' <<<"$projects")
}

board_fields() {
  [ -n "$proj_number" ] || die "board '$TITLE' not found — run: tracker.sh bootstrap"
  fields=$(gh project field-list "$proj_number" --owner "$OWNER" --format json)
  # The lifecycle field is "Stage" if bootstrap had to fall back, otherwise the built-in "Status".
  field_name=$(jq -r 'if any(.fields[]; .name == "Stage") then "Stage" else "Status" end' <<<"$fields")
  field_id=$(jq -r --arg f "$field_name" '.fields[] | select(.name == $f) | .id' <<<"$fields")
}

option_id_for() {
  jq -r --arg f "$field_name" --arg c "$1" \
    '.fields[] | select(.name == $f) | .options[] | select(.name == $c) | .id' <<<"$fields"
}

# "<item-id>\t<column>" for this issue's card on our board, or nothing. Asks the issue for its
# own board items — one small query, instead of paging the whole board.
card_for() {
  gh api graphql -F n="$1" -f o="${REPO%%/*}" -f r="${REPO#*/}" -f f="$field_name" -f query='
    query($o: String!, $r: String!, $n: Int!, $f: String!) {
      repository(owner: $o, name: $r) { issue(number: $n) { projectItems(first: 50) { nodes {
        id project { id }
        fieldValueByName(name: $f) { ... on ProjectV2ItemFieldSingleSelectValue { name } }
      } } } } }' \
    --jq ".data.repository.issue.projectItems.nodes[] | select(.project.id == \"$proj_id\")
          | [.id, (.fieldValueByName.name // \"\")] | @tsv" | head -1
}

add_card() {
  local card id
  card=$(card_for "$1")
  if [ -n "$card" ]; then echo "${card%%$'\t'*}"; return; fi
  # Take the id from item-add's own output — reads can lag right after an add.
  id=$(gh project item-add "$proj_number" --owner "$OWNER" \
    --url "https://github.com/$REPO/issues/$1" --format json | jq -r '.id // empty')
  [ -n "$id" ] || die "failed to add issue #$1 to the board"
  echo "$id"
}

bootstrap() {
  board_init
  if [ -z "$proj_number" ]; then
    gh project create --owner "$OWNER" --title "$TITLE" >/dev/null
    echo "created project '$TITLE'"
    board_init
  else
    echo "project '$TITLE' already exists (#$proj_number)"
  fi
  gh project link "$proj_number" --owner "$OWNER" --repo "$REPO" >/dev/null 2>&1 \
    && echo "linked to $REPO" || echo "already linked to $REPO (or link unsupported)"

  # Labels: one type label per ticket, plus `plan`. Creating an issue with a missing label
  # hard-fails, so create them up front; --force (create-or-update) keeps this idempotent.
  local failures="" name color desc
  while IFS='|' read -r name color desc; do
    [ -n "$name" ] || continue
    gh label create "$name" -R "$REPO" --description "$desc" --color "$color" --force \
      >/dev/null 2>&1 </dev/null || failures="$failures $name"
  done <<'LABELS'
feat|0e8a16|Branch prefix feat/… — new capability
fix|d73a4a|Branch prefix fix/… — bug fix
chore|0075ca|Branch prefix chore/… — tooling, docs, ops
refactor|fbca04|Branch prefix refactor/… — behaviour-preserving restructure
plan|5319e7|Has a plan doc under docs/plans/
LABELS
  if [ -z "$failures" ]; then echo "labels ready on $REPO: feat, fix, chore, refactor, plan"
  else echo "labels ready on $REPO except:$failures — check write access to the repo"; fi

  # Columns, from the status map. Only a board still on GitHub's default Todo/In Progress/Done
  # gets its options rewritten: rewriting a live board's options would drop every card's value.
  board_fields
  local want have missing="" key col n=0 options=""
  have=$(jq -r --arg f "$field_name" '.fields[] | select(.name == $f) | .options[].name' <<<"$fields")
  local colors=(GRAY BLUE YELLOW ORANGE PURPLE GREEN PINK)
  while IFS=$'\t' read -r key col; do
    grep -Fxq -- "$col" <<<"$have" || missing="$missing, $col"
    options+="{name: $(jq -Rn --arg s "$col" '$s'), color: ${colors[$n]}, description: $(jq -Rn --arg s "${LIFECYCLE_MEANING[$key]}" '$s')},"
    n=$((n + 1))
  done < <(distinct_columns)
  missing=${missing#, }
  if [ -z "$missing" ]; then
    echo "lifecycle columns already configured"
  elif [ "$(sort <<<"$have" | tr '\n' ,)" = "Done,In Progress,Todo," ] || [ -z "$have" ]; then
    if gh api graphql -f fieldId="$field_id" -f query="
        mutation(\$fieldId: ID!) { updateProjectV2Field(input: {fieldId: \$fieldId,
          singleSelectOptions: [${options%,}]}) { projectV2Field { ... on ProjectV2SingleSelectField { id } } } }" \
        >/dev/null 2>&1; then
      echo "columns set: $(distinct_columns | cut -f2 | paste -sd/ | sed 's|/| / |g')"
    else
      echo "could not rewrite Status options via API — creating a 'Stage' field instead"
      gh project field-create "$proj_number" --owner "$OWNER" --name Stage --data-type SINGLE_SELECT \
        --single-select-options "$(distinct_columns | cut -f2 | paste -sd,)" >/dev/null
      echo "NOTE: in the board UI, set the view's 'Group by' to Stage once (the adapter handles the rest)."
    fi
  else
    echo "board is missing columns: $missing — add them in the board UI (not rewritten automatically: that would clear every card's column)"
  fi

  # Make the default view an actual kanban board (it starts as a table).
  local view
  view=$(gh api graphql -f id="$proj_id" -f query='
    query($id: ID!) { node(id: $id) { ... on ProjectV2 { views(first: 1) { nodes { id layout } } } } }' \
    --jq '.data.node.views.nodes[0]')
  if [ "$(jq -r '.layout' <<<"$view")" != "BOARD_LAYOUT" ]; then
    gh api graphql -f viewId="$(jq -r '.id' <<<"$view")" -f query='
      mutation($viewId: ID!) { updateProjectV2View(input: {viewId: $viewId, layout: BOARD_LAYOUT, name: "Board"}) {
        projectV2View { id } } }' >/dev/null \
      && echo "default view switched to board layout" \
      || echo "could not switch the view layout via API — in the UI: view menu > Layout > Board"
  fi

  local owner_type board_url
  owner_type=$(gh api "users/$OWNER" --jq .type 2>/dev/null) || owner_type=User
  if [ "$owner_type" = "Organization" ]; then board_url="https://github.com/orgs/$OWNER/projects/$proj_number"
  else board_url="https://github.com/users/$OWNER/projects/$proj_number"; fi

  # The merge → Merged move rests on the built-in "Item closed" workflow (capabilities:
  # close_moves_to=merged). The API can read workflows but not enable or configure them, so
  # check it and leave the switch to the UI.
  local merged_col closed_enabled
  merged_col=$(resolve_status merged)
  closed_enabled=$(gh api graphql -f id="$proj_id" -f query='
    query($id: ID!) { node(id: $id) { ... on ProjectV2 { workflows(first: 20) { nodes { name enabled } } } } }' \
    --jq '.data.node.workflows.nodes[] | select(.name == "Item closed") | .enabled' 2>/dev/null)
  if [ "$closed_enabled" = true ]; then
    echo "'Item closed' workflow enabled (check it sets $field_name to '$merged_col', not the default 'Done')"
  else
    echo "ACTION NEEDED: enable the 'Item closed' workflow in the UI — $board_url/workflows"
    echo "  > Item closed > Edit: When 'Issue, Pull request', Set value $field_name: '$merged_col' > Save and turn on workflow"
    echo "  (the API cannot do this; without it a merged PR leaves its ticket's card in the review column)"
  fi

  echo "Board ready: $board_url"
}

# ---------- verbs ----------
case "$cmd" in
  create)
    arg 3 "$@"
    type=$1 title=$2 body_file=$3; shift 3
    [ -f "$body_file" ] || die "no body file '$body_file'"
    label_args=(-f "labels[]=$type")
    for l in "$@"; do label_args+=(-f "labels[]=$l"); done
    gh api -X POST "repos/$REPO/issues" -f title="$title" -F body=@"$body_file" "${label_args[@]}" \
      --jq '"\(.number)\t\(.html_url)"'
    ;;
  view)
    arg 1 "$@"
    gh api "repos/$REPO/issues/$(num "$1")" --jq \
      '{id: .number, title, state, state_reason, labels: [.labels[].name], body, url: .html_url}'
    ;;
  search)
    text="" state=open
    for a in "$@"; do if [ "$a" = --all ]; then state=all; else text="$a"; fi; done
    q="repo:$REPO is:issue"
    [ "$state" = open ] && q="$q state:open"
    [ -n "$text" ] && q="$q $text"
    gh api -X GET search/issues -f q="$q" -f per_page=100 --jq \
      '.items[] | "\(.number)\t\(.title)\t\([.labels[].name] | join(","))\t\(.state)"'
    ;;
  get-body)
    arg 1 "$@"; gh api "repos/$REPO/issues/$(num "$1")" --jq '.body // ""' ;;
  set-body)
    arg 2 "$@"; [ -f "$2" ] || die "no body file '$2'"
    gh api -X PATCH "repos/$REPO/issues/$(num "$1")" -F body=@"$2" --silent
    echo "body of #$(num "$1") updated"
    ;;
  comment)
    arg 1 "$@"; n=$(num "$1")
    if [ $# -ge 2 ]; then gh api -X POST "repos/$REPO/issues/$n/comments" -f body="$2" --jq .html_url
    else gh api -X POST "repos/$REPO/issues/$n/comments" -F body=@- --jq .html_url; fi
    ;;
  add-label)
    arg 2 "$@"; gh api -X POST "repos/$REPO/issues/$(num "$1")/labels" -f "labels[]=$2" --silent
    echo "#$(num "$1") labelled $2"
    ;;
  close)
    arg 2 "$@"
    case "$2" in completed) reason=completed ;; not-planned) reason=not_planned ;;
      *) die "close reason must be completed or not-planned" ;; esac
    gh api -X PATCH "repos/$REPO/issues/$(num "$1")" -f state=closed -f state_reason="$reason" --silent
    echo "#$(num "$1") closed ($2)"
    ;;
  url)          arg 1 "$@"; echo "https://github.com/$REPO/issues/$(num "$1")" ;;
  link)         arg 1 "$@"; echo "[#$(num "$1")](https://github.com/$REPO/issues/$(num "$1"))" ;;
  closing-ref)  arg 1 "$@"; echo "Closes #$(num "$1")" ;;
  mention-ref)  arg 1 "$@"; echo "Part of #$(num "$1")" ;;
  branch)       arg 2 "$@"; echo "$1/$2" ;;
  capabilities)
    # closes_on_merge — a merged review request whose body carries closing-ref closes the ticket.
    # close_moves_to — the board's built-in "Item closed" workflow moves ANY closed ticket's card
    #   to this lifecycle stage, unconditionally; after a non-merge close, set the column again.
    # labels — tickets carry type labels.
    printf '%s\n' "closes_on_merge=yes" "close_moves_to=merged" "labels=yes" "ticket_noun=issue"
    ;;
  add)
    arg 1 "$@"; n=$(num "$1"); board_init; board_fields; add_card "$n" >/dev/null
    echo "#$(num "$1") is on the board"
    ;;
  status)
    arg 1 "$@"; n=$(num "$1"); board_init; board_fields
    card=$(card_for "$n")
    [ -n "$card" ] || die "#$n is not on the board '$TITLE'"
    col=${card#*$'\t'}
    printf '%s\t%s\n' "$(status_key "$col")" "${col:-(no column)}"
    ;;
  set-status)
    arg 2 "$@"; n=$(num "$1"); col=$(resolve_status "$2")
    board_init; board_fields
    option_id=$(option_id_for "$col")
    [ -n "$option_id" ] || die "board '$TITLE' has no column '$col' on field '$field_name' — run: tracker.sh bootstrap"
    card=$(card_for "$n")
    if [ -n "$card" ] && [ "${card#*$'\t'}" = "$col" ]; then
      echo "#$n already in $col ($(status_key "$col"))"
    else
      item_id=$(add_card "$n")
      gh project item-edit --id "$item_id" --project-id "$proj_id" \
        --field-id "$field_id" --single-select-option-id "$option_id" >/dev/null
      echo "#$n -> $col ($(status_key "$col"))"
    fi
    ;;
  list)
    arg 1 "$@"; col=$(resolve_status "$1")
    board_init; board_fields
    [ -n "$(option_id_for "$col")" ] || die "board '$TITLE' has no column '$col'"
    # --limit bounds how many cards are fetched: a board with more than 1000 items would need it raised.
    gh project item-list "$proj_number" --owner "$OWNER" --format json --limit 1000 \
      | jq -r --arg f "$field_name" --arg c "$col" \
        '.items[] | select((.[$f | ascii_downcase] // .status) == $c)
         | "#\(.content.number // "?")\t\(.content.title // .title)"'
    ;;
  bootstrap) bootstrap ;;
  *) die "unknown verb '$cmd' — run with no arguments for the verbs" ;;
esac
