---
name: issue-plan
description: Write an implementation plan under docs/plans/ in this repo's house format — verified current-state section, locked decisions, checkbox milestones sized for Opus subagents — and file its ticket on the project's configured GitHub Projects board (per .agent/project.yml) via issue-create. Use when asked to plan a feature, fix, or migration, or to turn an investigation into a plan document.
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
${CLAUDE_PLUGIN_ROOT}/skills/issue-update/project-config.sh conventions.test_command ""   # test command, if any
${CLAUDE_PLUGIN_ROOT}/skills/issue-update/project-config.sh conventions.lint_command ""   # lint command, if any
${CLAUDE_PLUGIN_ROOT}/skills/issue-update/project-config.sh deploy.skill ""               # release skill, if any
```

The trailing `""` is the default: an empty result means the project defines no such command
or release skill, and the milestones below adapt accordingly — the rollout milestone names
the release steps explicitly, and a `**Verify:**` line says plainly that the repo configures
no test or lint command rather than inventing one. Keys read without a default exit non-zero
when missing — tell the user to add them to `.agent/project.yml` rather than guessing.

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

Anything that would change the shape of the plan is asked now, not left as a `TODO` in the
document. Use `AskUserQuestion`, batched (up to 4 per call), recommended option first and
labelled `(Recommended)`.

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

## 3. Write the document

`docs/plans/<kebab-topic>-plan.md`. Section order is fixed — copy `template.md` and fill it in:

| § | Section | Content |
|---|---------|---------|
| — | Title + `**Status:** … · **Ticket:** #NN · **Date:** …` | Status is `Ready to implement`, `Draft — not scheduled`, or `Draft for review`; the ticket link is added in step 6 |
| — | Lede (2–3 paragraphs, no heading) | The problem in concrete terms, with the evidence: file references, real numbers, the customer-visible symptom. A reader must understand why this exists before reaching §1 |
| — | Progress log | Empty at authoring time except its standing instruction line |
| 0 | Open questions | Only if any survived §2 above. Otherwise omit |
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
restructure) — where `<kebab-topic>` is usually the plan filename minus `-plan` (e.g.
`fix/feed-fetch-reliability`). Plan-specific process notes (a migration-collision warning, a
"land X first" ordering constraint) do belong there, beneath the pointer.

## 6. Finishing up

- Do not implement anything while writing the plan. Authoring and implementing are separate
  sessions; the plan is the handoff.
- **File the ticket via the `issue-create` skill**: board column `Ready` (or `Draft` if the
  plan is not yet locked), type label matching the branch prefix, plus the `plan` label.
  Add the resulting `**Ticket:** #NN` link to the plan's `**Status:**` line. The board —
  not any repo file — is the single source of truth for status.
- **If the repo keeps a `docs/todo.md`, remove any lines this plan covers** in the same
  session as filing the ticket. Per the note at the top of that file, `todo.md` holds only
  unplanned work — once a ticket exists on the board (in any column, including Draft or
  Parked), the ticket is the single tracker.
- Report back with the path, the ticket number, the milestone count, any §0 questions still
  open, and which `todo.md` lines were removed.
