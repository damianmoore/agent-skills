#!/usr/bin/env bash
# One-time bootstrap of the GitHub Projects v2 kanban board configured in .agent/project.yml.
# Idempotent — safe to re-run. Requires the gh 'project' scope:
#   gh auth refresh -s project,read:project
#
# Creates the project, sets its Status columns to the plan lifecycle, links it to the repo,
# creates the feat/fix/chore/refactor/plan issue labels, and switches the default view to a
# board layout. The board owner, repo, and title come from .agent/project.yml
# (github.owner / github.repo / github.project_title) — see project-config.sh. Cards are
# added by board.sh as tickets are created; this script only builds the empty board.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

OWNER=$("$HERE/project-config.sh" github.owner)
REPO=$("$HERE/project-config.sh" github.repo)
PROJECT_TITLE=$("$HERE/project-config.sh" github.project_title)

projects=$(gh project list --owner "$OWNER" --format json 2>&1) || {
  echo "ERROR: cannot list projects — token lacks the 'project' scope." >&2
  echo "Run:  gh auth refresh -s project,read:project   then re-run this script." >&2
  exit 1
}

proj_number=$(jq -r --arg t "$PROJECT_TITLE" '.projects[] | select(.title == $t) | .number' <<<"$projects")
if [ -z "$proj_number" ]; then
  gh project create --owner "$OWNER" --title "$PROJECT_TITLE" >/dev/null
  projects=$(gh project list --owner "$OWNER" --format json)
  proj_number=$(jq -r --arg t "$PROJECT_TITLE" '.projects[] | select(.title == $t) | .number' <<<"$projects")
  echo "created project '$PROJECT_TITLE' (#$proj_number)"
else
  echo "project '$PROJECT_TITLE' already exists (#$proj_number)"
fi

gh project link "$proj_number" --owner "$OWNER" --repo "$REPO" >/dev/null 2>&1 \
  && echo "linked to $REPO" || echo "already linked to $REPO (or link unsupported)"

# --- Labels the pipeline files issues with: one type label per ticket, plus `plan` ---
# `gh issue create --label feat` hard-fails on a repo that has no such label, so create them
# up front. --force means create-or-update, which keeps this step idempotent.
label_failures=""
while IFS='|' read -r label_name label_color label_desc; do
  [ -n "$label_name" ] || continue
  gh label create "$label_name" -R "$REPO" \
    --description "$label_desc" --color "$label_color" --force >/dev/null 2>&1 </dev/null \
    || label_failures="$label_failures $label_name"
done <<'LABELS'
feat|0e8a16|Branch prefix feat/… — new capability
fix|d73a4a|Branch prefix fix/… — bug fix
chore|0075ca|Branch prefix chore/… — tooling, docs, ops
refactor|fbca04|Branch prefix refactor/… — behaviour-preserving restructure
plan|5319e7|Has a plan doc under docs/plans/
LABELS

if [ -z "$label_failures" ]; then
  echo "labels ready on $REPO: feat, fix, chore, refactor, plan"
else
  echo "labels ready on $REPO except:$label_failures — check write access to the repo"
fi

# --- Columns: replace the default Todo/In Progress/Done Status options with the lifecycle ---
fields=$(gh project field-list "$proj_number" --owner "$OWNER" --format json)
status_id=$(jq -r '.fields[] | select(.name == "Status") | .id' <<<"$fields")
have_ready=$(jq -r '[.fields[] | select(.name == "Status") | .options[].name] | index("Ready") != null' <<<"$fields")
have_stage=$(jq -r 'any(.fields[]; .name == "Stage")' <<<"$fields")

if [ "$have_ready" = "true" ] || [ "$have_stage" = "true" ]; then
  echo "lifecycle columns already configured"
else
  set +e
  gh api graphql -f query='
    mutation($fieldId: ID!) {
      updateProjectV2Field(input: {
        fieldId: $fieldId,
        singleSelectOptions: [
          {name: "Draft",       color: GRAY,   description: "Plan being written or under review"},
          {name: "Ready",       color: BLUE,   description: "Plan locked; implementation not started"},
          {name: "In progress", color: YELLOW, description: "Branch cut, milestones underway"},
          {name: "In review",   color: ORANGE, description: "Code milestones done, PR open"},
          {name: "Merged",      color: PURPLE, description: "In main; production rollout pending"},
          {name: "Released",    color: GREEN,  description: "Released to prod / complete / superseded-closed"},
          {name: "Parked",      color: PINK,   description: "Deliberately not scheduled"}
        ]
      }) { projectV2Field { ... on ProjectV2SingleSelectField { id } } }
    }' -f fieldId="$status_id" >/dev/null 2>&1
  rc=$?
  set -e
  if [ $rc -eq 0 ]; then
    echo "Status columns set: Draft / Ready / In progress / In review / Merged / Released / Parked"
  else
    echo "could not rewrite Status options via API — creating a 'Stage' field instead"
    gh project field-create "$proj_number" --owner "$OWNER" --name Stage \
      --data-type SINGLE_SELECT \
      --single-select-options "Draft,Ready,In progress,In review,Merged,Released,Parked" >/dev/null
    echo "NOTE: in the board UI, set the view's 'Group by' to Stage once (board.sh handles the rest)."
  fi
fi

# --- Make the default view an actual kanban board (it starts as a table) ---
proj_id=$(jq -r --arg t "$PROJECT_TITLE" '.projects[] | select(.title == $t) | .id' <<<"$projects")
view=$(gh api graphql -f query='
  query($id: ID!) { node(id: $id) { ... on ProjectV2 {
    views(first: 1) { nodes { id layout } } } } }' -f id="$proj_id" \
  --jq '.data.node.views.nodes[0]')
if [ "$(jq -r '.layout' <<<"$view")" != "BOARD_LAYOUT" ]; then
  gh api graphql -f query='
    mutation($viewId: ID!) {
      updateProjectV2View(input: {viewId: $viewId, layout: BOARD_LAYOUT, name: "Board"}) {
        projectV2View { id }
      }
    }' -f viewId="$(jq -r '.id' <<<"$view")" >/dev/null \
    && echo "default view switched to board layout" \
    || echo "could not switch the view layout via API — in the UI: view menu > Layout > Board"
fi

# The board URL differs for user and organization owners; ask GitHub once which this is.
owner_type=$(gh api "users/$OWNER" --jq .type 2>/dev/null) || owner_type=User
[ -n "$owner_type" ] || owner_type=User
if [ "$owner_type" = "Organization" ]; then
  board_url="https://github.com/orgs/$OWNER/projects/$proj_number"
else
  board_url="https://github.com/users/$OWNER/projects/$proj_number"
fi

echo
echo "Board ready: $board_url"
