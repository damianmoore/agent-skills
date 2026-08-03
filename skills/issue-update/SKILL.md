---
name: issue-update
description: Move a ticket's card across the project's configured GitHub Projects board (per .agent/project.yml) and keep the issue itself current — comment on transitions, link branch/PR, close on completion. Use whenever work state changes; issue-implement, issue-pr, and the project's deploy skill route their status updates through this skill.
---

# Update a ticket

The project board configured in `.agent/project.yml` (Projects v2) is the single source of
truth for work status. Whenever the real state of a piece of work changes, the change is
recorded here — on the ticket and its card — not in repo files. Column names, labels, and
branch conventions are defined in the `issue-create` skill.

## Project config

Repo-specific values live in `.agent/project.yml` in the repo you are working in. Read the
one key this skill needs **once**, at the start of the run, and substitute it wherever the
commands below show `<repo>`:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/issue-update/project-config.sh github.repo   # <repo> — owner/name
```

The helper exits non-zero and names the missing file or key; tell the user to add it to
`.agent/project.yml` (the plugin README documents the schema) rather than guessing. The
board owner and title are read by `board.sh` and `bootstrap-board.sh` themselves, so those
scripts take no config arguments.

## Finding the ticket

The plan doc's `**Status:**` line carries `**Ticket:** #NN`. Failing that:
`gh issue list -R <repo> --state all --search "<topic>"`.
If no ticket exists for tracked work, create one first via the `issue-create` skill.

## Moving the card

`board.sh` in this skill's directory wraps the Projects API (it needs the gh `project`
scope — on a scope error, tell the user to run `gh auth refresh -s project,read:project`):

```bash
${CLAUDE_PLUGIN_ROOT}/skills/issue-update/board.sh status <issue#> "<Column>"
${CLAUDE_PLUGIN_ROOT}/skills/issue-update/board.sh show <issue#>
```

If the board doesn't exist yet, `${CLAUDE_PLUGIN_ROOT}/skills/issue-update/bootstrap-board.sh`
creates it (idempotent).

## Transitions

| Event | Column | Also do |
|-------|--------|---------|
| Plan authoring starts / still draft | Draft | ticket created via `issue-create` |
| Plan locked, ready to implement | Ready | plan's `**Status:**` line updated |
| Branch cut, implementation starts | In progress | comment: branch name, e.g. `Implementation started on \`fix/feed-fetch-reliability\`.` |
| PR opened | In review | comment: PR link + what remains (e.g. rollout milestone); PR body gains `Closes #NN` (issue-pr does this) |
| PR merged | Merged | **automatic** — merge closes the issue, board moves the card. Only comment: merge noted, rollout pending and whose it is |
| Deployed to prod / work complete | Released | comment: version shipped + outcome; archive the plan doc (see issue-implement §3). Issue is already closed — don't reopen it |
| Deliberately shelved | Parked | comment: why, and what would unpark it. Leave the issue **open** — closing it would bounce the card to Merged |
| Superseded by other work | Released | comment naming the successor ticket; `gh issue close <n> --reason "not planned"`, **then** set the column to Released — the close fires the Merged automation first |

Rules:

- **Always end PR bodies with `Closes #NN`.** The board's built-in *Item closed* workflow is
  what moves the card to Merged; without the closing keyword the card strands in In review.
  Merged still means "in `main`, rollout pending" — the issue being closed is a board
  mechanism, not a claim that the work shipped.
- **The Merged move is automatic; the comment is not.** After a merge, check whether the
  transition comment exists and add it if not.
- **Closing any ticket on the board sends its card to Merged** — the built-in workflow has no
  condition and can't be given one. Whenever you close an issue for a reason *other* than a
  merge, set the column explicitly afterwards.
- **Milestone-by-milestone detail stays in the plan's Progress log**, not the ticket. The
  ticket gets one comment per *transition*, written for someone reading the board — what
  changed, where it stands, the next action.
- Keep the issue body's `**State:**` line current when commenting a transition — it's the
  first thing a board reader sees.
- One event can imply two moves (e.g. a same-day merge + deploy) — land the card on the
  final column but still leave both facts in the comment.
