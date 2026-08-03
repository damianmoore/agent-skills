---
name: issue-implement
description: Implement a docs/plans/*-plan.md in the house protocol — ask §0 questions, branch off main, per-milestone Opus implement + separate Opus adversarial verify, commit and push each milestone, PR via issue-pr at completion — while keeping the plan's Progress log and the ticket's card on the project's configured GitHub Projects board (per .agent/project.yml, via issue-update) current. Use when asked to implement, start, resume, or continue a plan.
---

# Implement a plan

Runs a plan from `docs/plans/` end to end. This skill is the **single home of the
implementation protocol**: plans reference it instead of embedding the steps, and if an
older plan still carries its own protocol block in §5, **this skill supersedes that block**
(the plan's milestones, designs, and decisions still rule — only the process text yields).

## Project config

Everything repo-specific lives in `.agent/project.yml` in the repo you are working in. Read
these **once**, at the start of the run, and substitute the values wherever the commands
below show `<repo>`:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/issue-update/project-config.sh github.repo                # <repo> — owner/name
${CLAUDE_PLUGIN_ROOT}/skills/issue-update/project-config.sh conventions.lint_command ""
${CLAUDE_PLUGIN_ROOT}/skills/issue-update/project-config.sh conventions.test_command ""
${CLAUDE_PLUGIN_ROOT}/skills/issue-update/project-config.sh conventions.test_notes ""
${CLAUDE_PLUGIN_ROOT}/skills/issue-update/project-config.sh deploy.skill ""
```

The trailing `""` is a default — those keys are optional and an empty result means "the
project doesn't define one". Keys read without a default (`github.repo`) exit non-zero when
missing: tell the user to add them to `.agent/project.yml` (the plugin README has the schema)
rather than guessing. `board.sh` and `bootstrap-board.sh` read the config themselves, so they
take no config arguments.

## 0. Pick the plan and read it

- If the user named a plan, use it. Otherwise list the candidates from the board —
  `gh issue list -R <repo> --state open --search '"docs/plans/" in:body'`
  (plan-backed issues link their plan doc in the body; Ready column, plus
  In progress for resumes; `${CLAUDE_PLUGIN_ROOT}/skills/issue-update/board.sh show <n>`
  gives a card's column) — and ask which one via `AskUserQuestion`.
- Read the **whole plan file** (linked from the issue body) before doing anything. The
  Progress log tells you where a resumed plan actually is — trust it over the checkboxes
  if they disagree, and say so.
- If the plan has a **§0 Open questions** section with unticked items, put every one to the
  user with `AskUserQuestion` **before writing any code**, record each answer as a new row in
  §2 Decisions, and tick the §0 box.

## 1. Branch

```
git fetch origin
git switch -c <branch-name> --no-track origin/main
git push -u origin <branch-name>
```

`--no-track` is load-bearing: on a machine with `push.default=upstream`, a branch cut
tracking `origin/main` pushes **straight to remote `main`** (this really happened —
2026-07-30, a milestone commit landed on `origin/main` because the branch was cut without
`--no-track`). Publish the branch immediately and check the push output reads
`-> <branch-name>`, not `-> main`.

One branch for the whole plan; never work on `main`. Use the branch name the plan specifies.
If it doesn't specify one, derive it from the plan filename as `<prefix>/<kebab-topic>` with
one of the standard prefixes: `feat/` (new capability), `fix/` (bug fix), `chore/` (tooling,
docs, ops), `refactor/` (behaviour-preserving restructure) — e.g. `fix/feed-fetch-reliability`.
If the plan specifies a name without a prefix, add the appropriate one and update the plan's
§5 pointer block to match.

Then record the start via the `issue-update` skill: move the ticket's card to
**In progress** and comment the branch name. Update the plan file's own `**Status:**` line
to match (it should already carry the `**Ticket:** #NN` link; if the plan predates the
board and has no ticket, create one now with the `issue-create` skill).

If the repo keeps a `docs/todo.md`, sweep it and delete any lines this plan covers. Per the
note at the top of that file it holds only unplanned work — the ticket is the single tracker
now. (`issue-plan` normally removes them at authoring; this catches plans authored before
that rule and items added since.)

## 2. The milestone loop

Work milestones **in order** — each is independently committable and leaves the app
releasable; never a state where `main` could not ship.

For each milestone:

1. **Implement with an Opus subagent.** Give it the milestone text, the §4 subsections it
   cites, and the repo conventions. The orchestrating agent stays the orchestrator —
   reasoning effort is inherited, so run the session at high effort.
2. **Verify with a different Opus subagent.** It gets the milestone's `Verify` / `Done when`
   lines and the diff, and is instructed to hunt adversarially for the ways the work is
   wrong — off-by-ones in limit checks, inverted fail-open branches, swallowed errors,
   migration collisions — and to report defects, not fix or rubber-stamp. It also checks that
   **the previous milestone actually reached the remote**: `git log --oneline origin/<branch>..HEAD`
   must be empty except for commits belonging to the milestone under review (at verify time
   the current milestone is often not committed yet, so an empty range is normal). Any commit
   from an **earlier** milestone still sitting unpushed in that range is a defect to report,
   not a detail to overlook. Fix findings; re-verify until clean.

   ```
   Agent(model: "opus", prompt: "<milestone text + §4 design + repo conventions>")
   Agent(model: "opus", prompt: "Verify M<n> ... adversarially; report defects, do not fix; confirm earlier milestones are pushed")
   ```
3. **Run the project's configured checks.** Run `conventions.lint_command` exactly as
   configured — it is the repo's own command and defines its own scope — then
   `conventions.test_command`, and fix what they flag. Read the results with
   `conventions.test_notes` quoted alongside them — it records things like a known
   pre-existing failure, so a red run is not automatically this milestone's fault. If a key
   is absent from `.agent/project.yml`, say so in the milestone report ("no lint command
   configured") and move on; don't invent one.
4. **Commit via the `git-commit` skill, then `git push` — both before starting the next
   milestone.** A milestone that is committed but not pushed is an unfinished milestone:
   sessions run in ephemeral pods, and a pod that disappears takes every unpushed commit with
   it, so the remote branch is the only durable record of the work. Push, read the push
   output, and confirm it names your branch. Only then start the next milestone. Tick the
   milestone's boxes and append a Progress log line (date, milestone, one-line summary,
   commit hash) in the same commit or the next.

**When reality differs from the design, amend the plan in place.** The deviation and its
reason go into the Progress log entry, naming what was built instead and why. Never silently
implement something else.

## 3. Review and rollout

- **When the code milestones are complete** (or the work reaches the deployment milestone):
  open the PR with the `issue-pr` skill — it links the PR to the ticket and moves the card to
  **In review** (per the `issue-update` skill). Rollout milestones that need prod access
  stay unticked and are called out in the PR body. Update the plan's `**Status:**` line.
- **The production rollout milestone is normally the founder's**, not the agent's — leave it
  to them unless told otherwise. Merging the PR closes the issue and the board moves the card
  to **Merged** automatically; whoever runs the rollout (usually via the project's configured
  release skill — `deploy.skill` in `.agent/project.yml`, when one is set) moves it to
  **Released** and makes the plan's final Progress log entry. The issue is already closed by
  then — Released is a column move, not a close.
- **On Released (deployed, complete, or superseded): archive the plan.** `git mv` the file to
  `docs/plans/archive/`, and update any repo references to the old path —
  `grep -rn "<filename>"` across the repo; code comments, migrations, and other docs
  routinely point at plan files. The closed ticket keeps the outcome summary.

## 4. Session end

Every session, regardless of how far the work got: make sure everything is pushed, and that
the ticket reflects where things truly stand — card in the right column, and the issue body's
`**State:**` line (or a fresh comment, per the `issue-update` skill) naming the next action so
the next session can start without archaeology.
