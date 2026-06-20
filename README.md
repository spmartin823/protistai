# gifhub

An autonomous QA bug-hunt harness for **any web-app repo**.

Point a coding agent at your app; it walks the **entire user flow like a real
person**, hunts for bugs, and for every bug it finds it:

1. **records a GIF of the bug happening**,
2. **fixes it**,
3. **proves the fix with a UI end-to-end test**,
4. **records a GIF of that e2e test passing**, and
5. **opens a PR for the bug with the before + after GIFs embedded inline**, so a
   non-technical reviewer can watch the bug, then watch it disappear — without
   reading a line of code.

## Install as a Claude Code plugin

gifhub ships as a Claude Code plugin, so you can drop these skills into **any**
repo:

```
/plugin marketplace add press-pass/gifhub
/plugin install gifhub
```

That installs three skills — [`bug-hunt`](skills/bug-hunt/SKILL.md) (find + fix +
GIF PRs), [`prod-bug-report`](skills/prod-bug-report/SKILL.md) (report-only), and
[`get-or-create-per-worktree-dev-env`](skills/get-or-create-per-worktree-dev-env/SKILL.md)
(the isolation helper `bug-hunt` leans on) — plus the
[`/bug-hunt`](commands/bug-hunt.md) slash command. The skills auto-trigger when
you ask an agent to hunt for bugs. Run `/plugin update gifhub` to pull changes. To
try it without installing, from a clone:

```
claude --plugin-dir /path/to/gifhub
```

## Requirement: per-worktree environments

gifhub parallelizes by running subagents in **separate git worktrees**, each
with its **own isolated, running copy of the app**. So the one thing your repo
needs is a way to **stand up an isolated environment per worktree** — a command
that boots the app on a unique port with isolated data / state / auth, so parallel
agents never collide.

You don't have to build this by hand. The
[`get-or-create-per-worktree-dev-env`](skills/get-or-create-per-worktree-dev-env/SKILL.md)
skill **gets it if your repo already has it, or creates it if it doesn't** —
checking for a [Conductor](https://conductor.build) setup first (per-workspace
provisioning out of the box), and otherwise writing a `gifhub.toml` in Conductor's
schema plus a `scripts/worktree-env.sh` runner. It then **proves** the isolation
(two worktrees side by side: distinct ports, isolated data, isolated auth) before
declaring success. `bug-hunt` invokes it automatically before fanning out, and a
hook blocks the fan-out until isolation is verified. If a repo genuinely can't
isolate per worktree, gifhub runs single-threaded.

## Point it at your repo

Tell the agent (or bake into the prompt):

1. **Env setup + App URL** — usually nothing to do: `get-or-create-per-worktree-dev-env`
   gets-or-creates the isolated per-worktree env and returns the boot command +
   URL. Point it at an existing setup command if you already have one.
2. **E2E** — the command that runs the UI e2e suite (Playwright, Cypress, …), and
   the fact that it can record video (needed to produce the GIFs).

## The debug step

The [`bug-hunt`](skills/bug-hunt/SKILL.md) skill is the full brief. With the
plugin installed it runs as the [`/bug-hunt`](commands/bug-hunt.md) slash command
or auto-triggers when you ask an agent to hunt for bugs. [`PROMPT.md`](PROMPT.md)
carries the same brief as a copy-paste prompt for agents without the plugin.

## Report-only mode

Want bug reports without fixes — e.g. run against **production** — instead of
fix-and-PR? The [`prod-bug-report`](skills/prod-bug-report/SKILL.md) skill
walks the live app's flows like a user and writes each bug up with reproduction
steps (`steps:` / `expected behavior:` / `actual behavior:`). No code changes; it
just produces reports.

## How it works

The mechanics that make the GIFs reproducible and the e2e reliable are in
[`METHODOLOGY.md`](skills/bug-hunt/METHODOLOGY.md), bundled with the `bug-hunt`
skill:

- one e2e spec produces **both** GIFs — before (run against the buggy build,
  fails) and after (run against the fix, passes),
- GIFs embed **inline in the PR body even for private repos**, via committed
  `?raw=true` image URLs,
- favor **deterministic UI surfaces** for stable e2e (forms, inputs, toggles)
  over async/AI-driven UI,
- **one bug per worktree → one PR**.
