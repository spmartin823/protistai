---
name: get-or-create-per-worktree-dev-env
description: Use when a skill is about to parallelize work across git worktrees or subagents and needs each one to run its own copy of the app without colliding (port clashes, shared DB/state, leaking auth). Also use to bootstrap per-worktree isolation in a repo that doesn't have it yet. Returns a contract describing how to boot an isolated app per worktree.
---

# get-or-create-per-worktree-dev-env

## Overview

Parallel debugging only works if each git worktree can boot its **own isolated
copy of the app** — its own port, its own data/DB/state, its own auth — so
agents working in parallel never collide. This skill **gets** that capability if
the repo already has it, or **creates** it (with real isolation testing) if it
doesn't, and returns a **contract** the caller uses to bring up an isolated app.

**Core principle: never report success you didn't prove.** A per-worktree env
counts as working only after two worktrees have run side by side and demonstrated
port, data, auth, and lifecycle isolation. Config that *looks* right is not a
verified env.

## When to use

- A skill (e.g. `bug-hunt`) is about to fan out across worktrees/subagents.
- Symptoms that mean isolation is missing: two instances fight over a port,
  parallel runs see each other's data, one login appears in another worktree,
  killing one instance takes down another.
- A repo has no per-worktree story at all and you need to add one.

**When NOT to use:** running against production, or single-threaded work in one
worktree. No isolation needed — skip this.

## The contract this skill returns

On success, return (and persist) a small contract the caller can act on:

- **Boot command** for an isolated instance, in both modes:
  - **Conductor mode** (user-driven, cross-workspace): the `scripts.run`
    command on `$CONDUCTOR_PORT`. URL: `http://localhost:$CONDUCTOR_PORT`.
  - **Worktree mode** (agent-driven, subagent fan-out in one workspace):
    `scripts/worktree-env.sh up` → prints `BASE_URL`; `down` to tear down.
- **`run_mode`** (`concurrent` when isolation is proven).
- **Which isolation dimensions passed** (port / data / auth / lifecycle).

If any dimension genuinely cannot be isolated, say so explicitly and tell the
caller to run **single-threaded** — never imply isolation that isn't there.

## Procedure

### 0. Compute the state dir (used by step 4 and the enforcement hook)

Both this skill and `hooks/require-per-worktree-env.sh` must agree on one path.
Use exactly this derivation:

```bash
gifhub_state_dir() {
  local proj root
  proj="${CLAUDE_PROJECT_DIR:-$PWD}"
  root="$(cd "$proj" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)" || root="$proj"
  printf '%s/gifhub/%s' "${TMPDIR:-/tmp}" "$(printf '%s' "$root" | cksum | cut -d' ' -f1)"
}
STATE="$(gifhub_state_dir)"; mkdir -p "$STATE"
```

### 1. Detect — check for a Conductor setup first (the "get" path)

Look, in order, for an existing per-worktree story:

1. **Conductor** — `.conductor/settings.toml` (read from the **root checkout**,
   not a workspace worktree: `dirname "$(git rev-parse --path-format=absolute --git-common-dir)"`),
   or legacy `conductor.json`.
2. **gifhub** — a `gifhub.toml` at the repo root from a previous run.
3. **A prior** `scripts/worktree-env.sh`.

An existing config **qualifies** only if it boots the app on a configurable port
(`$CONDUCTOR_PORT`), declares `run_mode = "concurrent"`, and isolates
data/state/auth. If it qualifies → go straight to **step 3 (Verify)**. If it's
partial (e.g. concurrent but a shared DB) → treat it as **create/upgrade**.

### 2. Create — follow Conductor's schema

First investigate the real local dev loop: README, package manager + lockfile,
`Procfile`/`docker-compose`/`Makefile`, `.env.example`, the database, and any
hard-coded ports. Use the `conductor:conductor` skill for the exact settings
schema and `CONDUCTOR_*` variables. Then emit **one** "boot-isolated on
`(PORT, DATA_DIR)`" routine with two entry points:

1. **Config file (Conductor schema).** Write `[scripts]` `setup` / `run`
   (app on `$CONDUCTOR_PORT`, companions on `$CONDUCTOR_PORT+1..9`) /
   `run_mode = "concurrent"`, plus `.worktreeinclude` or `file_include_globs`
   for static gitignored files (`.env*`).
   - **If the repo already uses Conductor** (a `.conductor/` exists): write
     `.conductor/settings.toml` to the **root checkout** so Conductor reads it.
   - **Otherwise: write `gifhub.toml` at the repo root** — same Conductor repo
     schema, so it's drop-in (`cp gifhub.toml .conductor/settings.toml` adopts
     Conductor later). Do **not** create a `.conductor/` the repo didn't ask for.
   - Validate: `npx -y @taplo/cli lint --schema https://conductor.build/schemas/settings.repo.schema.json <file>`.
2. **`scripts/worktree-env.sh`.** Adapt `worktree-env.template.sh` (bundled
   beside this skill) into the target repo. It is the agent-driven fallback that
   *emulates locally* what Conductor does — allocate a free port, make an
   isolated data dir/DB, isolate auth, run setup then the same boot command, wait
   for health, print `BASE_URL`. Keep its boot command in sync with the config
   file (the config is canonical). Add `.worktree-env` and `.worktree-data/` to
   the target repo's `.gitignore` (per-worktree runtime state, never committed).

### 3. Verify — prove isolation (lots of testing)

**REQUIRED:** Do not write the contract until this passes. Follow
`verification.md` (bundled beside this skill): stand up **two worktrees
concurrently** and assert the full matrix — distinct live ports, data written in
A absent from B, a session in A not authed in B, teardown of A leaves B healthy,
and the setup script runs clean from a fresh worktree. Run this with raw
`git worktree` + background processes — **never dispatch subagents from this
skill** (the enforcement hook would block them, and you'd deadlock). Loop:
fix the config/script and re-run until the matrix passes, or report the
dimension that can't be isolated and stop.

### 4. Record the contract

Only after step 3 passes, write the verified marker so the caller (and the hook)
can see it:

```bash
cat > "$STATE/per-worktree-env.json" <<'JSON'
{ "verified": true, "run_mode": "concurrent",
  "config_file": "gifhub.toml",
  "boot": { "conductor": "scripts.run on $CONDUCTOR_PORT",
            "worktree": "scripts/worktree-env.sh up" },
  "url_pattern": "http://localhost:<port>",
  "isolation": { "port": true, "data": true, "auth": true, "lifecycle": true } }
JSON
```

Then return the contract (above) as your final message.

## Quick reference

| Situation | Output |
|---|---|
| Repo already uses Conductor + qualifies | verify, refresh marker, return contract |
| Conductor present but partial | upgrade `.conductor/settings.toml` (root checkout) |
| No Conductor | create `gifhub.toml` (Conductor schema) + `scripts/worktree-env.sh` |
| Can't isolate a dimension | report it; tell caller to run single-threaded |

## Common mistakes

- **Writing `.conductor/settings.toml` into a repo that doesn't use Conductor.**
  Use `gifhub.toml` instead — same schema, non-invasive.
- **Editing `.conductor/settings.toml` in a workspace worktree.** Conductor reads
  it from the root checkout; changes in a worktree don't take effect until merged.
- **Declaring `run_mode = "concurrent"` without proving it.** Concurrency claims
  require the step-3 matrix to pass.
- **Dispatching subagents to do the verification.** The hook blocks Task until the
  marker exists; verify with raw worktrees + background processes instead.
- **Silent partial isolation.** A shared DB you can't parameterize is a
  single-threaded result, reported — not a pass.
