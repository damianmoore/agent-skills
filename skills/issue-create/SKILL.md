---
name: issue-create
description: Create a GitHub issue for a piece of work and put its card on the project's configured GitHub Projects board (per .agent/project.yml), with the house title, label, and branch-name conventions. Use when asked to create/file a ticket or issue for work; issue-plan calls this when a plan is authored.
---

# Create a ticket

Every unit of tracked work is one GitHub issue on the configured repo plus a card on that
project's board (Projects v2). **The board is the single source of truth for status** —
there are no status tables in the repo. Plan documents under `docs/plans/` carry the design
and milestone detail; the ticket carries the state.

## Project config

Everything repo-specific lives in `.agent/project.yml` in the repo you are working in. Read
the keys this skill needs **once**, at the start of the run, and substitute the values into
the commands below wherever they show `<repo>`:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/issue-update/project-config.sh github.repo   # <repo> — owner/name
```

The helper exits non-zero and names the missing file or key. When that happens, tell the
user to add it to `.agent/project.yml` (the plugin README documents the schema) — never
guess a repo or board name. `board.sh` and `bootstrap-board.sh` read the config themselves,
so they take no config arguments.

## Conventions (shared by issue-plan, issue-update, issue-implement, issue-pr)

- **Title** — the topic, short and concrete: `Feed fetch reliability`, not "fix the feeds".
  When a plan doc exists, use the same topic wording as its filename.
- **One type label, matching the branch prefix.** Exactly one of `feat` / `fix` / `chore` /
  `refactor` — the same word the work's branch will start with
  (label `fix` ↔ branch `fix/feed-fetch-reliability`). Pick by the nature of the work:
  `feat` new capability, `fix` bug fix, `chore` tooling/docs/ops, `refactor`
  behaviour-preserving restructure.
- **Branch name** — `<prefix>/<kebab-topic>`, where `<kebab-topic>` is the plan filename
  minus `-plan` (e.g. `docs/plans/rest-api-plan.md` → `feat/rest-api`).
- **Board columns** (in flow order):

  | Column | Meaning |
  |--------|---------|
  | Draft | Plan being written or under review |
  | Ready | Plan locked; implementation not started |
  | In progress | Branch cut, milestones underway |
  | In review | Code milestones done, PR open |
  | Merged | In `main`; production rollout pending (issue closed at merge) |
  | Released | Deployed to prod / complete |
  | Parked | Deliberately not scheduled |

## Steps

1. **Create the issue.** Write the body to a scratchpad file, then:

   ```bash
   gh issue create -R <repo> \
     --title "<topic>" --label "<type>" --body-file <scratchpad>/issue-body.md
   ```

   Body shape (short — the plan doc holds the detail):

   ```markdown
   <One or two sentences: the problem or capability, with the concrete symptom/value.>

   - **Plan:** `docs/plans/<file>.md`   (omit if none yet)
   - **Branch:** `<prefix>/<kebab-topic>`

   **State:** <where things stand and the next action a fresh session can take>
   ```

2. **Put the card on the board** and set its column (usually `Ready` for a locked plan,
   `Draft` for one still forming):

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/skills/issue-update/board.sh status <issue#> "Ready"
   ```

   If this fails with a scope error, the token needs `gh auth refresh -s project,read:project`
   — tell the user, and note the pending board step in your report; the issue itself is
   already created. If the board doesn't exist yet, run
   `${CLAUDE_PLUGIN_ROOT}/skills/issue-update/bootstrap-board.sh` first.

3. **Cross-reference the plan.** If a plan doc exists, its `**Status:**` header line gains a
   ticket link: `**Status:** Ready to implement · **Ticket:** [#NN](https://github.com/<repo>/issues/NN) · **Date:** …`.

4. **Sweep `docs/todo.md`, if the repo keeps one.** Delete any lines the new ticket covers —
   per the note at the top of that file, `todo.md` holds only unplanned work, and the item is
   now tracked on the board (in any column). `issue-plan` and `issue-implement` repeat this
   sweep, but don't rely on them: a ticket filed directly (e.g. a bug) may never pass through
   those skills. Skip the step in repos with no such file.

5. Report the issue number and URL, noting any `todo.md` lines removed. All later state changes go through the `issue-update`
   skill — never edit status prose into repo files.
