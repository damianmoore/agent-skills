# PR screenshots

The generic mechanics behind `SKILL.md` §5. A PR whose diff changes what a user sees in the
app carries a `## Screenshots` section in its **body**, captured from the pushed head. When
later pushes change the UI that section is replaced, never added to.

This file covers everything that is the same in every repo. The project's own guide — the
path in `pr.screenshots_guide` in `.agent/project.yml` — covers the rest, and you need both:

- **Which diffs need screenshots** — the paths that render the app, and the ones that don't.
- **How to boot the pushed commit** on a throwaway stack that never touches shared dev data,
  how to seed it with plausible fixture data, and how to log in.
- **Capture extras** — floating widgets to hide, pages that need a warm-up request.
- **Teardown.**

No guide configured means the project takes no PR screenshots: skip `SKILL.md` §5.

## 1. Does the PR need screenshots?

Yes when the diff changes the rendered app, as the project guide defines it. Never for logic
with no visible effect, tests, docs, schema snapshots or emails unless the guide says
otherwise.

A copy-only change gets no screenshots. Put the old and new wording in "What changed"
instead: a picture of a sentence is harder to review than the sentence.

## 2. Pick the shots

- **One shot per new or visibly changed element or state**, in the order a user meets them.
  Aim for four or fewer; any more should each justify themselves in their caption.
- **Crop to the change plus a little context:** the element, its section heading, and about
  24px of padding. Capture a full viewport only when *where* it sits is the point (a new nav
  item, a new banner). For a new page, capture its form or content block, not the header
  and footer; the caption says where the page lives.
- **Don't repeat yourself.** If an edit form is the add form plus a toggle, the second shot
  crops to the difference, and the caption says so.
- **Describe wording variants in text.** An empty state, a limit-reached label or an error
  message that differ only in wording from a shot you already have go in a bullet under it.
- **Viewport:** desktop, 1280×900. Add a 390px shot only when the change has its own
  narrow-screen layout.
- **Don't hide defects.** If a capture shows overflow, clipping or a broken state, fix it
  before opening the PR when it's in scope. Otherwise capture it as rendered and name it in
  the caption, so the reviewer sees what a user would.

## 3. Boot the pushed commit

The shots must show exactly what was pushed, so check that first:

```bash
git status --short                                    # must be empty
git fetch origin <branch> && git rev-parse HEAD origin/<branch>   # the two must match
```

Then boot that commit and seed it **as the project guide describes**. Whatever the mechanism,
key the stack on the short SHA (`git rev-parse origin/<branch> | cut -c1-7`): the caption and
the teardown both use it, and a branch name points at a different commit after the next push.
Seed data must be fictional and plausible, with at least one row per visual state the change
introduces (enabled and disabled, success and failure) — never a real customer's data.

## 4. Capture with Playwright

- Use whichever Playwright MCP instance is free. "Browser is already in use" means another
  session holds that profile; switch to the other (`mcp__playwright__*` is headless,
  `mcp__playwright-headed__*` is visible).
- Work in a tab you opened yourself (`browser_tabs` → `new`). Never navigate a tab you
  didn't open: it may be the user's GitHub sign-in.
- Before the first shot, `browser_resize` to 1280×900 and
  `mkdir -p .playwright-mcp/pr-<branch-slug>` in the **main checkout**. The MCP writes there
  even from a worktree, and won't create directories.
- Capture with `browser_run_code_unsafe`, cropping to the union of a few specific locators:

```js
async (page) => {
  const parts = [
    page.getByRole('heading', { name: 'Webhook endpoints' }),
    page.locator('table', { hasText: 'acme.example' }),
  ];
  const pad = 24;
  await parts[parts.length - 1].waitFor();
  await page.evaluate(() => window.scrollTo(0, 0));
  const pageWidth = await page.evaluate(() => document.documentElement.scrollWidth);
  const boxes = await Promise.all(parts.map((p) => p.boundingBox()));
  const x1 = Math.max(0, Math.min(...boxes.map((b) => b.x)) - pad);
  const y1 = Math.max(0, Math.min(...boxes.map((b) => b.y)) - pad);
  const x2 = Math.min(pageWidth, Math.max(...boxes.map((b) => b.x + b.width)) + pad);
  const y2 = Math.max(...boxes.map((b) => b.y + b.height)) + pad;
  await page.screenshot({
    path: '.playwright-mcp/pr-<branch-slug>/01-<slug>.png',
    clip: { x: x1, y: y1, width: x2 - x1, height: y2 - y1 },
    fullPage: true,
    style: '<the guide\'s hide rule, if any>',
  });
}
```

  Each piece is there for a reason:
  - A plain element screenshot drops the heading that gives the shot its context.
  - `scrollTo(0, 0)` plus `fullPage: true` make the boxes page coordinates. A page scrolled
    even sideways, which happens when content overflows, shifts every box.
  - `style` hides floating widgets (a chat launcher, a cookie banner) in the capture only.
    The project guide names them; use `display: none`, because `visibility` can be
    overridden by an element's children. Drop the option when the guide names none.
  - Use specific locators: a generic `locator('table').last()` can match an off-layout
    table.
- **Read every PNG back** with the Read tool before uploading. Check the crop, and that no
  floating widget, toast or spinner got in. Name files `NN-slug.png` in display order.

## 5. Upload through GitHub's editor

This section is GitHub's mechanism (the default forge). On another forge the shape is the
same — upload through the review request's own comment editor, copy the image markup it
inserts, never submit the comment — with that editor's controls in place of GitHub's.

GitHub has no API for attaching images to a PR body. Its editor's upload is the only route,
and it stores images under the repository's own access control
(`https://github.com/user-attachments/assets/…`, visible only to people who can see the
repo when it is private).

- The browser profile must be signed in to GitHub — usually a headed (visible) profile the
  user signed in to once. Open the PR in your tab. A 404 on a private repo, or a "Sign in to
  comment" prompt, means the profile isn't signed in: **stop and ask the user to sign in** in
  that browser window. Never open the login page or type GitHub credentials yourself; it's
  the user's account.
- Upload into the PR's new-comment box at the foot of the Conversation tab:
  1. Click the button named "Paste, drop, or click to add files", under the textbox named
     "Comment". It opens a file chooser.
  2. Call `browser_file_upload` with every PNG at once. Pass absolute paths under the main
     checkout's `.playwright-mcp/`; the MCP refuses paths outside the project.
  3. Poll the textbox's `inputValue()` until it holds one `user-attachments/assets/` URL per
     file and no "Uploading…" placeholder. GitHub inserts one
     `<img width height alt="<file name>" src="…">` tag per file, in upload order.
  4. Clear it with `fill('')` and check the Comment button is disabled again. **Never submit
     the comment**: the images belong in the body. Clearing matters too, because GitHub
     keeps unsent comment drafts per browser.
- Copy those `<img>` tags into the section unchanged. GitHub scales anything wider than the
  column (about 780px) down to fit.

## 6. Write the section into the body

The section goes after "What changed" (or before "How to review this" when there is no
"What changed"). Its shape:

```markdown
## Screenshots

Captured at `<sha7>`, 1280px viewport, seeded fixture data.

**Settings → Developers, below API keys**: the new Webhook endpoints table, with per-podcast and all-podcast endpoints, one disabled.

<img width="991" height="493" alt="01-developers-webhooks" src="https://github.com/user-attachments/assets/…" />

- With no endpoints, the section shows "<Workspace> has not created any webhook endpoints yet"; at five it replaces Add webhook with "Webhook limit reached (5)".
```

Give each image one bold location label and a one-line caption, and keep lines unwrapped
like the rest of the body. Replace the section wholesale, every time:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/forge.sh get-body <n> > <scratch>/pr-body.md
python3 - <scratch>/pr-body.md <scratch>/screenshots-section.md <<'PY'
import re, sys
body_path, section_path = sys.argv[1:3]
body = open(body_path).read().rstrip('\n') + '\n'  # the read appends a newline; don't let each refresh add one
section = open(section_path).read().strip() + '\n\n'
current = re.compile(r'^## Screenshots\n.*?(?=^## |^(Closes|Part of) |\Z)', re.S | re.M)
if current.search(body):
    body = current.sub(lambda m: section, body, count=1)
else:
    anchor = re.search(r'^(## (How to review this|Testing|Risk and rollout|Out of scope)\b|(Closes|Part of) )', body, re.M)
    body = body[: anchor.start()] + section + body[anchor.start() :] if anchor else body.rstrip() + '\n\n' + section
open(body_path, 'w').write(body)
PY
${CLAUDE_PLUGIN_ROOT}/scripts/forge.sh set-body <n> <scratch>/pr-body.md
```

Fetch the body immediately before patching, since another session may have edited it. Then
diff the patched file against what you fetched: the only change should be the section.
After patching, reload the PR in your tab and check every section image has
`naturalWidth > 0`. They are served from `private-user-images.githubusercontent.com` with a
signed token, so they render only for people who can see the repo.

## 7. After follow-up pushes

Any later push that changes pictured UI (a fix round, a review response, a rebase that
alters the UI) repeats §3–§6 for the new head, and the "Captured at" SHA moves with it.
Recapture every shot, not just the changed ones, so the whole set matches one commit. Pushes
that leave the UI alone leave the section alone.

## 8. Tear down

Tear the stack down as the project guide describes, using the SHA you booted, not
`origin/<branch>`: after the next push that ref names a different commit, and the old stack
would keep running. Then close your tab and delete `.playwright-mcp/pr-<branch-slug>/`: the
uploaded copies are the record.
