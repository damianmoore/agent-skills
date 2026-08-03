# <Problem or feature, stated concretely — not the branch name>

**Status:** Ready to implement · **Ticket:** [#NN](https://github.com/<repo>/issues/NN) · **Date:** <YYYY-MM-DD>

<Lede, 2–3 paragraphs, no heading. The problem in concrete terms with evidence: what is
broken or missing, the customer-visible symptom, real numbers from prod/dev where relevant,
and `path/to/file.py:123` references for the key claims. A reader must understand why this
plan exists before reaching §1. For bug fixes: root cause here, in one paragraph.>

---

## Progress log

Implementing agents: append one line here per completed milestone (date, milestone, commit),
and tick the checkboxes in place. Keep milestone order — each is independently committable.
If reality forces a deviation from the design, record it here with the reason — never
silently implement something else.

<!-- - YYYY-MM-DD — M1: <one-line summary> — commit <hash> -->

---

## 0. Open questions (ask before implementing)

<Omit this section entirely if none. Two kinds of entry live here, written identically and
never split apart: questions that could not be settled at authoring time (they need a prod
value, a founder ops step, a vendor response), and — in async plan-PR review mode — every
question that would have been put interactively, each carrying the default the plan assumes.
Any box still unticked when implementation starts must be put to the user with
`AskUserQuestion` BEFORE any code is written, and each answer recorded as a new row in §2.>

<Write each one as a "Decision needed" callout — bold label, the question, then the proposed
default — phrased so that ticking the box means "the default is fine". Keep it to the one
wrapped line: in async mode these are copied verbatim into the plan PR body as GitHub
task-list items and read on a phone screen.>

- [ ] **Decision needed:** <the question, and what it changes> — **Default:** <the answer
      the plan assumes if nobody says otherwise; one clause on what any other answer alters>

  > <Optional, only when the trade-off needs it: a sentence of context or evidence.
  > Anything longer belongs in §4 with a pointer from here.>

---

## 1. Goal & non-goals

**Goal:** <one sentence — the end state this plan delivers.>

**Non-goals:** <explicit exclusions with reasons or pointers — these stop scope creep
mid-implementation. "No X (future idea — precedent at path:line)".>

---

## 2. Decisions (locked)

| Area | Decision |
|------|----------|
| **<Area>** | <The decision, stated as a rule the implementation follows — not the discussion that produced it. Include values, defaults, flag states.> |

---

## 3. Current state (verified <YYYY-MM-DD>)

<Everything here was checked against the code or a live system on the date above — no claims
from memory. Every claim carries a `path/to/file.py:123` reference. Subsection by concern.>

### 3.1 <Data model / existing behaviour>

### 3.2 <The write paths / call sites that must change — ALL of them, including indirect ones>

### 3.3 <Existing conventions to reuse — error patterns, UI patterns, migration patterns, test patterns, each with the file used as the model>

### 3.4 <For bug fixes: blast radius, measured — real counts, not adjectives>

---

## 4. Design

<Concrete enough that the implementer is not redesigning: actual field definitions in code
blocks, actual function signatures, actual user-facing strings (flag any that are stable
match tokens for other code), migration numbers, GraphQL payload shapes, per-entrypoint
treatment tables, rollout/flag behaviour.>

### 4.1 <Data model>

### 4.2 <New modules / functions — signatures and contracts>

### 4.3 <Enforcement / integration points>

### 4.4 <Frontend / UX treatment per entrypoint>

### 4.5 <Rollout behaviour — what each flag state means>

---

## 5. Milestones

Instructions for implementing agents: run this plan with the **`issue-implement` skill** — do
not free-hand the process. It covers §0 questions, branching (branch name:
`<feat|fix|chore|refactor>/<kebab-topic>`), per-milestone Opus implement + separate Opus
adversarial verify, commits/pushes, the PR, and keeping this plan's Progress log and the
ticket's board card (via the `issue-update` skill) current.

### M1 — <Coherent slice, sized for one Opus subagent (~3–8 boxes)>

- [ ] <Self-contained box: the change, the file (`path:line` where it exists today), the §4
      subsection carrying the design, the pattern file to copy>
- [ ] <Migration box: app + number, schema/data/seed, reverse behaviour>
- [ ] Tests: <the cases to cover, named; the existing test file whose pattern to follow>

**Verify:** <exact commands — the repo's configured test and lint commands, narrowed to the
area under change — plus the manual walkthrough when behaviour is user-visible.>
**Done when:** <an observable end state the verification subagent can answer true/false on.>

### M2 — <…>

- [ ] …

**Verify:** …
**Done when:** …

### M<n> — Production rollout (founder task)

- [ ] Pre-flight on prod: <what to confirm before deploying — data present, flags seeded,
      env values, saved baseline output of any audit command>
- [ ] Release via the project's configured `deploy.skill` skill (`.agent/project.yml`), or
      the explicit release steps when the project has none
- [ ] <Flag flips in order, with what to verify at each state>
- [ ] Sweep `docs/todo.md`, if the repo keeps one, for lines this plan resolves that were
      added after authoring (lines it covered at authoring were already removed then);
      append final Progress log entry

**Done when:** <the end-to-end prod state.>

---

## 6. Risks & edge cases

- **<Risk>**: <mitigation, or an explicit "accepted for v1" with the reason>

## 7. Out of scope / future ideas

- <Good ideas deliberately excluded, with enough context to pick them up later>
