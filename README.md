# agent-skills

A Claude Code plugin holding one opinionated workflow: **every unit of tracked work is a
ticket with a card on a board, and that board is the single source of truth for status.**
Out of the box the ticket is a GitHub issue, the board is a GitHub Projects v2 board and the
review request is a pull request; the tracker and forge sit behind adapters, so other
backends can be added (see *Architecture*). No status tables in the repo, no stale `README` checklists — plan
documents under `docs/plans/` carry the design and milestone detail, the ticket carries the
state.

Five skills cover the lifecycle. Four of them run in sequence:

| Skill | What it does |
|-------|--------------|
| `issue-create` | Creates the ticket with the house title/label/branch conventions and puts its card on the board. |
| `issue-plan` | Writes `docs/plans/<topic>.md` in a fixed house format — a verified current-state section, locked decisions, and checkbox milestones sized for one subagent each — attached to the work's ticket, reusing an existing one where there is one and filing a new one via `issue-create` where there isn't. Its review gate runs interactively at a terminal or as an async **plan PR** (below). |
| `issue-implement` | Runs a plan end to end: §0 questions, branch off `main`, per-milestone implement subagent (Sonnet by default) + parallel session-model verify lenses while the configured test gate runs in the background, commit and push per milestone, PR at completion. |
| `issue-pr` | Opens a reviewer-focused PR, assigns it to the configured reviewer, fills in the ticket's PR link, moves the card to In review, and — when the repo configures a screenshots guide — adds screenshots of UI changes to the PR body. |

The fifth runs throughout rather than at one point in that sequence:

| Skill | What it does |
|-------|--------------|
| `issue-update` | Moves cards and keeps the ticket current. Every other skill routes its status changes through this one. |

## The board

The board's columns are the work lifecycle. Skills move cards by **lifecycle key**; each key
maps to a column name, by default:

| Key | Default column | Meaning |
|-----|----------------|---------|
| `draft` | Draft | Plan being written or under review |
| `ready` | Ready | Plan locked; implementation not started |
| `in_progress` | In progress | Branch cut, milestones underway |
| `in_review` | In review | Code milestones done, review request open |
| `merged` | Merged | In `main`; production rollout pending (ticket closed at merge) |
| `released` | Released | Deployed to prod / complete |
| `parked` | Parked | Deliberately not scheduled |

The `statuses:` config section renames any of them to match an existing board, and two keys
may share one column (`merged` and `released` both "Done"); moving between keys that share a
column is then a no-op, and the transition comment is the only record of it.

On GitHub, merging a PR whose body ends `Closes #NN` closes the issue, and the board's
built-in *Item closed* workflow moves the card to Merged — which is why the closing
reference is load-bearing and why Released is a separate manual move on an already-closed
issue. The adapter reports these facts (`tracker.sh capabilities`) so the skills can adapt to
a tracker that behaves differently.

Requirements for the GitHub adapters: `gh` (authenticated, with the `project` scope — `gh
auth refresh -s project,read:project`), `jq`, and `bash` 4+.

## Reviewing a plan: interactive, or as a plan PR

Every plan passes a human gate before implementation starts, and `issue-plan` runs it one of
two ways. At a terminal it asks its open questions interactively, commits the plan to `main`
(through a temporary worktree, so the branch you are on is left alone), and the card lands in
`Ready` as soon as the plan is locked. Headless — in a session pod, under `claude -p`, or whenever
async review is asked for — it instead ships the plan as a **plan PR**: the open questions
become §0 entries with proposed defaults, the plan doc is committed to a `plan/<kebab-topic>`
branch, and a PR labelled `plan` carries a summary plus those questions as task-list
checkboxes. The whole gate then works from the GitHub mobile app — read the diff, tick a box
to accept its default or reply in a comment, approve.

The card sits in `Draft` while that PR is open. Approving it turns every ticked default into a
locked §2 decision, merges the plan, deletes the branch and moves the card to `Ready`;
implementation proceeds unchanged from there. A plan PR body ends with the ticket's mention
reference (`Part of #NN`), **never** its closing reference — it must not close the ticket, or
the *Item closed* workflow would send the card to Merged before any of the work existed.

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
tracker:
  type: github                      # adapter for tickets and the board
  repo: damianmoore/audio-audit     # where the issues live
  board_owner: damianmoore          # Projects v2 board owner (user or org)
  board_title: "Audio Audit"
forge:
  type: github                      # adapter for review requests
  repo: damianmoore/audio-audit
  reviewer: damianmoore             # human reviewer PRs are assigned to
statuses:                           # optional — only where the board's columns differ
  in_review: "Code Review"
conventions:
  lint_command: "ruff check --fix <files> && ruff format <files>"   # optional
  iterate_command: "make test <path>"   # optional
  test_command: make test-gate      # optional
  test_notes: "known pre-existing failure: test_speech_recognition"  # optional free text
agents:
  implement_model: sonnet           # optional
plans:
  examples: "docs/plans/archive/a-feature.md docs/plans/archive/a-fix.md"   # optional
pr:
  screenshots_guide: docs/agents/pr-screenshots.md   # optional
  api_snapshots: "docs/api/openapi-v1.json"          # optional
deploy:
  skill: deploy-production          # optional project-specific skill name
```

| Key | Required | Used by | Meaning |
|-----|----------|---------|---------|
| `tracker.type` | no | `tracker.sh` | Tracker adapter (default `github`) |
| `tracker.repo` | yes (github) | GitHub tracker | `owner/name` of the repo the issues live in |
| `tracker.board_owner` | no | GitHub tracker | Login owning the Projects v2 board (default: the repo's owner) |
| `tracker.board_title` | yes (github) | GitHub tracker | Board title; `tracker.sh bootstrap` creates it if absent |
| `forge.type` | no | `forge.sh` | Forge adapter (default `github`) — separate from the tracker, since Jira tickets with GitHub code is common |
| `forge.repo` | yes (github) | GitHub forge | `owner/name` of the code repo |
| `forge.reviewer` | no | GitHub forge | Login that PRs are assigned to and asked to review |
| `forge.base_branch` | no | GitHub forge | Branch review requests target (default `main`) |
| `statuses.<key>` | no | all skills | Board column for a lifecycle key (`draft` … `parked`); unset keys use the default names |
| `conventions.lint_command` | no | `issue-implement` | Run first on each milestone handoff; `<files>` in it is filled with the touched files, otherwise the command defines its own scope |
| `conventions.iterate_command` | no | `issue-plan`, `issue-implement` | Fast, targeted tests for implement agents and fix rounds; `<path>` is filled with the file or directory under test. Omitted means the test command is scoped as narrowly as its runner allows |
| `conventions.test_command` | no | `issue-plan`, `issue-implement` | The milestone-close gate, run in the background alongside the verify lenses; the authority on green. Omitted means "this repo has none" |
| `conventions.test_notes` | no | `issue-implement` | Free text quoted alongside test results — a known pre-existing failure, whether exit codes can be trusted, how to keep fix rounds off the gate's database |
| `agents.implement_model` | no | `issue-plan`, `issue-implement` | Model for implement subagents (default `sonnet`); `session` inherits the session model. Verify agents always inherit it; a plan can escalate one milestone with a `**Model:** session` line |
| `plans.examples` | no | `issue-plan` | Space-separated reference plans read in full before writing a new one |
| `pr.screenshots_guide` | no | `issue-pr`, `issue-implement` | Repo doc saying which paths are UI and how to boot, seed and tear down the pushed commit; omitted means no PR screenshots |
| `pr.api_snapshots` | no | `issue-pr` | Space-separated committed API spec snapshots whose changes need a breaking/non-breaking classification in the PR |
| `deploy.skill` | no | `issue-plan`, `issue-implement`, `issue-update` | Name of the repo's own release skill, used by the rollout milestone and the Released move |

**Legacy `github:` section.** Configs written for 0.2 keep working: `github.repo` stands in for
`tracker.repo` and `forge.repo`, `github.owner` for `tracker.board_owner`,
`github.project_title` for `tracker.board_title`, and `github.assignee` for `forge.reviewer`.
New keys win where both are set.

A commented example lives in [`examples/project.yml`](examples/project.yml).

### Reading it

`scripts/project-config.sh` is the only reader, and it is also usable directly:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/project-config.sh tracker.repo
${CLAUDE_PLUGIN_ROOT}/scripts/project-config.sh conventions.test_command ""
```

One dotted `section.key` per call. With no second argument a missing key is an error; the
second argument is a default for optional keys. A missing `.agent/project.yml` is always an
error. It parses a deliberately tiny YAML subset (two levels, scalar values, `#` comments) in
`awk`, so the dependency list stays `bash` + `jq` + `gh`.

## Onboarding a repo

1. Install the plugin (once per machine, above).
2. Commit `.agent/project.yml` in the repo root — copy `examples/project.yml` and fill it in.
3. Create the board and the labels. `tracker.sh bootstrap` reads `.agent/project.yml` from the
   current git repo, so run it **with your working directory inside the repo being
   onboarded**, invoking the script out of a clone of this one:

   ```bash
   git clone https://github.com/damianmoore/agent-skills ~/src/agent-skills   # once per machine
   cd /path/to/the/repo/being/onboarded
   ~/src/agent-skills/scripts/tracker.sh bootstrap
   ```

   The script path may be absolute or relative to the clone — only the working directory
   matters. Inside Claude Code you never type this: the skills invoke the script for you as
   `${CLAUDE_PLUGIN_ROOT}/scripts/tracker.sh`, a variable the plugin runtime sets and an
   ordinary shell does not.

   Idempotent (GitHub): it creates the project if it does not exist, links it to the repo,
   creates the five labels, sets the lifecycle columns from the status map, and switches the
   default view to a board layout. It rewrites the columns only on a fresh board still showing
   GitHub's default Todo / In Progress / Done — on a live board it lists any missing columns
   for you to add in the UI instead, since rewriting the options would clear every card's
   column. Re-running it is safe.

   One step is UI-only: turn on the board's built-in **Item closed** workflow and point it
   at Merged (board ⋯ > Workflows > Item closed > Edit > set Status to Merged > Save and turn
   on workflow). GitHub's API can read workflows but not configure them, so `bootstrap`
   checks it and prints `ACTION NEEDED` with the link until it is on. Without it, merging a
   PR closes the issue but leaves its card in In review.

   The labels matter — creating an issue with a `feat` label hard-fails on a repo that has no `feat`
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

That is the whole setup. From then on `issue-create` / `issue-plan` / `issue-implement` /
`issue-pr` / `issue-update` work against that repo's board.

## Project-specific skills stay in the repo

Anything that only makes sense for one codebase — a production deploy that bumps a Helm chart
and pushes an image, for instance — stays in that repo's own `.claude/skills/` and is named in
`deploy.skill`. `issue-plan`'s rollout milestone and `issue-implement`'s Released transition
both point at whatever `deploy.skill` names, and simply describe the release steps explicitly
when a repo sets no value.

## Architecture: skills, verbs, adapters

The skills never call `gh` (or any tracker's CLI) themselves. They speak two small
command-line interfaces, and each dispatches to an adapter chosen by the config:

```
scripts/
  tracker.sh      -> adapters/<tracker.type>/tracker.sh   tickets, labels, comments, the board
  forge.sh        -> adapters/<forge.type>/forge.sh       review requests, links to code
  lib.sh          config fallbacks, the lifecycle and the status map
  project-config.sh  the .agent/project.yml reader
  adapters/github/   the only adapters today
```

Run either script with no arguments for its verbs. The contract a new adapter implements:

| `tracker.sh` verb | Contract |
|-------------------|----------|
| `create <type> <title> <body-file> [label…]` | File a ticket with the type label (+ extras); print `<id>\t<url>` |
| `view <id>` | JSON `{id, title, state, state_reason, labels, body, url}` |
| `search [text] [--all]` | `<id>\t<title>\t<labels>\t<state>` per ticket; open only unless `--all` |
| `get-body <id>` / `set-body <id> <file>` | Read / replace the body |
| `comment <id> [text]` | Add a comment (stdin when text is omitted) |
| `add-label <id> <label>` / `close <id> <completed\|not-planned>` | |
| `url <id>` / `link <id>` | URL / markdown link |
| `closing-ref <id>` / `mention-ref <id>` | Text for a review-request body that closes the ticket on merge / only references it |
| `branch <type> <kebab-topic>` | Branch name for the work (Jira-style trackers put the key in it) |
| `capabilities` | `closes_on_merge=yes\|no`, `close_moves_to=<key or empty>`, `labels=yes\|no`, `ticket_noun=…` |
| `add <id>` / `status <id>` / `set-status <id> <key>` / `list <key>` | Board: add a card; print `<key>\t<column>`; move (accepting a key or a column name); list `<ref>\t<title>` |
| `bootstrap` | Create or check the board, columns and labels; where that is an admin job, report what is missing |

| `forge.sh` verb | Contract |
|-----------------|----------|
| `current-review [branch]` | `<n>\t<url>` of the open review request for the branch, or nothing |
| `open <title> <body-file> [--label L]… [--draft]` | Open one from the current branch into the base branch, assign and request the reviewer; print `<n>\t<url>` |
| `request-review <n> [login]` | Request a review; a self-authored request is reported, not failed |
| `get-body <n>` / `set-body <n> <file>` / `comment <n> [text]` | |
| `review-state <n>` | JSON `{approved, changes_requested, reviews}` from each reviewer's latest review |
| `feedback <n>` | JSON `{body, reviews, comments, inline}` — every place an answer can arrive |
| `merge <n> <subject> <body>` / `close <n> <comment>` | Squash-merge with exactly that message / close unmerged; both delete the branch |
| `url <n>` / `link <n>` / `file-url <path> [ref]` / `branch-url <branch>` | Links |
| `noun` | What the forge calls a review request (`PR`, `MR`) |

`statuses` (the key → column map) is answered by `tracker.sh` itself from the config, so every
adapter gets it for free, and `lib.sh`'s `resolve_status` turns a key or a column name into the
configured column.

**Adding a backend** means one new directory under `scripts/adapters/` implementing the verbs
above — no skill text changes, provided the new tracker's behaviour is expressed through
`capabilities` and the reference verbs rather than special-cased. Build the second adapter
against a real project: it is what will show whether this boundary is in the right place. Two
things to expect: a tracker whose boards are an admin job (Jira) can only check and report in
`bootstrap`, and reading or searching can reasonably lean on the tracker's MCP server while the
state-changing verbs stay in the script, where they are deterministic.

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
