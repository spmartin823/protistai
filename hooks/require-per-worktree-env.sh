#!/usr/bin/env bash
#
# gifhub PreToolUse gate for the Task (subagent dispatch) tool.
#
# Parallel bug-hunt subagents each need an ISOLATED per-worktree copy of the app.
# This hook makes that non-negotiable: once a bug-hunt is active, it blocks
# subagent dispatch until get-or-create-per-worktree-dev-env has verified
# isolation and written its marker.
#
# Good plugin citizenship: this is a NO-OP unless a bug-hunt is active. It never
# interferes with a user's own subagent use in their repo.
#
# Two-key scoping (state lives in a temp dir keyed by repo root, not the repo):
#   - bug-hunt-active     : touched by the bug-hunt skill before it parallelizes
#   - per-worktree-env.json : written by get-or-create-per-worktree-dev-env on a
#                             VERIFIED isolated env
#
set -euo pipefail

# Consume the PreToolUse JSON on stdin (we don't need fields from it).
cat >/dev/null 2>&1 || true

# Resolve the worktree root EXACTLY as the skill does (must stay in sync).
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
root="$(cd "$proj" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)" || root="$proj"
state="${TMPDIR:-/tmp}/gifhub/$(printf '%s' "$root" | cksum | cut -d' ' -f1)"

# Not in a gifhub bug-hunt → never interfere.
[ -f "$state/bug-hunt-active" ] || exit 0

# Isolation already verified → allow the fan-out.
[ -f "$state/per-worktree-env.json" ] && exit 0

# Bug-hunt active but no verified isolated env → deny and explain.
cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"gifhub: parallel bug-hunt subagents need a verified per-worktree dev env, but none has been verified for this worktree. Invoke the get-or-create-per-worktree-dev-env skill first — it stands up an isolated app per worktree (own port, data, auth), proves the isolation, and writes the marker this gate checks. If isolation is impossible for this repo, run the bug hunt single-threaded instead of dispatching Task subagents."}}
JSON
exit 0
