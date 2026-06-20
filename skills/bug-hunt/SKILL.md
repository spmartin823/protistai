---
name: bug-hunt
description: Walk the full user flow of a running web app like a real person, find bugs, fix them, and ship each fix as its own PR with before/after GIFs embedded inline. Use when asked to bug-hunt, QA-and-fix, or produce reviewable GIF-proof bug PRs for an app repo.
---

# bug-hunt

Go through the full user flow of this app (sign up, log in, the core features,
settings / configuration, and the obvious edge cases) and find bugs.

When you find a bug, record a GIF of the bug. Once you have fixed the bug,
reproduce the same bug **not** happening in a UI e2e test (the e2e harness is
already set up). Then record the UI of that e2e test as a GIF. The before and
after GIFs must be embedded **inline** in the PR for the bug, so non-technical
people can review the bug and see that it's fixed.

## Before you start — determine two things for this repo

1. **Env setup + App URL** — how to bring up an isolated instance for a worktree
   and reach it. Don't hand-roll this: invoke the
   `get-or-create-per-worktree-dev-env` skill, which gets or creates it and hands
   back the boot command + URL pattern (see *Parallelize across worktrees* below).
2. **E2E** — the command that runs the UI e2e suite (Playwright, Cypress, …),
   which must be able to record video (needed to produce the GIFs).

## Parallelize across worktrees

Use subagents in different git worktrees to parallelize exploration and fixes.
Each worktree brings up its own isolated copy of the app (its own port, DB/state,
and auth) so parallel agents never collide.

**Before you dispatch any subagent, guarantee that isolation exists.** Run this
once, from the repo root, then invoke the `get-or-create-per-worktree-dev-env`
skill:

```bash
# scope + freshen the per-worktree-env gate for this bug hunt
# (same state-dir derivation the skill and the enforcement hook use)
PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
ROOT="$(cd "$PROJ" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)" || ROOT="$PROJ"
STATE="${TMPDIR:-/tmp}/gifhub/$(printf '%s' "$ROOT" | cksum | cut -d' ' -f1)"
mkdir -p "$STATE"; rm -f "$STATE/per-worktree-env.json"; touch "$STATE/bug-hunt-active"
```

Then **invoke `get-or-create-per-worktree-dev-env`**. It returns a contract (the
isolated-boot command + URL pattern) — give that command to each subagent so it
brings up its own instance. A `PreToolUse` hook enforces this: subagent dispatch
is blocked until that skill has verified isolation. If the repo genuinely can't
isolate per worktree, the skill says so — then run **single-threaded** (don't
dispatch subagents).

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

The exact GIF-recording and inline-embed mechanics are in **`METHODOLOGY.md`**,
bundled alongside this skill. Read it before recording.
