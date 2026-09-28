#!/usr/bin/env bash
# GitHub forge adapter: review requests are pull requests. REST throughout — no GraphQL
# budget, and unaffected by the Projects-classic bug that breaks `gh pr edit` on older gh.
#
#   current-review [branch]                      "<n>\t<url>" of the open review request for a
#                                                branch (default: current), or nothing
#   open <title> <body-file> [--label L]... [--draft]
#                                                open one from the current branch into the base
#                                                branch, assign the reviewer, request their
#                                                review; prints "<n>\t<url>"
#   request-review <n> [login]                   request a review (default: the reviewer); a
#                                                self-authored PR is reported, not failed
#   get-body <n> | set-body <n> <file>
#   comment <n> [text]                           conversation comment (stdin when text omitted)
#   review-state <n>                             JSON {approved, changes_requested, reviews:[latest per reviewer]}
#   feedback <n>                                 JSON {body, reviews, comments, inline} — every
#                                                place a reviewer can leave an answer
#   merge <n> <subject> <body>                   squash-merge with exactly this message, delete the branch
#   close <n> <comment>                          comment, close unmerged, delete the branch
#   url <n> | link <n>                           URL, or a markdown link "[#51](…)"
#   file-url <path> [ref]                        link to a file on a branch (default: base branch)
#   branch-url <branch>
#   noun                                         what this forge calls a review request
#
# Config (.agent/project.yml): forge.repo, forge.reviewer, forge.base_branch (default main) —
# falling back to the legacy github.repo / github.assignee.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib.sh"

usage() { awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0" | sed '/^Config/,$d'; exit 2; }
[ $# -ge 1 ] || usage
cmd=$1; shift

REPO=$(cfg_req forge.repo github.repo)
REVIEWER=$(cfg "" forge.reviewer github.assignee)
BASE=$(cfg main forge.base_branch)

num() { local n=${1#\#}; [[ $n =~ ^[0-9]+$ ]] || die "expected a PR number, got '$1'"; echo "$n"; }
arg() { [ $# -ge "$1" ] || die "usage: $cmd — run with no arguments for the verbs"; }

request_review() {
  local n=$1 login=$2 out
  [ -n "$login" ] || { echo "no reviewer configured (forge.reviewer) — review not requested"; return 0; }
  if out=$(gh api -X POST "repos/$REPO/pulls/$n/requested_reviewers" -f "reviewers[]=$login" --silent 2>&1); then
    echo "review requested from $login"
  elif [[ $out == *"pull request author"* ]]; then
    # GitHub refuses a review request from the PR's own author; the assignment already puts it
    # on their list, so this is expected in a single-identity setup, not an error.
    echo "review request skipped: $login opened this PR (it is assigned to them instead)"
  else
    echo "review request to $login failed: $out" >&2
  fi
}

case "$cmd" in
  current-review)
    branch=${1:-$(git rev-parse --abbrev-ref HEAD)}
    gh api "repos/$REPO/pulls?state=open&head=${REPO%%/*}:$branch" --jq '.[] | "\(.number)\t\(.html_url)"'
    ;;
  open)
    arg 2 "$@"; title=$1 body_file=$2; shift 2
    [ -f "$body_file" ] || die "no body file '$body_file'"
    labels=() draft=false
    while [ $# -gt 0 ]; do
      case "$1" in --label) labels+=("$2"); shift 2 ;; --draft) draft=true; shift ;; *) die "unknown option $1" ;; esac
    done
    head=$(git rev-parse --abbrev-ref HEAD)
    [ "$head" != "$BASE" ] || die "on $BASE — nothing to open a review request from"
    pr=$(gh api -X POST "repos/$REPO/pulls" -f title="$title" -f head="$head" -f base="$BASE" \
      -F body=@"$body_file" -F draft="$draft" --jq '"\(.number)\t\(.html_url)"')
    n=${pr%%$'\t'*}
    if [ -n "$REVIEWER" ]; then
      gh api -X POST "repos/$REPO/issues/$n/assignees" -f "assignees[]=$REVIEWER" --silent
    fi
    for l in "${labels[@]}"; do gh api -X POST "repos/$REPO/issues/$n/labels" -f "labels[]=$l" --silent; done
    request_review "$n" "$REVIEWER" >&2
    echo "$pr"
    ;;
  request-review) arg 1 "$@"; request_review "$(num "$1")" "${2:-$REVIEWER}" ;;
  get-body) arg 1 "$@"; gh api "repos/$REPO/pulls/$(num "$1")" --jq '.body // ""' ;;
  set-body)
    arg 2 "$@"; [ -f "$2" ] || die "no body file '$2'"
    gh api -X PATCH "repos/$REPO/pulls/$(num "$1")" -F body=@"$2" --silent
    echo "body of PR #$(num "$1") updated"
    ;;
  comment)
    arg 1 "$@"; n=$(num "$1")
    if [ $# -ge 2 ]; then gh api -X POST "repos/$REPO/issues/$n/comments" -f body="$2" --jq .html_url
    else gh api -X POST "repos/$REPO/issues/$n/comments" -F body=@- --jq .html_url; fi
    ;;
  review-state)
    arg 1 "$@"
    # Latest non-comment review per reviewer — the same rule GitHub's reviewDecision applies.
    gh api --paginate "repos/$REPO/pulls/$(num "$1")/reviews" | jq -s '
      [add // [] | .[] | select(.state != "COMMENTED" and .state != "PENDING")]
      | group_by(.user.login) | map(max_by(.submitted_at))
      | { approved: (any(.state == "APPROVED") and (any(.state == "CHANGES_REQUESTED") | not)),
          changes_requested: any(.state == "CHANGES_REQUESTED"),
          reviews: map({user: .user.login, state, submitted_at}) }'
    ;;
  feedback)
    arg 1 "$@"; n=$(num "$1")
    jq -n \
      --argjson pr "$(gh api "repos/$REPO/pulls/$n")" \
      --argjson reviews "$(gh api --paginate "repos/$REPO/pulls/$n/reviews" | jq -s 'add // []')" \
      --argjson comments "$(gh api --paginate "repos/$REPO/issues/$n/comments" | jq -s 'add // []')" \
      --argjson inline "$(gh api --paginate "repos/$REPO/pulls/$n/comments" | jq -s 'add // []')" '
      { body: $pr.body,
        reviews: [$reviews[] | {user: .user.login, state, body, submitted_at}],
        comments: [$comments[] | {user: .user.login, body, created_at}],
        inline: [$inline[] | {user: .user.login, path, line, body, created_at}] }'
    ;;
  merge)
    arg 3 "$@"; n=$(num "$1")
    head=$(gh api "repos/$REPO/pulls/$n" --jq .head.ref)
    gh api -X PUT "repos/$REPO/pulls/$n/merge" -f merge_method=squash \
      -f commit_title="$2" -f commit_message="$3" --jq .sha
    gh api -X DELETE "repos/$REPO/git/refs/heads/$head" --silent 2>/dev/null \
      && echo "deleted branch $head" || echo "branch $head already gone"
    ;;
  close)
    arg 2 "$@"; n=$(num "$1")
    head=$(gh api "repos/$REPO/pulls/$n" --jq .head.ref)
    gh api -X POST "repos/$REPO/issues/$n/comments" -f body="$2" --silent
    gh api -X PATCH "repos/$REPO/pulls/$n" -f state=closed --silent
    gh api -X DELETE "repos/$REPO/git/refs/heads/$head" --silent 2>/dev/null \
      && echo "PR #$n closed; deleted branch $head" || echo "PR #$n closed; branch $head already gone"
    ;;
  url)        arg 1 "$@"; echo "https://github.com/$REPO/pull/$(num "$1")" ;;
  link)       arg 1 "$@"; echo "[#$(num "$1")](https://github.com/$REPO/pull/$(num "$1"))" ;;
  file-url)   arg 1 "$@"; echo "https://github.com/$REPO/blob/${2:-$BASE}/${1#./}" ;;
  branch-url) arg 1 "$@"; echo "https://github.com/$REPO/tree/$1" ;;
  noun)       echo "PR" ;;
  *) die "unknown verb '$cmd' — run with no arguments for the verbs" ;;
esac
