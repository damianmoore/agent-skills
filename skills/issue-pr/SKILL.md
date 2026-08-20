---
name: issue-pr
description: Open a GitHub PR for the current branch with a reviewer-focused summary, assigned to the project's configured reviewer, and move the work's ticket to In review on the project's configured GitHub Projects board (per .agent/project.yml). Use when asked to create/open/raise a PR, make a pull request, or push a branch for review. This is the implementation PR; a plan-review PR on a plan/ branch belongs to issue-plan §7 instead.
---

# Create a pull request

Opens a PR for the current branch against `main`, writes a description aimed squarely at
the person reviewing it, and assigns it to the project's configured reviewer.

## Project config

The reviewer is repo-specific and lives in `.agent/project.yml` in the repo you are working
in. Read it **once**, at the start of the run, and substitute it wherever the commands below
show `<assignee>`:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/issue-update/project-config.sh github.assignee   # <assignee>
```

The helper exits non-zero and names the missing file or key. When that happens, tell the user
to add it to `.agent/project.yml` (the plugin README documents the schema) — never guess a
login. `board.sh` reads the config itself, so it takes no config arguments.

## 1. Gather context

Run these together and read the output before writing anything:

```bash
git rev-parse --abbrev-ref HEAD                  # current branch
git status --short                               # uncommitted work?
git log --oneline main..HEAD                     # commits in this branch
git diff main...HEAD --stat                      # files + churn
gh pr list --head "$(git rev-parse --abbrev-ref HEAD)" --state open --json number,url
```

**Check the branch first: plan PRs are not this skill's job.** If the current branch is
`plan/*`, or what you are being asked to open is the review gate for a plan document rather
than for code, stop here and follow **`issue-plan` §7** instead — those PRs are titled
`Plan: <topic>`, end their body `Part of #NN` (a closing keyword would close the ticket, and
the board's *Item closed* automation would slam the card from Draft straight to Merged before
any of the work existed), and leave the card in `Draft`, so §5's In review move does not apply
either. Everything below is for the **implementation** PR.

Then read the **actual diff** — `git diff main...HEAD` — before summarising. Never write a
PR body from commit messages alone; commit subjects say what was done, the diff says what
a reviewer needs to check. For large diffs read the substantive files in full and skim
generated/lockfile churn.

Stop and ask the user first if any of these hold:

- Current branch is `main` — there is nothing to open a PR from.
- A PR is already open for this branch — offer to update its body instead (`gh pr edit`).
- Uncommitted changes exist — ask whether to commit them (via the `git-commit` skill) or
  leave them out. Do not commit silently.

Push the branch if it has no upstream: `git push -u origin HEAD`.

## 2. Write the description

Sections scale with the diff — a two-file fix needs the first three, a milestone-sized
branch needs all of them. Drop any section that would be padding, keep the order.

**Write the body unwrapped.** GitHub renders a newline inside a paragraph as a line break,
so prose hard-wrapped at 80 columns keeps those breaks at every browser width and reads
ragged. Each paragraph and each bullet is one unbroken line, however long, with blank lines
only between blocks — let the browser do the wrapping. This is the opposite of the commit
convention: wrap commit messages, never wrap PR or issue bodies. The template below is
shown unwrapped for that reason; it will look over-long in an editor, and that is correct.

```markdown
## What this does

Two to four sentences on one line: the problem, and the shape of the fix. Lead with the user-visible or system-visible behaviour change, not the implementation. If it fixes a bug, state the symptom the bug produced.

## Why

The reason this change exists — the failure it prevents, the requirement it meets, the plan or milestone it belongs to. Link the plan doc under `docs/plans/` and the tracking issue. Skip if section 1 already makes it obvious.

## What changed

Grouped by area, each entry naming the file so a reviewer can jump straight there:

- `server/billing/limits.py` — new `plan_for()` resolution with sticky fail-open.
- `ui/components/PlanLimitNotice.tsx` — surfaces the cap to the user at the point of block.

## How to review this

The highest-value part of the description. Tell the reviewer:

- **Start here** — the one or two files carrying the actual logic.
- **Skim** — mechanical churn, renames, generated types, test fixtures.
- **Scrutinise** — anything subtle: off-by-ones on limit checks, cache keys, fail-open vs fail-closed branches, migration ordering, anything touching money or credits.

## Testing

What was actually run and what it did — the exact command and its result, e.g. the repo's configured test command with its pass count (`make test`, 76 passed), e2e spec names, manual steps in the local app. If something was not tested, say so plainly here rather than leaving the reviewer to assume coverage.

## Risk and rollout

Only when relevant: feature flags and their default state, DB migrations, config or secret changes, deploy ordering against the release, and how to roll back.

## Out of scope

Known follow-ups deliberately left for later, so the reviewer does not flag them as omissions. Note where they are tracked.
```

### Required when the diff touches a committed API spec snapshot

Repos that publish a versioned public API often commit a generated spec snapshot (an
OpenAPI JSON, a GraphQL SDL) with a test that fails until it is regenerated — so the fix is
always "run the regeneration command and commit", which anyone can do reflexively without
asking what changed. **The snapshot diff detects change; it does not classify it.** A
breaking change can ship on v1 that way without a single person deciding to.

So a PR whose diff includes such a snapshot must carry a section stating the classification
and the reason:

```markdown
## API compatibility

**Non-breaking — ships on v1.** Adds an optional `updated_since` filter to `GET /reports` and a `first_seen_at` field to the item listing. Existing clients see no change to any request they already send or any field they already read.
```

Classify against these rules:

- **Non-breaking, ships on the current version** — a new endpoint, a new optional parameter, a new response field, relaxed validation, a deprecation notice.
- **Breaking, needs a new `/v2/…` route** — removing or renaming a field or endpoint, a type change, a new required parameter, a changed error code or status for an existing condition, changed pagination or envelope semantics.
- **Breaking and invisible to the diff** — tightening a resolver's or handler's permission check changes what the API returns without altering the spec at all. If the diff touches code the API executes, say so here even when the snapshot is unchanged.

Two rules for the reviewer's sake: name the *specific* additions rather than saying
"regenerated snapshot", and if the change is breaking, the PR must add the v2 route rather
than argue that no client will notice.

Rules for the body:

- One line per paragraph and per bullet, as above. A bullet that needs a second line uses a
  real list item or a blank-line-separated paragraph, never a soft wrap.
- Be concrete. "Fixes the off-by-one in `can_add_podcast` (`<` → `<=`)" beats "improves
  limit handling".
- Accuracy over salesmanship. If a milestone is partly deferred, the PR body says which
  part and why.
- Never mention Claude, AI, or assistant tooling. No `Co-Authored-By` or "Generated with"
  trailers — this applies to PR bodies exactly as it does to commit messages.
- End the body with `Closes #NN` when the work has a ticket (the plan's `**Status:**` line
  carries the number; the `issue-update` skill explains how to find it otherwise). The
  closing keyword is load-bearing: merging into `main` closes the issue, and the project
  board's built-in **Item closed** workflow moves the card to **Merged**. A neutral
  `Tracking issue: #NN` would leave the card stranded in In review. This rule is for
  implementation PRs; a plan PR ends `Part of #NN` instead — see §1.
- Closing the ticket at merge does **not** mean the work is done — **Merged** still means
  "in `main`, rollout pending". Released is a separate, manual move on the already-closed
  issue.

## 3. Title

One line, present-tense imperative, aiming for ≤72 characters — same convention as commit
messages. `Enforce per-plan podcast and seat limits`, not `plan limits stuff` and not
`Fix/plan-limits-enforcement` (the branch-name default `gh` would otherwise pick).

Match the repo's existing style if unsure: `git log -10 --pretty=%s`.

## 4. Open it

Write the body to a scratchpad file rather than fighting shell quoting in `--body`:

```bash
gh pr create \
  --base main \
  --title "<imperative title>" \
  --body-file /path/to/scratchpad/pr-body.md \
  --assignee <assignee>
```

Then request review. GitHub rejects a review request from the PR's own author, so this
step is expected to fail whenever the configured reviewer is the same account that opened
the PR:

```bash
gh pr edit --add-reviewer <assignee> 2>&1 || true
```

If it fails with "review cannot be requested from pull request author", that is normal and
not an error to report as a problem — the `--assignee` above already puts the PR on their
list. Say so in one clause and move on. If a different collaborator should review, ask who
and use `--add-reviewer <login>` for them instead.

## 5. Update the ticket

Per the `issue-update` skill: move the card to **In review** and leave a comment with the
PR link and what remains (e.g. the rollout milestone and whose it is). Implementation PRs
only — a plan PR leaves the card in `Draft` (§1):

```bash
${CLAUDE_PLUGIN_ROOT}/skills/issue-update/board.sh status <issue#> "In review"
gh issue comment <issue#> --body "In review on PR #<pr> (branch \`<branch>\`). <what remains>"
```

If the branch has no ticket (untracked one-off work), skip this — don't invent one for a
trivial change.

## 6. Report back

Give the user the PR URL, the title, the ticket moved (or that none exists), and a
one-line note on what still needs a human (assignee set, review-request skipped as
self-review, tests pending, flag still off).
