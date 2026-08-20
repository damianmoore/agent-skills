---
name: issue-plan
description: Write an implementation plan under docs/plans/ in this repo's house format — verified current-state section, locked decisions, checkbox milestones sized for Opus subagents — attached to the work's ticket on the project's configured GitHub Projects board (per .agent/project.yml), reusing the existing ticket when there is one and filing a new one via issue-create when there isn't. Also supports an async plan-PR review flow for headless or phone review, shipping the plan as a PR whose open questions are task-list checkboxes. Use when asked to plan a feature, fix, or migration, to turn an investigation into a plan document, or to put a plan up for async review — and equally for the back half of that flow, i.e. checking whether a plan PR has been approved, transcribing its answers, merging an approved plan PR, or moving a plan's card to Ready.
---

# Write an implementation plan

Produces `docs/plans/<topic>.md` in the same format as the existing plans, written so a
**fresh agent with no memory of this conversation** can pick it up and implement it end to end.

Read one or two recent plans under `docs/plans/` (including `docs/plans/archive/`) in this
repo in full before writing, when any exist — ideally one feature plan and one bug-fix plan,
since they exercise different sections. In a repo with none, the reference is `template.md`
in this skill's directory: follow its structure closely. Start from `template.md` either way.

The plan is a working document, not a proposal: it gets ticked, appended to, and amended in
place while the work happens.

## Project config

Repo-specific values live in `.agent/project.yml` in the repo you are working in. This skill
needs these keys, read once at the start of the run:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/issue-update/project-config.sh github.repo                   # <repo> — owner/name
${CLAUDE_PLUGIN_ROOT}/skills/issue-update/project-config.sh conventions.test_command ""   # test command, if any
${CLAUDE_PLUGIN_ROOT}/skills/issue-update/project-config.sh conventions.lint_command ""   # lint command, if any
${CLAUDE_PLUGIN_ROOT}/skills/issue-update/project-config.sh deploy.skill ""               # release skill, if any
```

The trailing `""` is the default: an empty result means the project defines no such command
or release skill, and the milestones below adapt accordingly — the rollout milestone names
the release steps explicitly, and a `**Verify:**` line says plainly that the repo configures
no test or lint command rather than inventing one. Keys read without a default exit non-zero
when missing — tell the user to add them to `.agent/project.yml` rather than guessing.

## Resolve the ticket first

Every plan has exactly one ticket. Establish which one **before** writing, so the plan carries
the right `**Ticket:**` link and §6 never files a duplicate.

- **If the invocation names one** — `#57`, an issue URL, or "the webhooks ticket" — use it.
  Read its body: it may already carry context, and its `**State:**` line says what was
  expected next.

  ```bash
  gh issue view <number> -R <repo> --json number,title,state,labels,body
  ```

- **If it doesn't, search before concluding there is none.** Work is normally captured as a
  ticket first, so a plan request usually *has* one already — typically sitting in **Draft**
  with a `**State:**` line reading "next action: author a plan":

  ```bash
  gh issue list -R <repo> --state open --limit 100 \
    --json number,title,labels \
    --jq '.[] | "\(.number)\t\(.title)\t\([.labels[].name]|join(","))"'
  ```

  Match on topic, not exact wording — "plan rate limiting for the API" is covered by
  `#56 API rate limiting`. Check `docs/plans/` for a file on the same topic while you are
  there; if one exists this is an amendment to that plan, not a new one.

- **If genuinely none exists**, there is nothing to reuse and §6 files one.

When the match is arguable, ask rather than guess. Filing a second ticket for work that
already has one splits its history across two cards, and the board is the single source of
truth for status.

---

## Review mode: interactive or plan PR

The plan gets a human review gate either way. Decide **which mode at the start of the run**,
before §2 — it changes how the open questions are put, and nothing else about the plan:

- **Interactive** — a human is at the terminal. Questions go through `AskUserQuestion` (§2),
  the ticket is filed at the end (§6), and its card lands in `Ready` once the plan is locked —
  `Draft` if it is not. This is the default whenever the session is interactive.
- **Async plan PR** — nobody is watching the terminal. Questions become **§0 Open questions**
  carrying proposed defaults (§2), the plan doc ships as a PR labelled `plan`, and the whole
  gate happens in the GitHub mobile app (§7). The card sits in `Draft` until that PR is
  approved and merged.

**Async is the default whenever the session is headless** — a session pod, a `claude -p` run,
any invocation with no interactive user — and whenever the user asks for review "async", "on
my phone", "as a PR" or similar. `AskUserQuestion` has no answer path in those sessions:
asking there either strands the run or quietly takes a default nobody chose.

**Probe for it rather than guessing:** if the `AskUserQuestion` tool is not available to you in
this session, you are headless — take the async path. If it is available, you are interactive.
An explicit request for async review overrides the probe either way; nothing overrides it
towards interactive.

Once §7.1 has run, **the mode is a property of the plan, not of the session**. A human who
turns up mid-plan reviews it through the PR, and an interactive session later asked to "check
the plan PR" or "finish it off" executes §7.3 as written — being interactive is not a reason to
re-ask questions that are already sitting on a PR.

---

## 1. Research before writing

Section 3 of every plan is headed **"Current state (verified <date>)"**. That word is load
bearing — every claim in it must have been checked against the code or a live system during
*this* session, and carry a `path/to/file.py:123` reference a reviewer can jump to. Never
write §3 from memory, from `CLAUDE.md`, or from a prior conversation summary.

Fan out to gather it. Independent questions go in one message so the agents run concurrently:

```
Agent(subagent_type: "Explore", model: "opus")  — locate the write paths / call sites / models
Agent(subagent_type: "Explore", model: "opus")  — inventory the frontend entrypoints and existing UI patterns
```

What §3 has to establish before the design can be trusted:

- **Every write path** that must be changed or gated. Plans fail when one is missed — a past
  plan needed a third, silently-invoked write path that nobody spotted until implementation.
- **Existing conventions to reuse** rather than invent: error patterns, UI patterns, migration
  patterns, test patterns, each with a file reference used as the model.
- **Duplication targets** — where the same fact is currently hard-coded in several places.
- For bug-fix plans: the **blast radius**, measured. Query the dev DB or prod read-only and put
  real counts in the plan ("747 episodes stuck, 652 of them from one host"), not adjectives.

## 2. Ask the open questions **before** writing

Anything that would change the shape of the plan is settled now, not left as a `TODO` in the
document. In interactive mode that means asking: use `AskUserQuestion`, batched (up to 4 per
call), recommended option first and labelled `(Recommended)`. In async plan-PR mode the same
questions are written down instead — see the subsection at the end of this section; the rest
of the section applies unchanged to both.

Ask about things like: which behaviour is intended when the rule bites; whether existing
over-limit or broken data gets migrated, grandfathered, or left; fail-open vs fail-closed;
whether it ships behind a feature flag and at what default; scope boundaries you are about to
assume ("I am treating personal workspaces as in scope — correct?"); anything that costs money,
touches billing, or sends email to real users.

Do **not** ask what the code can answer, or what has a conventional default. Decide those and
record them as decisions.

Every answer becomes a row in **§2 Decisions (locked)** with the decision, not the discussion.

If something genuinely cannot be settled until implementation starts (needs a prod value, a
founder ops step, a vendor response), it does not silently vanish — it goes in **§0 Open
questions**, which the implementing agent is instructed to put to the user before writing any
code. Leave §0 out entirely when there are none.

### Async mode: write the questions down instead of asking them

In async plan-PR mode there is nobody to answer an `AskUserQuestion`, so the same questions —
found by the same judgement about what would change the shape of the plan — go into **§0 Open
questions** instead. Each carries a **proposed default**: the option you would have marked
`(Recommended)`, restated as the answer the plan assumes if nobody says otherwise. Phrase the
question so that **ticking its box means "the default is fine"**, and use `template.md`'s
"Decision needed" callout form so it stays skimmable on a phone:

```markdown
- [ ] **Decision needed:** Do existing over-limit workspaces get migrated, grandfathered, or
      left alone? — **Default:** grandfathered; the cap binds new additions only (§4.5).
```

These lines are copied into the plan PR body as GitHub task-list items (§7.2), and each one
the reviewer ticks or answers becomes a §2 Decisions row at approval (§7.3). Async mode is
not licence to punt: a question the code or a conventional default can answer is still yours
to decide and record straight in §2.

**§0 therefore carries two kinds of entry, written identically:** questions deferred to
implementation time (the paragraph above), and — in async mode only — the plan-review
questions with their defaults. Do not split them into subsections or mark which is which.
Both are boxes a human must tick before code is written, and `issue-implement`'s §0 gate
treats whatever is still unticked when it runs the same way. In async mode the review
answers simply arrive first and are ticked before the plan PR merges, so anything left
unticked on `main` is by construction the implementation-time kind — §7.3 guarantees that by
consuming *every* review-time question at approval, including the boxes the reviewer left
untouched, which an approval accepts at their proposed defaults.

## 3. Write the document

`docs/plans/<kebab-topic>.md` (no `-plan` suffix — the `plans/` directory already says so). Section order is fixed — copy `template.md` and fill it in:

| § | Section | Content |
|---|---------|---------|
| — | Title + `**Status:** … · **Ticket:** #NN · **Date:** …` | Status is `Ready to implement`, `Draft — not scheduled`, or `Draft for review`; the ticket link is added in step 6. In async mode the plan is authored as `Draft for review` and flips to `Ready to implement` when its plan PR is approved (§7.3) |
| — | Lede (2–3 paragraphs, no heading) | The problem in concrete terms, with the evidence: file references, real numbers, the customer-visible symptom. A reader must understand why this exists before reaching §1 |
| — | Progress log | Empty at authoring time except its standing instruction line |
| 0 | Open questions | Only if any survived §2 above — the ones deferred to implementation time, plus (in async mode) every question that would have been asked interactively, each with its proposed default. Otherwise omit |
| 1 | Goal & non-goals | Non-goals matter as much as the goal — they stop scope creep mid-implementation |
| 2 | Decisions (locked) | Two-column table. Every judgement call, including the ones you made yourself |
| 3 | Current state (verified `<date>`) | §1 research, subsectioned, every claim referenced |
| 4 | Design | Data model, new modules with their function signatures, exact error copy, GraphQL payload shapes, per-entrypoint treatment tables, rollout behaviour |
| 5 | Milestones | The checkboxes — see below |
| 6 | Risks & edge cases | Each with its mitigation or an explicit "accepted for v1" |
| 7 | Out of scope / future ideas | Where the good ideas go to not derail this branch |

Write §4 concretely enough that the implementer is not redesigning: give the actual field
definitions, the actual function signatures, the actual user-facing strings, the actual
migration numbers. If a string is a stable match token for other code, say so.

## 4. Milestone rules

Milestones are the part an agent works through, so they carry the most weight.

- **M1 … Mn, in dependency order.** Each must be independently committable and leave the app
  releasable — never a state where `main` could not ship.
- **Each is one subagent's job.** Size it to fit comfortably in one Opus context: roughly
  3–8 checkboxes over a coherent slice (backend foundation / enforcement / frontend plumbing /
  one UI surface / rollout). Split anything bigger.
- **Every box is self-contained**: name the file, the line range where it exists today, the
  §4 subsection carrying the design, and the pattern file to copy. A box that reads
  `- [ ] Add validation` is a defect; `- [ ] Seat check in UserInviteMutation.mutate
  (§4.4.1 — before invitee User creation; re-invites of existing members exempt)` is the bar.
- **Tests are a box, not an afterthought**, and they name the cases to cover and the existing
  test file whose pattern to follow.
- Each milestone ends with two lines:
  - `**Verify:** ` — the exact commands. Resolve the repo's configured
    `conventions.test_command` / `conventions.lint_command` **now**, while writing the plan,
    and put the resolved, runnable commands into the line — narrowed to the area under change
    where the command supports it — never the config key names. The implementer must be able
    to copy the line and run it. Add the manual walkthrough where behaviour is user-visible.
  - `**Done when:** ` — an observable end state, phrased so the verification subagent can
    return true or false on it.
- **The last milestone is production rollout** and is normally the founder's, not the agent's:
  pre-flight checks against prod, release via the project's configured `deploy.skill` skill
  when one exists (otherwise name the release steps explicitly), flag flips with what to
  verify at each state, and the docs/todo cleanup.
- Ops work with lead time (vendor API access, tokens, DNS) goes in an **M0** flagged as a
  founder task, called out early because it blocks later milestones.

## 5. The implementation protocol pointer

The protocol itself lives in **one place: the `issue-implement` skill** — §0 questions first,
branch off `main`, per-milestone Opus implement + separate Opus adversarial verify,
`git-commit` skill + push per milestone, `issue-pr` skill at completion, ticket/board upkeep
via `issue-update`. Do **not** copy those steps into the plan; the top of §5 carries only the
short pointer block from `template.md`, with the branch name filled in. Branch names follow
`<prefix>/<kebab-topic>` with one of the standard prefixes — `feat/` (new capability),
`fix/` (bug fix), `chore/` (tooling, docs, ops), `refactor/` (behaviour-preserving
restructure) — where `<kebab-topic>` is usually the plan filename minus `.md` (e.g.
`fix/feed-fetch-reliability`). Plan-specific process notes (a migration-collision warning, a
"land X first" ordering constraint) do belong there, beneath the pointer.

## 6. Finishing up

- Do not implement anything while writing the plan. Authoring and implementing are separate
  sessions; the plan is the handoff.
- **Settle the ticket, using whatever *Resolve the ticket first* turned up:**
  - *A ticket already exists* — **do not file another.** Attach the plan to it: add a
    `**Plan:**` line to the issue body if it has none (linked to `main`, as `issue-create`
    step 1 shows), add the `plan` label, and move its card to `Ready` (or leave it in `Draft`
    if the plan is not yet locked) via the `issue-update` skill.
  - *No ticket exists* — file one via the `issue-create` skill: board column `Ready` (or
    `Draft` if not yet locked), type label matching the branch prefix, plus the `plan` label.

  Either way, add the `**Ticket:** #NN` link to the plan's `**Status:**` line. The board —
  not any repo file — is the single source of truth for status.
  **In async mode the column is always `Draft`** (the plan PR is what locks the plan), and
  the ticket is settled **here, before §7 cuts the branch** — the plan PR body has to
  reference `#NN`, and the plan doc that gets committed should already carry the ticket link.
- **If the repo keeps a `docs/todo.md`, remove any lines this plan covers** in the same
  session as filing the ticket. Per the note at the top of that file, `todo.md` holds only
  unplanned work — once a ticket exists on the board (in any column, including Draft or
  Parked), the ticket is the single tracker. In async mode those deletions ride along on the
  plan branch and land when the plan PR merges.
- **In interactive mode, land the plan on `main`** — always, and never on a feature branch.
  See below. In async mode the plan lands when its PR merges (§7.3), so skip it there.
- Report back with the path, the ticket number **and whether it was reused or newly filed**,
  the milestone count, any open questions still unanswered, which `todo.md` lines were
  removed, and — interactive mode — the commit sha the plan landed on `main` as.

### Interactive mode: land the plan on `main`

A plan is a handoff document: `issue-implement` branches off `main` to work it, and any future
session looking for it expects it there. A plan left uncommitted, or committed onto whatever
feature branch happened to be checked out, is invisible to both. **So the plan is always
committed, and always to `main`** — including the `todo.md` deletions above, which belong in
the same commit.

Follow the `git-commit` conventions for the message: one line, ≤72 chars, present-tense
imperative, no AI/assistant attribution, no `Co-Authored-By` trailer. `Add <topic>
implementation plan` for a new plan, `Update <topic> plan — <what changed>` when amending an
existing one.

**If `main` is already checked out**, commit in place:

```bash
git add -- docs/plans/<file>.md docs/todo.md   # todo.md only if it changed
git commit -m "Add <topic> implementation plan"
git push
```

**Otherwise — the normal case, since planning usually happens mid-branch — commit to `main`
through a temporary worktree, leaving the current branch and its working tree untouched:**

```bash
plan=docs/plans/<file>.md
msg="Add <topic> implementation plan"
wt=".claude/worktrees/_plan-$(basename "$plan" .md)"

git fetch origin main
git worktree add "$wt" main
git -C "$wt" merge --ff-only origin/main    # no-op when local main is already current
cp "$plan" "$wt/$plan"                      # plus any docs/todo.md edit from above
git -C "$wt" add -- "$plan"
git -C "$wt" commit -m "$msg"
git -C "$wt" push
git worktree remove "$wt"
rm -- "$plan"
```

Notes on that sequence:

- **The `--ff-only` step is not optional.** Committing on a stale local `main` produces a push
  that is rejected as non-fast-forward. If the fast-forward itself fails, local `main` has
  diverged from the remote — stop and tell the user rather than merging or rebasing it.
- **The final `rm` is deliberate.** Once the plan is on `main`, the untracked copy left behind
  on the feature branch would block the next `git merge main` with *"untracked working tree
  files would be overwritten"*. Read it from `main` instead — `git show main:$plan` — or wait
  for it to arrive with the next merge. Say in the report that the working-tree copy was
  removed, so nobody thinks it was lost.
- **Restore any *tracked* file you carried over the same way** — `docs/todo.md`, or anything
  else edited alongside the plan: `git checkout -- docs/todo.md`. The `rm` above only handles
  the plan, which is untracked. A tracked file left modified on the feature branch gets folded
  into that branch's next commit and then conflicts on the next merge from `main`.
- Keep `.claude/worktrees/` out of version control (a line in `.git/info/exclude` does it
  without touching the repo's `.gitignore`), so the temporary worktree never shows up as
  untracked. Remove it even when a later step fails.
- **If `git worktree add` fails with "main is already checked out"**, another worktree holds
  it — commit there instead of creating a second one (`git worktree list` finds it).
- **If the push is rejected, do not force.** Report it and stop; the commit is intact on local
  `main`.
- The ticket work itself is untouched by this — `issue-implement` still cuts its own branch
  from `main` later, and picks the plan up from there.

**Interactive mode is done once the plan is on `main`.** In async mode the plan is not
finished until its PR is open — continue to §7, and report the PR URL alongside everything
above.

---

## 7. The plan-PR gate

The plan itself goes up as a pull request, so the review runs entirely in the GitHub mobile
app: read the diff, tick the §0 boxes or answer them in a comment, approve. Nothing about the
plan's *content* changes — only how it is reviewed and when the card moves.

Async mode is what opens this gate, but the gate is not owned by the session that opened it:
once §7.1 has run, any session asked to check on, answer, or finish the plan PR works through
§7.3 below, interactive or not.

**The gate presupposes two identities.** The agent account (a dedicated bot user) opens the
plan PR; the human named in `github.assignee` approves it. GitHub refuses an approving review
from a PR's own author, so in a single-identity setup — the pipeline running under your own
login on a laptop, where the author *is* the configured reviewer — a formal approval is
impossible and waiting for one deadlocks the plan. **In that configuration only**, an explicit
approving comment from the configured reviewer ("approved", "LGTM — merge it") is the gate;
say in your report that you took a comment as the approval and why. This is a stopgap until the
two-account setup exists, not a general relaxation — wherever author and reviewer are different
accounts, an `APPROVED` review is the only thing that opens the gate.

Read the two config values this needs the same way every other skill does:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/issue-update/project-config.sh github.repo       # <repo> — owner/name
${CLAUDE_PLUGIN_ROOT}/skills/issue-update/project-config.sh github.assignee   # <assignee>
```

Both are required keys — on a non-zero exit, tell the user to add them to
`.agent/project.yml` rather than guessing a repo or a login.

### 7.1 Branch and push the plan

The branch is `plan/<kebab-topic>` — the *same* `<kebab-topic>` the implementation branch will
use later, with `plan/` in place of the type prefix, so the two are visibly the same work:
`plan/feed-fetch-reliability` now, `fix/feed-fetch-reliability` at implementation time.

```bash
git fetch origin
git switch -c plan/<kebab-topic> --no-track origin/main
git push -u origin plan/<kebab-topic>
```

`--no-track` is load-bearing here for exactly the reason `issue-implement` §1 gives: on a
machine with `push.default=upstream`, a branch cut tracking `origin/main` pushes **straight to
remote `main`**. Read the push output and confirm it says `-> plan/<kebab-topic>`.

`git switch -c` carries uncommitted work across, so the plan doc and the `docs/todo.md`
deletions from §6 come with you — they do not need committing first. The one hazard is a
**shared** file: the branch is cut from freshly-fetched `origin/main`, and if `origin/main` has
moved on since your checkout, git refuses the switch rather than clobber your edits to a file
that also changed upstream. Cut the branch *before* editing anything shared like
`docs/todo.md` when that is a possibility.

Then commit the plan doc — plus any `docs/todo.md` deletions from §6 — with the `git-commit`
skill and push. Never commit the plan to `main` directly in this mode; merging the plan PR is
what puts it there.

**No closing keywords in any commit message on this branch** — no `Closes #NN`, `Fixes #NN` or
`Resolves #NN`. A squash merge concatenates the branch's commit messages into the merge body by
default, so one such subject would close the ticket the moment the plan merged, for the same
reason §7.2 bans it in the PR body. §7.3 pins the merge subject and body explicitly as a second
line of defence.

### 7.2 Open the plan PR

The body is a *summary* plus the questions, not a copy of the plan — the diff is the plan.
Write it to a scratchpad file rather than fighting shell quoting, as `issue-pr` does:

```markdown
## What this plans

<Two to four sentences, lifted from the plan's lede: the problem in concrete terms and the
shape of the fix. Lead with the user-visible symptom.>

## How to review this

- **Read** `docs/plans/<kebab-topic>.md` — §1 goal and non-goals, §2 decisions, §5 milestones.
- **Scrutinise** §2: those decisions are what the implementation will not re-litigate.
- **Answer** the questions below — tick a box to accept its default, or reply in a comment
  to choose something else.

## Open questions

- [ ] **Decision needed:** <question> — **Default:** <proposed answer, with one clause on
      what a different answer would change>
- [ ] **Decision needed:** <question> — **Default:** <proposed answer>

Approving this PR locks the plan: every ticked default becomes a §2 decision, the plan merges
to `main`, and the ticket moves to Ready.

Part of #NN
```

The task-list items are the §0 entries **verbatim** — same wording, same defaults. That is
what makes ticking a box on a phone an unambiguous answer.

**End the body `Part of #NN`, never `Closes #NN`.** This is the one place the `issue-pr` rule
inverts, and the reason is board automation: the board's built-in *Item closed* workflow fires
on the issue closing, so a plan PR merged with a closing keyword would close the ticket and
slam its card from `Draft` to `Merged` before a single line of the work existed. `Part of #NN`
cross-references the ticket without closing it. `issue-pr`'s `Closes #NN` rule still holds for
the **implementation** PR — that one is meant to close the ticket.

Everything else follows `issue-pr`'s conventions: one-line title, ≤72 characters, concrete
over salesmanlike, and no mention of Claude, AI or assistant tooling anywhere in the body —
no `Co-Authored-By`, no "Generated with" trailer. The title is `Plan: <topic>`
(`Plan: Feed fetch reliability`), reusing the ticket's topic wording. That is a noun phrase
rather than `issue-pr`'s imperative, deliberately: this PR names a plan, it does not describe
a change to the code.

```bash
gh pr create -R <repo> \
  --base main \
  --title "Plan: <topic>" \
  --body-file <scratchpad>/plan-pr-body.md \
  --label plan \
  --assignee <assignee>

gh pr edit <pr> -R <repo> --add-reviewer <assignee> 2>&1 || true
```

`plan` is the same repo label `issue-create` puts on plan-backed tickets (`bootstrap-board.sh`
creates it); it is what tells a reviewer, and the notification stream, that this PR is a gate
and not code. As in `issue-pr`, the `--add-reviewer` step fails with "review cannot be
requested from pull request author" when the configured reviewer opened the PR — that is
normal, `--assignee` already put it on their list, so note it in a clause and move on.

Finally, leave the trail on the ticket (the card is already in `Draft` from §6 — no move):

```bash
gh issue comment <issue#> -R <repo> \
  --body "Plan up for review on PR #<pr> (branch \`plan/<kebab-topic>\`). Card stays in Draft until it's approved and merged."
```

### 7.3 When the plan is approved

Approval means a PR review in the `APPROVED` state — or, in the single-identity configuration
described at the top of §7, an explicit approving comment from the configured reviewer.
Otherwise never infer approval from a friendly comment, and never approve or merge on your own
reading of the thread.

**Get back on the plan branch before touching anything.** Approval usually arrives in a new
session, sitting on `main`, and every edit below has to land inside the PR — editing here
without switching pushes the plan's own locking commit to `main`, which is exactly what §7.1
forbids:

```bash
git fetch origin
git switch plan/<kebab-topic> || git switch -c plan/<kebab-topic> --track origin/plan/<kebab-topic>
git pull
```

The first `git switch` covers the branch already existing locally; the fallback creates it from
the remote in a session that has never seen it.

**Then collect the answers — from all three surfaces.** They can arrive as ticked checkboxes in
the **PR body**, as **conversation comments**, or as **inline review comments** on the plan
diff (the natural thing to do when reading a diff on a phone). `--json comments` returns
conversation comments *only*, so the inline review threads need the API call as well:

```bash
gh pr view <pr> -R <repo> --json reviewDecision,reviews,body,comments
gh api "repos/<repo>/pulls/<pr>/comments"     # inline review-thread comments
```

Read all three before transcribing anything. Where a comment and a checkbox disagree, **the
comment wins** — a ticked box under a comment saying "actually, do B" is answered B.

`reviewDecision` is authoritative whenever it is non-empty: `APPROVED` means approved. It comes
back null or empty on repos with no branch protection and no requested reviewer — there, fall
back to the latest review in `reviews` having state `APPROVED`.

**An approval with the boxes untouched and no contrary comment accepts every proposed
default.** That is what writing defaults into the questions is *for*: the reviewer read them
and pressed Approve. Record each default as a §2 Decisions row, tick its box yourself, and note
"accepted by approval" in the row.

The converse does **not** hold. Boxes ticked or answers commented with no approval is not a
gate: do not merge. Leave one comment summarising what you have taken as answered and asking
for the approval click, then stop and report the wait state. Nudge once — not on a loop.

Then, in this order:

1. **Record every answer as a row in §2 Decisions (locked)** — one row per question, none left
   over. A ticked box is an accepted default and becomes a decision exactly like a written
   answer: "Grandfathered; the cap binds new additions only", not "we agreed to grandfather
   it". A commented answer counts identically to a tick, and an untouched box under an
   approval is the default accepted — with "accepted by approval" noted in the row.
2. **Tick the §0 boxes** you have just converted, and delete §0 entirely if that empties it.
   Anything genuinely unanswerable until implementation stays in §0 for `issue-implement`'s
   gate to pick up.
3. **Flip the plan's status line** — the `**Status:**` header becomes `Ready to implement`.
4. **Commit those edits with the `git-commit` skill and push.** They must land *inside* the
   PR, so the plan that reaches `main` is the locked one.
5. **Re-check the approval, now that you have pushed.** Under branch protection with "dismiss
   stale approvals when new commits are pushed", the transcription commit you just pushed
   dismisses the very approval you are acting on, and the merge is refused:

   ```bash
   gh pr view <pr> -R <repo> --json reviewDecision,reviews
   ```

   If it no longer reads `APPROVED`, **do not merge**. Comment on the PR saying the only change
   since the approval is the transcription commit, what it contains (the §2 rows, the ticked
   boxes, the status flip — no change to the design), and asking for a re-approval. Then stop
   and report the wait state.
6. **Merge, only now that the approval still stands:**

   ```bash
   gh pr merge <pr> -R <repo> --squash --delete-branch \
     --subject "Plan: <topic> (#<pr>)" \
     --body "Part of #NN"
   ```

   Pin the subject and body explicitly. Left to itself, a squash merge concatenates the
   branch's commit messages into the merge body, so a single commit reading "Fixes #NN" would
   close the ticket and fire the board's *Item closed* automation — precisely what §7.2's
   `Part of #NN` exists to prevent.
7. **Move the card to `Ready`** via the `issue-update` skill, with the transition comment:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/skills/issue-update/board.sh status <issue#> "Ready"
   gh issue comment <issue#> -R <repo> \
     --body "Plan approved and merged (PR #<pr>). Ready to implement on \`<prefix>/<kebab-topic>\`."
   ```

8. **Confirm the plan branch is gone.** `--delete-branch` removes it on the remote and, run
   from a clone, locally too; check with `git branch --list 'plan/*'` and clean up if not.
   Then `git switch main && git pull` so the implementation branch is later cut from an
   up-to-date `main`.

Implementation is unchanged from there: `issue-implement` picks the ticket up out of `Ready`
and cuts `<prefix>/<kebab-topic>` off `main`. Its §0 gate still runs, so anything left
unticked is put to the user before code is written.

### 7.4 When the plan is rejected or superseded

"Request changes" is a **revision**, not a rejection: address the feedback on the same branch,
push, and the same approval path applies.

A plan that is genuinely not going ahead does not merge — close the PR with the reason:

```bash
gh pr close <pr> -R <repo> --delete-branch \
  --comment "<why — the decision that killed it, and the successor ticket if there is one>"
```

Then follow the `issue-update` skill for the ticket:

- **Shelved for now** — card to `Parked`, comment saying why and what would unpark it, and
  leave the issue **open**: closing it would bounce the card to Merged.
- **Superseded** — comment naming the successor ticket, `gh issue close <n> --reason "not
  planned"`, **then** set the column to `Released`, because the close fires the Merged
  automation first.

The plan doc dies with the branch — it never reached `main`, so there is nothing to archive.
