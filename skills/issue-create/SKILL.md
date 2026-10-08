---
name: issue-create
description: Create a ticket for a piece of work in the project's configured tracker (a GitHub issue by default) and put its card on the board (per .agent/project.yml), with the house title, label, and branch-name conventions. Use when asked to create/file a ticket or issue for work; issue-plan calls this when a plan is authored.
---

# Create a ticket

Every unit of tracked work is one ticket in the project's tracker plus a card on its board.
**The board is the single source of truth for status** — there are no status tables in the
repo. Plan documents under `docs/plans/` carry the design and milestone detail; the ticket
carries the state.

## Tools and config (shared by issue-plan, issue-update, issue-implement, issue-pr)

The skills never call a tracker's or forge's CLI directly. Two scripts carry every such call,
each dispatching to an adapter chosen by `.agent/project.yml` (`tracker.type`,
`forge.type`; both default to `github` — a GitHub issue on a Projects v2 board, and a pull
request):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/tracker.sh <verb> …   # tickets, labels, comments, the board
${CLAUDE_PLUGIN_ROOT}/scripts/forge.sh <verb> …     # review requests, and links to code
```

Run either with no arguments for its verbs. They read the config themselves and take no
repo or board arguments; when a key is missing they exit non-zero and name it — tell the user
to add it to `.agent/project.yml` (the plugin README documents the schema), never guess a
repo or board name. For other repo-specific values, read them once at the start of a run:
`${CLAUDE_PLUGIN_ROOT}/scripts/project-config.sh <section.key> [default]`.

`<id>` below is the tracker's ticket id (`42` on GitHub). **Always build ticket references,
links and closing text with the scripts** (`tracker.sh link <id>`, `tracker.sh closing-ref
<id>`, `forge.sh link <n>`) rather than writing `#42` or a URL by hand: each tracker spells
them differently, and the closing text is load-bearing.

## Conventions

- **Title** — the topic, short and concrete: `Feed fetch reliability`, not "fix the feeds".
  When a plan doc exists, use the same topic wording as its filename.
- **Voice** — everything these skills write for a human (ticket bodies, transition comments,
  review-request descriptions, Progress log lines, subagent handoffs and reports) is plain
  English: short sentences, concrete nouns and file names, no process jargon. The reader is
  skimming a board or a PR between other work, and current models drift verbose and
  jargon-heavy unless the register is set once.
- **One type label, matching the branch prefix.** Exactly one of `feat` / `fix` / `chore` /
  `refactor` — the same word the work's branch will start with
  (label `fix` ↔ branch `fix/feed-fetch-reliability`). Pick by the nature of the work:
  `feat` new capability, `fix` bug fix, `chore` tooling/docs/ops, `refactor`
  behaviour-preserving restructure.
- **Branch name** — `tracker.sh branch <type> <kebab-topic>`, where `<kebab-topic>` is the
  plan filename minus `.md` (e.g. `docs/plans/rest-api.md` → `feat/rest-api` on GitHub; a
  tracker that links branches by ticket key puts the key in the name).
- **`plan/` is a fifth branch prefix, and a special case**: `plan/<kebab-topic>` is the
  short-lived branch carrying a plan document up for async review (`issue-plan` §7). It is
  **not** a type — the ticket still takes exactly one of the four type labels and the matching
  implementation branch, so `plan/feed-fetch-reliability` and `fix/feed-fetch-reliability` are
  the same work at two stages. It pairs with the `plan` label, which means "has a plan doc",
  never a work type.
- **Groups of tickets** — a feature too big for one plan is filed as **several tickets that
  share one group label**, so the board can filter to the whole set and a reader can see the
  order. The group label is the feature's `<kebab-topic>` (`episode-review`, never a type
  word), created once with `tracker.sh ensure-label <kebab-topic> "<one-line description>"`
  and passed to every `create` in the group as an extra label (alongside the type label and,
  where there is a plan doc, `plan`). Then:
  - **One ticket is the core** — the one with a plan, filed first, in `ready` (or `draft` while
    its plan is under review). Its body ends with a sentence naming the follow-up slices.
  - **Every other ticket in the group is a Draft placeholder**: a scope paragraph, the three
    standard bullets with `_none yet_` for the plan, and a **`**Blocked by:**`** line directly
    above `**State:**` listing the tickets it needs merged first, built with `tracker.sh link`
    — never a bare number. A ticket that depends on nothing in the group still carries the
    label; it just has no `Blocked by` line. State reads "Not scoped. Next action: author a
    plan with the `issue-plan` skill once the blocking ticket has merged."
  - **File in dependency order**, so each `Blocked by` line can link a ticket that already
    exists, and read the ids back from `create`'s output rather than predicting them.
  - **Pre-existing tickets the group touches** (an older ticket a slice pairs with or
    supersedes) get the group label too, plus one comment naming the dependency — never a
    body rewrite.
  - Filing the placeholders is a decision for the person, not the skill: `issue-plan` §6 asks
    before filing anything beyond the core ticket.
- **The lifecycle** — the skills move cards by **lifecycle key**; `.agent/project.yml`'s
  `statuses:` section maps each key to the board's own column name, so a board may call
  `in_review` "Code Review", or put `merged` and `released` in one "Done" column (moving
  between two keys that share a column is a no-op). `tracker.sh statuses` prints the map.
  In flow order:

  | Key | Default column | Meaning |
  |-----|----------------|---------|
  | `draft` | Draft | Approach not settled — plan being written/reviewed, or a planless ticket that still needs one |
  | `ready` | Ready | Approach settled; implementation not started |
  | `in_progress` | In progress | Branch cut, milestones underway |
  | `in_review` | In review | Code milestones done, review request open |
  | `merged` | Merged | In `main`; production rollout pending (ticket closed at merge, where the tracker does that) |
  | `released` | Released | Deployed to prod / complete |
  | `parked` | Parked | Deliberately not scheduled |

  Prose in these skills names the default columns (Ready, In review…); commands pass keys.

## Steps

1. **Create the ticket.** Write the body to a scratchpad file, then:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/tracker.sh create <type> "<topic>" <scratchpad>/issue-body.md   # prints "<id>\t<url>"
   ```

   Pass `plan` as an extra trailing argument when the work has a plan doc — it adds the label
   alongside the type.

   Body shape (short — the plan doc holds the detail):

   ```markdown
   <One or two sentences: the problem or capability, with the concrete symptom/value.>

   - **Plan:** [`docs/plans/<file>.md`](<forge.sh file-url docs/plans/<file>.md>)   (_none yet_ if there is no plan doc)
   - **Branch:** [`<branch>`](<forge.sh branch-url <branch>>)
   - **PR:** _none yet_

   **Blocked by:** <tracker.sh link <id>, …>   (only on a ticket in a group that needs others merged first)

   **State:** <where things stand and the next action a fresh session can take>
   ```

   **All three bullets are always present, in this order, and each value is either a link
   or the placeholder `_none yet_`** — never omit a bullet because its value doesn't exist
   yet. Plan → `forge.sh file-url docs/plans/<file>.md`, which links the file on the base
   branch, never on the branch the plan was authored on, so the link survives that branch
   being deleted. Branch → `forge.sh branch-url <branch>`. PR → `forge.sh link <pr>`. (The
   bullet is labelled **PR** whatever the forge calls it — `forge.sh noun` gives the word
   for prose.)

   Plan and Branch are linked from the start, even though both 404 at the moment the ticket
   is filed — the plan only reaches `main` when it lands there, and the branch only exists
   after its first push. Their URLs are known in advance, so each link starts resolving on
   its own and needs no follow-up edit. The PR number isn't known until the PR exists, so
   that bullet starts as `_none yet_` and `issue-pr` fills it in when it opens the PR. Plan
   reads `_none yet_` only on a ticket with no plan doc; `issue-plan` fills it in if one is
   written later.

   **Write the body unwrapped.** Trackers render a newline inside a paragraph as a line
   break, so prose hard-wrapped at 80 columns keeps those breaks at every browser width and
   reads ragged. Each paragraph and each bullet is one unbroken line, however long, with
   blank lines only between blocks — let the browser do the wrapping. Same rule for ticket
   comments (`issue-update`) and PR bodies (`issue-pr`); it is the opposite of the commit
   convention, where messages *are* wrapped.

2. **Put the card on the board** and set its column. The test is whether the approach is
   settled, *not* whether a plan file exists — a small bug or chore whose fix is stated in
   the ticket body goes straight to `ready` with no plan doc. Use `draft` when a plan is still
   being written or under review, and for a planless ticket whose `**State:**` line reads
   "next action: author a plan" or otherwise still needs scoping:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/tracker.sh set-status <id> ready
   ```

   If this fails with a scope or permission error, relay the script's fix to the user (on
   GitHub: `gh auth refresh -s project,read:project`) and note the pending board step in
   your report; the ticket itself is already created. A rate-limit error means wait, not
   re-auth. If the board doesn't exist yet, run `${CLAUDE_PLUGIN_ROOT}/scripts/tracker.sh
   bootstrap` first.

3. **Cross-reference the plan.** If a plan doc exists, its `**Status:**` header line gains a
   ticket link (`tracker.sh link <id>`): `**Status:** Ready to implement · **Ticket:** [#NN](…) · **Date:** …`.

4. **Sweep `docs/todo.md`, if the repo keeps one.** Delete any lines the new ticket covers —
   per the note at the top of that file, `todo.md` holds only unplanned work, and the item is
   now tracked on the board (in any column). `issue-plan` and `issue-implement` repeat this
   sweep, but don't rely on them: a ticket filed directly (e.g. a bug) may never pass through
   those skills. Skip the step in repos with no such file.

5. Report the ticket id and URL, noting any `todo.md` lines removed. All later state changes
   go through the `issue-update` skill — never edit status prose into repo files: it goes
   stale on every branch that does not carry the edit, which is how README status tables end
   up conflicting between branches.
