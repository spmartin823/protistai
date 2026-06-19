---
description: Walk the full app flow, find bugs, fix them, and ship each as a PR with inline before/after GIFs
---

Go through the full user flow of this app (sign up, log in, the core features,
settings / configuration, and the obvious edge cases) and find bugs.

When you find a bug, record a GIF of the bug. Once you have fixed the bug,
reproduce the same bug **not** happening in a UI e2e test (the e2e harness is
already set up). Then record the UI of that e2e test as a GIF. The before and
after GIFs must be embedded **inline** in the PR for the bug, so non-technical
people can review the bug and see that it's fixed.

Use subagents in different git worktrees to parallelize exploration and fixes.
Each worktree brings up its own isolated copy of the app by running the repo's
per-worktree environment setup (its own port, DB/state, and auth). If the repo
can't isolate environments per worktree, run single-threaded.

Before starting, determine three things for this repo: the per-worktree env
setup command, how to reach the running app (URL/port), and the e2e command
(which must be able to record video).

Definition of done per bug: one PR, on its own branch, with a failing-then-passing
e2e test committed, before+after GIFs inline in the PR body, and a plain-language
description of the symptom, root cause, and minimal fix.

Follow `docs/METHODOLOGY.md` for the exact GIF-recording and inline-embed
mechanics, and `PROMPT.md` for the full brief.
