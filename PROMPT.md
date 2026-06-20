# The debug step

Paste everything between the rules to the agent. Fill in the three repo specifics
(env setup, app URL, e2e command) — see the [README](README.md).

---

Go through the full user flow of the app (sign up, log in, the core features,
settings / configuration, and the obvious edge cases) and find bugs.

When you find a bug, record a gif of the bug. Once you have fixed the bug,
reproduce the same bug not happening in a UI e2e test (the e2e harness is already
set up). Then record the UI of that e2e test as a gif. The before and after gifs
should be in the PR for the bug so that non-technical people can review the bug
and see that it's fixed.

You can use subagents in different git worktrees to parallelize your exploration
+ fixes. Each worktree must bring up its **own isolated copy of the app** — its
own port, data/state, and auth — so parallel agents never collide. Get the repo's
per-worktree env setup if it has one; if it doesn't, create one (prefer
[Conductor](https://conductor.build)'s schema — a `gifhub.toml` with `[scripts]`
`setup`/`run` on a unique port and `run_mode = "concurrent"`) and **prove the
isolation with two worktrees side by side before relying on it**. If the repo
can't isolate per worktree, run single-threaded.

---

## Definition of done (per bug)

- **One PR per bug**, on its own branch.
- A UI **e2e test that fails on the buggy build and passes on the fix**, committed
  alongside the existing e2e suite (match its conventions).
- **`before.gif`** (the bug reproducing) and **`after.gif`** (the fix verified)
  embedded **inline in the PR body** — not as links. A non-technical reviewer
  should be able to scroll the PR and see both.
- A plain-language description: what the user sees go wrong, the root cause, and
  the minimal fix.

## Notes

- Prefer bugs on **deterministic surfaces** (forms, inputs, toggles, navigation)
  for stable e2e and clean GIFs.
- Keep fixes **minimal and atomic**. One bug, one fix, one PR.
- The exact recording + inline-embed mechanics are in
  [`METHODOLOGY.md`](skills/bug-hunt/METHODOLOGY.md). Read it before recording.
