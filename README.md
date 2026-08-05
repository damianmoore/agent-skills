# agent-skills

A Claude Code plugin holding one opinionated workflow: **every unit of tracked work is a
GitHub issue with a card on a GitHub Projects v2 board, and that board is the single source
of truth for status.** No status tables in the repo, no stale `README` checklists — plan
documents under `docs/plans/` carry the design and milestone detail, the ticket carries the
state.

Six skills cover the lifecycle:

| Skill | What it does |
|-------|--------------|
| `issue-plan` | Writes `docs/plans/<topic>-plan.md` in a fixed house format — a verified current-state section, locked decisions, and checkbox milestones sized for one subagent each — then files the ticket via `issue-create`. Its review gate runs interactively at a terminal or as an async **plan PR** (below). |
| `issue-create` | Creates the GitHub issue with the house title/label/branch conventions and puts its card on the board. |
| `issue-implement` | Runs a plan end to end: §0 questions, branch off `main`, per-milestone implement + separate adversarial verify subagent, configured lint/test commands, commit and push per milestone, PR at completion. |
| `issue-pr` | Opens a reviewer-focused PR, assigns it to the configured reviewer, and moves the card to In review. |
| `issue-update` | Moves cards and keeps the issue current. Every other skill routes its status changes through this one. Ships `board.sh`, `bootstrap-board.sh`, and `project-config.sh`. |
| `browser-handoff` | Hands the shared browser to a human when a page needs a login, 2FA or SSO the agent must not invent — page them, wait for the hand-back, then persist the login so the next session skips the wall. Referenced by `issue-implement` during verification. |

## The board

`bootstrap-board.sh` creates a Projects v2 board whose Status field is the work lifecycle:

| Column | Meaning |
|--------|---------|
| Draft | Plan being written or under review |
| Ready | Plan locked; implementation not started |
| In progress | Branch cut, milestones underway |
| In review | Code milestones done, PR open |
| Merged | In `main`; production rollout pending (issue closed at merge) |
| Released | Deployed to prod / complete |
| Parked | Deliberately not scheduled |

Merging a PR whose body ends `Closes #NN` closes the issue, and the board's built-in *Item
closed* workflow moves the card to Merged — which is why the closing keyword is load-bearing
and why Released is a separate manual move on an already-closed issue.

Requirements: `gh` (authenticated, with the `project` scope — `gh auth refresh -s
project,read:project`), `jq`, and `bash`.

## Reviewing a plan: interactive, or as a plan PR

Every plan passes a human gate before implementation starts, and `issue-plan` runs it one of
two ways. At a terminal it asks its open questions interactively and the card lands in `Ready`
as soon as the plan is locked. Headless — in a session pod, under `claude -p`, or whenever
async review is asked for — it instead ships the plan as a **plan PR**: the open questions
become §0 entries with proposed defaults, the plan doc is committed to a `plan/<kebab-topic>`
branch, and a PR labelled `plan` carries a summary plus those questions as task-list
checkboxes. The whole gate then works from the GitHub mobile app — read the diff, tick a box
to accept its default or reply in a comment, approve.

The card sits in `Draft` while that PR is open. Approving it turns every ticked default into a
locked §2 decision, merges the plan, deletes the branch and moves the card to `Ready`;
implementation proceeds unchanged from there. A plan PR body ends `Part of #NN`, **never**
`Closes #NN` — it must not close the ticket, or the *Item closed* workflow would send the card
to Merged before any of the work existed.

## Install

In Claude Code:

```
/plugin marketplace add damianmoore/agent-skills
/plugin install agent-skills@damianmoore
```

Or from the CLI:

```bash
claude plugin marketplace add damianmoore/agent-skills
claude plugin install agent-skills@damianmoore --scope user
```

The repo is its own marketplace, so the marketplace name and the plugin name are both
`agent-skills`.

## Per-repo configuration: `.agent/project.yml`

The skills carry no project-specific values. Each repo that uses them commits a
`.agent/project.yml` at its root:

```yaml
# Configuration for the agent-skills pipeline (https://github.com/damianmoore/agent-skills)
github:
  owner: damianmoore                # Projects v2 board owner
  repo: damianmoore/audio-audit     # owner/name
  project_title: "Audio Audit"      # Projects v2 board title
  assignee: damianmoore             # human reviewer for PRs
conventions:
  test_command: make test           # optional
  lint_command: "ruff check --fix . && ruff format ."   # optional
  test_notes: "known pre-existing failure: test_speech_recognition"  # optional free text
deploy:
  skill: deploy-production          # optional project-specific skill name
```

| Key | Required | Used by | Meaning |
|-----|----------|---------|---------|
| `github.owner` | yes | `board.sh`, `bootstrap-board.sh` | Login owning the Projects v2 board (user or org) |
| `github.repo` | yes | all five `issue-*` skills | `owner/name` of the repo the issues live in |
| `github.project_title` | yes | `board.sh`, `bootstrap-board.sh` | Board title; `bootstrap-board.sh` creates it if absent |
| `github.assignee` | yes | `issue-pr` | Login that PRs are assigned to for human review |
| `conventions.test_command` | no | `issue-implement` | Run after each milestone; omitted means "this repo has none" |
| `conventions.lint_command` | no | `issue-implement` | Run as configured after each milestone; the command defines its own scope |
| `conventions.test_notes` | no | `issue-implement` | Free text quoted alongside test results, e.g. a known pre-existing failure |
| `deploy.skill` | no | `issue-plan`, `issue-implement` | Name of the repo's own release skill, used by the rollout milestone |

A commented example lives in [`examples/project.yml`](examples/project.yml).

### Reading it

`skills/issue-update/project-config.sh` is the only reader, and it is also usable directly:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/issue-update/project-config.sh github.repo
${CLAUDE_PLUGIN_ROOT}/skills/issue-update/project-config.sh conventions.test_command ""
```

One dotted `section.key` per call. With no second argument a missing key is an error; the
second argument is a default for optional keys. A missing `.agent/project.yml` is always an
error. It parses a deliberately tiny YAML subset (two levels, scalar values, `#` comments) in
`awk`, so the dependency list stays `bash` + `jq` + `gh`.

## Onboarding a repo

1. Install the plugin (once per machine, above).
2. Commit `.agent/project.yml` in the repo root — copy `examples/project.yml` and fill it in.
3. Create the board and the labels. `bootstrap-board.sh` reads `.agent/project.yml` from the
   current git repo, so run it **with your working directory inside the repo being
   onboarded**, invoking the script out of a clone of this one:

   ```bash
   git clone https://github.com/damianmoore/agent-skills ~/src/agent-skills   # once per machine
   cd /path/to/the/repo/being/onboarded
   ~/src/agent-skills/skills/issue-update/bootstrap-board.sh
   ```

   The script path may be absolute or relative to the clone (`./skills/issue-update/bootstrap-board.sh`
   if you are sitting in the clone and the target repo is the current git repo) — only the
   working directory matters. Inside Claude Code you never type this: the skills invoke the
   script for you as `${CLAUDE_PLUGIN_ROOT}/skills/issue-update/bootstrap-board.sh`, a
   variable the plugin runtime sets and an ordinary shell does not.

   Idempotent: it creates the project if it does not exist, sets the seven lifecycle columns,
   links the board to the repo, creates the five issue labels, and switches the default view
   to a board layout. Re-running it is safe.

   The labels matter — `gh issue create --label feat` hard-fails on a repo that has no `feat`
   label, so `issue-create` cannot file a ticket until they exist:

   | Label | Meaning |
   |-------|---------|
   | `feat` | New capability — branch prefix `feat/…` |
   | `fix` | Bug fix — branch prefix `fix/…` |
   | `chore` | Tooling, docs, ops — branch prefix `chore/…` |
   | `refactor` | Behaviour-preserving restructure — branch prefix `refactor/…` |
   | `plan` | Has a plan doc under `docs/plans/` — also the prefix of the short-lived plan-review branch `plan/…` (`issue-plan` §7); not a type |

   Every ticket carries exactly one of the four type labels, matching its branch prefix;
   `plan` is added alongside it when the work has a plan document. `plan/` is the one branch
   prefix that is not a type: it names the branch a plan doc is reviewed on, and the same work
   is implemented later on its `feat/` / `fix/` / `chore/` / `refactor/` branch.

That is the whole setup. From then on `issue-plan` / `issue-create` / `issue-implement` /
`issue-pr` / `issue-update` work against that repo's board.

## Project-specific skills stay in the repo

Anything that only makes sense for one codebase — a production deploy that bumps a Helm chart
and pushes an image, for instance — stays in that repo's own `.claude/skills/` and is named in
`deploy.skill`. `issue-plan`'s rollout milestone and `issue-implement`'s Released transition
both point at whatever `deploy.skill` names, and simply describe the release steps explicitly
when a repo sets no value.

## Versioning

`version` in `.claude-plugin/plugin.json` is the source of truth. Releases are git tags of the
form `agent-skills--v<version>`, created with:

```bash
claude plugin tag ~/projects/agent-skills
```

which validates that `plugin.json` and the marketplace entry agree before tagging. Bump the
version in `plugin.json`, commit, then tag.

## Validating changes

Run **both** forms — they check different things:

```bash
claude plugin validate .                            # marketplace manifest only
claude plugin validate .claude-plugin/plugin.json   # plugin manifest + skill frontmatter
```

The directory form does *not* parse skill frontmatter. A stray `: ` inside an unquoted
YAML scalar (e.g. a `description:` containing `foo: bar`) silently drops **all** of that
skill's frontmatter at runtime — the second form is what catches it.
