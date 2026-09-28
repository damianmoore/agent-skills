---
name: issue-pr
description: Open a pull request (or the configured forge's review request) for the current branch with a reviewer-focused summary (plus screenshots of any UI change when the project configures a screenshots guide, kept current as later pushes change it), assigned to the project's configured reviewer, and move the work's ticket to In review on the project's configured board (per .agent/project.yml). Use when asked to create/open/raise a PR, make a pull request, push a branch for review, or refresh a PR's screenshots. This is the implementation PR; a plan-review PR on a plan/ branch belongs to issue-plan §7 instead.
---

# Create a pull request

Opens a PR for the current branch against `main`, writes a description aimed squarely at
the person reviewing it, adds screenshots when the diff changes the UI (and the project
configures a screenshots guide), and assigns it to the project's configured reviewer.

## Tools and config

Every forge and tracker call goes through `forge.sh` / `tracker.sh` (see `issue-create`,
*Tools and config*); they read the repo, reviewer and board from `.agent/project.yml`
themselves. This skill also reads, **once**, at the start of the run:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/project-config.sh pr.screenshots_guide ""   # repo's screenshot guide, if any
${CLAUDE_PLUGIN_ROOT}/scripts/project-config.sh pr.api_snapshots ""       # committed API spec snapshots, if any
```

Both are optional: empty means the project takes no PR screenshots, or names no API
snapshots (the §2 API-compatibility rule then still applies to any spec snapshot you spot in
the diff). "PR" below means whatever the forge calls a review request (`forge.sh noun` —
"MR" on GitLab); use that word in anything you write for a human.

## 1. Gather context

Run these together and read the output before writing anything:

```bash
git rev-parse --abbrev-ref HEAD                  # current branch
git status --short                               # uncommitted work?
git log --oneline main..HEAD                     # commits in this branch
git diff main...HEAD --stat                      # files + churn
${CLAUDE_PLUGIN_ROOT}/scripts/forge.sh current-review   # open PR for this branch, if any
```

**Check the branch first: plan PRs are not this skill's job.** If the current branch is
`plan/*`, or what you are being asked to open is the review gate for a plan document rather
than for code, stop here and follow **`issue-plan` §7** instead — those PRs are titled
`Plan: <topic>`, end their body with `tracker.sh mention-ref` rather than the closing ref (a
closing ref would close the ticket, and a tracker that moves closed cards would slam it from
Draft straight to Merged before any of the work existed), and leave the card in `draft`, so §6's In review move does not apply
either. Everything below is for the **implementation** PR.

Then read the **actual diff** — `git diff main...HEAD` — before summarising. Never write a
PR body from commit messages alone; commit subjects say what was done, the diff says what
a reviewer needs to check. For large diffs read the substantive files in full and skim
generated/lockfile churn.

While reading, note whether the diff changes what a user sees in the app. The project's
`pr.screenshots_guide` defines which paths count; when the project configures no guide,
skip screenshots entirely. If it does, the PR gets screenshots in §5.

Stop and ask the user first if any of these hold:

- Current branch is `main` — there is nothing to open a PR from.
- A PR is already open for this branch — offer to update its body instead, with
  `forge.sh get-body <n>` / `forge.sh set-body <n> <file>`.
- Uncommitted changes exist — ask whether to commit them (via `/git-commit`) or
  leave them out. Do not commit silently — the user may be keeping those changes out of
  this PR on purpose, and a stray commit on a reviewed branch is the hardest kind to unpick.

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

The paths are in `pr.api_snapshots` when the project names them; otherwise recognise one by
shape. Repos that publish a versioned public API often commit a generated spec snapshot (an
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

- Don't write a `## Screenshots` section here. §5 inserts it after "What changed" once the
  PR exists, captured from the pushed head.
- One line per paragraph and per bullet, as above. A bullet that needs a second line uses a
  real list item or a blank-line-separated paragraph, never a soft wrap.
- Be concrete. "Fixes the off-by-one in `can_add_podcast` (`<` → `<=`)" beats "improves
  limit handling".
- Accuracy over salesmanship. If a milestone is partly deferred, the PR body says which
  part and why.
- Never mention Claude, AI, or assistant tooling — the PR and the git history are written
  for the people maintaining the code, and tooling attribution is noise to them. No
  `Co-Authored-By` or "Generated with" trailers; this applies to PR bodies exactly as it
  does to commit messages.
- End the body with the ticket's closing reference when the work has a ticket —
  `tracker.sh closing-ref <id>` prints it (`Closes #42` on GitHub; the plan's `**Status:**`
  line carries the id, and the `issue-update` skill explains how to find it otherwise). It is
  load-bearing where `tracker.sh capabilities` says `closes_on_merge=yes`: merging into
  `main` closes the ticket, and on GitHub the board's built-in *Item closed* workflow moves
  the card to **Merged**. A neutral "Tracking issue: #42" would leave the card stranded in
  In review. This rule is for implementation PRs; a plan PR ends with `tracker.sh
  mention-ref <id>` instead — see §1.
- Closing the ticket at merge does **not** mean the work is done — **Merged** still means
  "in `main`, rollout pending". Released is a separate, manual move on the already-closed
  ticket.

## 3. Title

One line, present-tense imperative, aiming for ≤72 characters — same convention as commit
messages. `Enforce per-plan podcast and seat limits`, not `plan limits stuff` and not
`Fix/plan-limits-enforcement` (the branch-name default a forge would otherwise pick).

Match the repo's existing style if unsure: `git log -10 --pretty=%s`.

## 4. Open it

Write the body to a scratchpad file rather than fighting shell quoting, then open it from
the current branch into the base branch:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/forge.sh open "<imperative title>" <scratchpad>/pr-body.md   # prints "<n>\t<url>"
```

That assigns the PR to the configured reviewer and requests their review. A forge may refuse
a review request from the PR's own author (GitHub does), so when the configured reviewer
opened the PR the script reports "review request skipped … assigned instead" — that is
normal and not a problem to report; say so in one clause and move on. If a different
collaborator should review, ask who and run `forge.sh request-review <n> <login>`.

## 5. Screenshots (UI changes only)

When §1 found app UI changes and the project configures `pr.screenshots_guide`, add
screenshots of the pushed head to the body now that the PR exists. Two documents carry the
how-to: `screenshots.md` in this skill's directory (the generic mechanics — choosing shots,
cropping with Playwright, uploading through GitHub, patching the body) and the project's own
guide (which paths count as UI, and how to boot and seed the pushed commit). Read both before
the first shot. In outline:

1. Confirm the tree is clean and `HEAD` equals `origin/<branch>`. Then boot that commit as the
   project guide describes, and seed it.
2. Capture a few tight crops with Playwright: the changed element plus a little context, at a
   1280px viewport. Aim for four or fewer. Describe wording-only variants in text rather than
   shooting them.
3. Upload them through the PR's comment box in the browser. Never submit the comment.
4. Patch the body to add a `## Screenshots` section after "What changed".

If the browser profile isn't signed in to GitHub, the PR is still open and the rest of this
skill still runs. Report the screenshots as pending the user's sign-in, and finish them once
they have signed in.

**Every later push that changes pictured UI replaces the whole section** with a fresh set from
the new head (`screenshots.md` §7). That applies whoever pushes: a fix round, a review
response, or a rebase.

## 6. Update the ticket

Per the `issue-update` skill: move the card to **In review**, leave a comment with the PR
link and what remains (e.g. the rollout milestone and whose it is), and fill in the ticket
body's `**PR:**` bullet — replace its `_none yet_` placeholder with `forge.sh link <pr>`, and
bring the `**State:**` line up to date in the same edit. Implementation PRs only — a plan PR
leaves the card in `draft` (§1):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/tracker.sh set-status <id> in_review
${CLAUDE_PLUGIN_ROOT}/scripts/tracker.sh comment <id> "In review on $(${CLAUDE_PLUGIN_ROOT}/scripts/forge.sh link <pr>) (branch \`<branch>\`). <what remains>"
${CLAUDE_PLUGIN_ROOT}/scripts/tracker.sh get-body <id> > <scratchpad>/issue-body.md
# set the **PR:** bullet and **State:** line in that file, then:
${CLAUDE_PLUGIN_ROOT}/scripts/tracker.sh set-body <id> <scratchpad>/issue-body.md
```

On an older ticket with no `**PR:**` bullet, add one under `**Branch:**`.

If the branch has no ticket (untracked one-off work), skip this — don't invent one for a
trivial change.

## 7. Report back

Give the user the PR URL, the title, the ticket moved (or that none exists), and whether
the body has screenshots (how many, or why none: no UI change, no screenshots guide
configured, or pending a GitHub sign-in). Add a one-line note on what still needs a human
(assignee set, review-request skipped as self-review, tests pending, flag still off).
