# Methodology

How the agent turns "find bugs" into reviewable, proven PRs. These are the
mechanics that make it reliable. Commands are shown with **Playwright**; adapt
them to whatever UI e2e runner the target repo uses (any runner that can record
video works).

## 1. One spec produces both GIFs (TDD, RED → GREEN)

Write a single e2e spec that **asserts the fixed behavior**, then run it twice:

- against the **buggy** build → it **fails**, and the recording shows the bug
  (this is `before.gif`),
- against the **fix** → it **passes**, and the recording shows correct behavior
  (this is `after.gif`).

To capture both on one machine, stash the fix between runs:

```bash
# record BEFORE (buggy): revert just the fix, run, copy the video, restore
git stash push -- <fix-file>
<e2e command> <spec>          # fails — records the bug
cp <video-output>.webm /tmp/before.webm
git stash pop
# record AFTER (fixed): run again
<e2e command> <spec>          # passes — records the fix
cp <video-output>.webm /tmp/after.webm
```

Enable video recording **temporarily** (do NOT commit it). For Playwright:

```ts
use: { baseURL: process.env.E2E_BASE_URL, video: "on", viewport: { width: 1280, height: 800 } }
```

Convert webm → gif with ffmpeg (palette for quality; `tpad` freezes the last
frame so a fast-passing "after" lingers on the result):

```bash
ffmpeg -y -i in.webm -vf "fps=10,scale=760:-1:flags=lanczos,palettegen=stats_mode=diff" /tmp/pal.png
ffmpeg -y -i in.webm -i /tmp/pal.png \
  -lavfi "fps=10,scale=760:-1:flags=lanczos,tpad=stop_mode=clone:stop_duration=3[x];[x][1:v]paletteuse=dither=bayer" out.gif
```

## 2. Inline GIFs in the PR — even for a private repo

Do **not** rely on `raw.githubusercontent.com` (GitHub camo-proxies it and it
breaks for private repos), and do **not** use links.

Instead: **commit** the GIFs (e.g. `docs/qa-evidence/<bug>-before.gif`), then in
the PR body reference them with the first-party `?raw=true` blob URL:

```markdown
![before](https://github.com/<owner>/<repo>/blob/<COMMIT_SHA>/docs/qa-evidence/<bug>-before.gif?raw=true)
![after](https://github.com/<owner>/<repo>/blob/<COMMIT_SHA>/docs/qa-evidence/<bug>-after.gif?raw=true)
```

GitHub serves first-party `github.com` URLs through the **viewer's own
authenticated session** (no camo), so they render inline for anyone with repo
access. Use the **commit SHA**, not the branch name.

Verify it actually renders (don't assume):

```bash
gh api repos/<owner>/<repo>/pulls/<n> -H "Accept: application/vnd.github.html+json" \
  --jq .body_html | grep -c data-animated-image     # == number of GIFs
gh api repos/<owner>/<repo>/pulls/<n> -H "Accept: application/vnd.github.html+json" \
  --jq .body_html | grep -c camo.githubusercontent  # must be 0
```

A `curl` of the `?raw=true` URL with a PAT returns 404 — that's expected (the web
endpoint uses session cookies, not tokens) and does **not** mean it's broken in
the browser.

## 3. Reliable e2e: prefer deterministic surfaces

Build regression specs around forms, inputs, toggles, tabs, and navigation —
they're synchronous and reproducible. Async- or AI-driven UI (e.g. streaming
chat) is slow and nondeterministic; only encode it in e2e when the bug genuinely
lives there, and give it long timeouts.

Read 1–2 existing specs first and match their conventions (fresh fixture/login,
selectors, helpers).

## 4. Parallelize across worktrees (the per-worktree environment requirement)

Spawn subagents, each in its **own git worktree**. Each worktree runs the repo's
**per-worktree environment setup** to bring up an **isolated copy of the app** —
its own dev-server port, isolated DB/state, and isolated auth — so agents
exploring and fixing different bugs never collide.

- With [Conductor](https://conductor.build): each workspace provisions its own
  stack automatically.
- Without it: `git worktree add ../wt-<bug>` + the repo's setup script that
  parameterizes the port and data directory per worktree.

One bug → one worktree → one branch → one PR. If the repo can't isolate
environments per worktree, run single-threaded instead.

## 5. PR hygiene

- One bug per PR; minimal, atomic fix commit.
- Commit the e2e regression test (it stays; the temporary video config does not).
- Lead the PR with the plain-language symptom and the two GIFs, then root cause
  and the fix.
