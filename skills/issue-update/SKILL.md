---
name: issue-update
description: Move a ticket's card across the project's configured board (per .agent/project.yml — a GitHub Projects board by default) and keep the ticket itself current — comment on transitions, link branch/PR, close on completion. Use whenever work state changes; issue-implement, issue-pr, and the project's deploy skill route their status updates through this skill.
---

# Update a ticket

The project's board is the single source of truth for work status. Whenever the real state
of a piece of work changes, the change is recorded here — on the ticket and its card — not
in repo files. The lifecycle keys, labels, branch conventions, and the two scripts every
command below goes through (`tracker.sh`, `forge.sh`) are defined in the `issue-create`
skill's *Tools and config* and *Conventions* sections.

## Finding the ticket

The plan doc's `**Status:**` line carries `**Ticket:**`. Failing that:
`${CLAUDE_PLUGIN_ROOT}/scripts/tracker.sh search "<topic>" --all`.
If no ticket exists for tracked work, create one first via the `issue-create` skill.

## Moving the card

Cards move by lifecycle key (`draft`, `ready`, `in_progress`, `in_review`, `merged`,
`released`, `parked`); the tracker adapter maps each to the board's own column name:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/tracker.sh set-status <id> <key>
${CLAUDE_PLUGIN_ROOT}/scripts/tracker.sh status <id>     # "<key>\t<column>"
${CLAUDE_PLUGIN_ROOT}/scripts/tracker.sh list <key>      # cards in that column
```

On a scope or permission error, relay the fix the script names (GitHub: `gh auth refresh -s
project,read:project`); on a rate-limit error, do the ticket edits and comments now — they
use a separate budget — and the moves after the reset, from a background wait rather than by
polling. If the board doesn't exist yet, `${CLAUDE_PLUGIN_ROOT}/scripts/tracker.sh bootstrap`
creates it (idempotent; on trackers where boards are an admin job it reports what is missing
instead).

## Editing the ticket body

The body's Plan / Branch / PR bullets and its `**State:**` line (template in `issue-create`
step 1) are edited in place — read, edit the file, write back:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/tracker.sh get-body <id> > <scratchpad>/issue-body.md
# edit the file, then:
${CLAUDE_PLUGIN_ROOT}/scripts/tracker.sh set-body <id> <scratchpad>/issue-body.md
```

Read immediately before writing — another session may have edited it — and diff your file
against what you read: only your intended lines should differ. Replace a `_none yet_`
placeholder with its link as the value comes into existence. Tickets filed before the PR
bullet existed have no `- **PR:**` line (and planless ones no `- **Plan:**` line) — add the
missing bullet in its template position rather than leaving the set incomplete.

Comments: `tracker.sh comment <id> "<text>"`, or pipe a longer body in on stdin.

## How the tracker behaves on close

Two facts decide several rules below. Read them once per run:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/tracker.sh capabilities
```

- `closes_on_merge=yes` — merging a review request whose body carries the ticket's
  `tracker.sh closing-ref <id>` closes the ticket. `no` means you close it yourself after the
  merge.
- `close_moves_to=<key>` — the board moves *any* closed ticket's card to that stage, with no
  conditions (GitHub's built-in *Item closed* workflow sends it to `merged`). Empty means
  closing leaves the card where it is.

## Transitions

| Event | Stage | Also do |
|-------|-------|---------|
| Plan authoring starts / still draft | `draft` | ticket created via `issue-create` |
| Plan PR opened for async review (`issue-plan` §7) | `draft` | **no move** — the card is already there; comment: plan PR link and that its approval is the gate. That PR body ends with `tracker.sh mention-ref`, never the closing ref |
| Plan locked, ready to implement | `ready` | plan's `**Status:**` line updated. In async mode this transition *is* the plan PR being approved: merge it first, then move the card (the branch is deleted by the merge) |
| Plan rejected, not going ahead | `parked` (or `released` if superseded) | close the plan PR unmerged with the reason as its close comment, then follow the Parked / Superseded rows below |
| Branch cut, implementation starts | `in_progress` | comment: branch name, e.g. `Implementation started on \`fix/feed-fetch-reliability\`.` |
| Implementation PR opened | `in_review` | comment: PR link + what remains (e.g. rollout milestone); ticket body's `**PR:**` bullet filled in; PR body ends with the closing ref (issue-pr does all three). A plan PR never matches this row — it has its own row above, and leaves the card in `draft` |
| PR merged | `merged` | with `closes_on_merge=yes` and `close_moves_to=merged` this is **automatic** — merge closes the ticket, the board moves the card. Otherwise close the ticket and/or set `merged` yourself. Either way comment: merge noted, rollout pending and whose it is |
| Deployed to prod / work complete | `released` | comment: version shipped + outcome; archive the plan doc (see issue-implement §3). The ticket is already closed — don't reopen it |
| Deliberately shelved | `parked` | comment: why, and what would unpark it; `**State:**` line says the same. Leave the ticket **open** — where `close_moves_to` is set, closing it would bounce the card |
| Superseded by other work | `released` | comment naming the successor ticket (or saying there is none); `**State:**` line updated to match; `tracker.sh close <id> not-planned`, **then** set `released` — the close may have moved the card first |

Rules:

- **End implementation PR bodies with `tracker.sh closing-ref <id>`** (`Closes #42` on GitHub).
  Where the tracker closes on merge and moves closed cards, that is what gets the card to
  Merged; without it the card strands in In review. Merged still means "in `main`, rollout
  pending" — the ticket being closed is a board mechanism, not a claim that the work shipped.
- **The one exception is a plan PR** (`issue-plan` §7), which ends with `tracker.sh
  mention-ref <id>` (`Part of #42`). For the same reason: the close-moves-the-card rule has no
  conditions, so a closing ref there would send the card from Draft to Merged and close the
  ticket before the work existed. One ticket has at most two PRs — the plan PR references it,
  the implementation PR closes it.
- **The Merged move may be automatic; the comment is not.** After a merge, check whether the
  transition comment exists and add it if not.
- **Merged is a holding column, not a resting state.** The Released move has an owner only
  when the rollout is a deploy (the project's `deploy.skill` does it, when one is configured);
  work released some other way — content published by hand, a DNS flip, a vendor-side step —
  has no automatic trigger. Any session that verifies a Merged ticket's remaining work is
  complete runs the Released transition then and there (column move, comment, `**State:**`
  line, plan archived per `issue-implement` §3) — don't leave it for a future deploy to
  notice. `tracker.sh list merged` shows what is waiting.
- **Where `close_moves_to` is set, closing any ticket moves its card** — GitHub's built-in
  workflow has no condition and can't be given one. Whenever you close a ticket for a reason
  *other* than a merge, set the column explicitly afterwards.
- **Two stages may share a column** (`statuses:` maps `merged` and `released` to one "Done",
  say). Moving between them is a no-op on the board, so the transition comment is the only
  record — never skip it.
- **Milestone-by-milestone detail stays in the plan's Progress log**, not the ticket. The
  ticket gets one comment per *transition*, written for someone reading the board — what
  changed, where it stands, the next action.
- Keep the ticket body's `**State:**` line current when commenting a transition — it's the
  first thing a board reader sees.
- One event can imply two moves (e.g. a same-day merge + deploy) — land the card on the
  final stage but still leave both facts in the comment.
