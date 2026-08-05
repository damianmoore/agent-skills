---
name: browser-handoff
description: Hand your browser to a human when a page needs credentials you must not invent — a login form, 2FA, an SSO or OAuth consent screen — then take it back and persist the login so no future session hits that wall. Use when browser automation is blocked by authentication, a sign-in redirect, a captcha or any step that only a person can complete, and when someone asks to watch or drive the browser you are using.
---

# Hand the browser to a human

You drive a **shared** browser: it is not on your machine, and a person can watch it live
or take the keyboard, from a phone. This skill is what to do when a page asks for something
only a human has — and how to make sure the next session never has to ask again.

**Never invent credentials.** Not a plausible test password, not `admin/admin`, not an email
you made up. A login wall is not a test failure and not a puzzle: it is a handoff.

## When this applies

Any of these, on any page:

- a username/password form, a "sign in with…" button, or a magic-link prompt;
- a 2FA / OTP / passkey / hardware-key challenge;
- an SSO or OAuth consent screen (often a **popup**, i.e. a new browser target);
- a captcha or a bot-check interstitial;
- a paywall, an invite gate, or anything else that needs an account you do not own.

It does **not** apply when the app under test has fixture credentials the repo documents
(check `.agent/project.yml`, the README, and the project's secret files first) — use those.

## Before you start: is it already solved?

The platform stores a browser login per project, and your browser was seeded with it at
start-up. If you hit a wall anyway, check whether a state exists and is merely stale:

```bash
envctl auth list
```

- **A state is listed and looks current** → the session may just have expired, or the wrong
  state is loaded. Continue with the handoff; the fresh push at step 4 replaces it.
- **Nothing listed** → nobody has ever logged this project in. The handoff is how that
  changes.

## The protocol

### 1. Stop, and identify the wall

Take a page snapshot and read it. Name the thing precisely — the **origin** and what it
wants ("login needed for github.com", "2FA code for staging.example.com"). Do not click
around trying to route past it; a half-completed auth flow is harder for a human to finish
than a clean one. Leave the browser sitting on the page the person needs to see.

### 2. Page a human

Give the environment enough time to survive the wait first — a person has to find their
phone, open a DM and type a password, and an environment reaped mid-login wastes the whole
handoff:

```bash
envctl ttl 1h
envctl browser notify "login needed for github.com"
```

That sends a direct message and raises a "Needs you" item, both carrying a link that opens
your browser **in control mode**. Keep the reason to one plain line: it is the first thing
shown on a lock screen, and it is what tells the person which account to reach for.

Say the same thing in your own transcript/update, with the link, so the context is visible
to anyone reading along:

```bash
envctl browser url --control
```

### 3. Wait for the hand-back

The person finishes and presses **Hand back**. That delivers the sentence
`browser handoff complete` to you — how depends on the kind of session you are:

- **In a conversation** (a discussion session): it simply arrives as a message.
- **Otherwise** (the usual case — a one-shot headless run has no input channel): it is
  written to a **mailbox file** in the pod. Poll it:

  ```bash
  # patient, cheap, and bounded — a person on a phone is minutes, not seconds
  for _ in $(seq 1 120); do [ -f ~/.session/browser-handoff.json ] && break; sleep 15; done
  cat ~/.session/browser-handoff.json     # {"message":"browser handoff complete — …","event":"…","at":"…"}
  rm -f ~/.session/browser-handoff.json   # consume it: a stale file must not answer a LATER wait
  ```

  The `note` field carries anything the person added ("logged in as demo, 2FA done") —
  read it, it often says which account you are now using. Delete the file once you have
  read it.

Wait for that signal. Do not poll the page and guess — a page can look logged in
mid-redirect, and taking the browser back while someone is still typing breaks their flow.

**If nobody comes** (give it a genuinely generous wait — this is a human on a phone, not a
CI job), do not spin and do not carry on as if the wall were not there:

- post a `blocked:` comment on the ticket saying what is needed and what you tried, per the
  house convention (see the `issue-implement` skill);
- make sure your work is committed and pushed;
- park the task and continue with anything else in the plan that does not need that login.

### 4. Take it back, verify, and **save the login immediately**

The moment you have the browser back:

1. **Verify** you are actually authenticated — navigate to the page that was gated and
   confirm the content, not just the absence of a form. A redirect back to the login page
   means the handoff did not take; say so and go back to step 2.
2. **Persist it.** This is the step that makes the whole exercise worth doing:

   ```
   browser_storage_state          (Playwright MCP — writes a file, returns its PATH)
   envctl auth push --file <path> (uploads it to the control plane)
   ```

   Do this **before** anything else, and do it even if you are about to finish. The pod is
   ephemeral: an unsaved login dies with it, and the next session meets the same wall and
   pages the same person again. `browser_storage_state` returns a *path*, never the cookies
   — do not print or paste the file's contents anywhere.

   Use `--name <n>` only for a second identity or environment (`staging-admin`); the unnamed
   `default` state is the one every new session is seeded with.
3. **Clear the request** you raised, so nobody has to dismiss an answered page:

   ```bash
   envctl browser notify --resolved
   ```

### 5. Continue

Go back to exactly what you were verifying when you hit the wall, and finish it. Mention the
handoff in your milestone/PR notes — "logged in via handoff, storage state pushed as
`default`" — so a reviewer knows why that step is not automated and that it will not recur.

## Notes

- **Popups are new targets.** An OAuth consent window is a separate browser target; the
  viewer follows it automatically in control mode, so the person will see it. You may need
  to re-select the original page afterwards.
- **The MCP twins** are equivalent to the CLI, if you are driving envctl through tools
  rather than a shell: `browser_notify` (with `resolved: true` for step 4.3),
  `browser_view_url` (`control: true`), `browser_auth_push`, `browser_auth_list`.
- **Some logins resist any remote browser** (hardware keys, some Google flows). If a person
  reports they cannot complete it in the viewer, the escape hatch is theirs, not yours: they
  log in locally with `playwright codegen --save-storage=auth.json` and upload the state
  through the dashboard API. Record that as the outcome and move on.
