#!/usr/bin/env bash
#
# worktree-env.sh — bring up an ISOLATED copy of this app for the current git
# worktree, so parallel agents never collide.
#
# This is a TEMPLATE. The get-or-create-per-worktree-dev-env skill adapts it into
# the target repo at scripts/worktree-env.sh:
#   - fill in run_setup() and run_app() with this repo's real commands
#   - keep them in sync with the [scripts] in .conductor/settings.toml / gifhub.toml
#     (that config is canonical; this script just emulates Conductor locally)
#
# It mirrors what Conductor gives each workspace: a unique port range, an isolated
# data dir, and isolated auth — but driven by an agent inside one workspace so a
# single agent can fan subagents out across worktrees.
#
# Usage:
#   scripts/worktree-env.sh up     # boot isolated, print BASE_URL, write .worktree-env
#   scripts/worktree-env.sh url    # print BASE_URL for the running instance
#   scripts/worktree-env.sh down   # stop the instance and clean its data
#
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ENV_FILE="$ROOT/.worktree-env"          # gitignore this
DATA_DIR="$ROOT/.worktree-data"         # per-worktree, isolated; gitignore this
PORT_LOCKS="${TMPDIR:-/tmp}/gifhub-ports"   # cross-worktree atomic port registry

# --- helpers ---------------------------------------------------------------

# True if something is already listening on $1 (pure-bash, no deps).
port_in_use() {
  (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && { exec 3>&- 3<&-; return 0; }
  return 1
}

# Claim a free port WITHOUT a time-of-check/time-of-use race. Picking a port and
# closing the socket before the app binds lets two concurrent worktrees grab the
# same port; instead we atomically reserve it with `mkdir` (succeeds for exactly
# one caller) and hold the reservation until `down`.
#
# We deliberately do NOT use $CONDUCTOR_PORT here: it is one value per Conductor
# *workspace*, but this script stands up MANY worktrees inside one workspace for
# subagent fan-out — they would all collide on it. $CONDUCTOR_PORT belongs to the
# canonical config (.conductor/settings.toml / gifhub.toml) where scripts.run uses
# it for Conductor's own one-instance-per-workspace run.
claim_port() {
  mkdir -p "$PORT_LOCKS"
  local p
  for p in $(seq "${GIFHUB_PORT_MIN:-20000}" "${GIFHUB_PORT_MAX:-20500}"); do
    if mkdir "$PORT_LOCKS/$p" 2>/dev/null; then        # atomic across processes
      if port_in_use "$p"; then rmdir "$PORT_LOCKS/$p" 2>/dev/null || true; continue; fi
      echo "$p"; return 0
    fi
  done
  echo "worktree-env: no free port in range" >&2; return 1
}

wait_for_http() {
  local url="$1" tries="${2:-60}"
  for _ in $(seq 1 "$tries"); do
    if curl -fsS -o /dev/null "$url" 2>/dev/null; then return 0; fi
    sleep 1
  done
  echo "worktree-env: app never became healthy at $url" >&2
  return 1
}

# --- repo-specific bits (FILL THESE IN) ------------------------------------

# Install deps / generate files / init this worktree's isolated DB. Receives an
# isolated DATA_DIR and PORT in the environment. Must be idempotent.
run_setup() {
  : # e.g. pnpm install ; pnpm prisma migrate deploy
}

# Start the app in the background on $PORT with $DATA_DIR as its only state, and
# echo its PID. Auth/session storage MUST live under $DATA_DIR (or a per-port
# key) so logins don't leak across worktrees.
run_app() {
  : # e.g. PORT="$PORT" DATABASE_URL="sqlite:$DATA_DIR/app.db" pnpm start >"$DATA_DIR/app.log" 2>&1 & echo $!
}

# Health-check URL once the app is up.
health_url() { echo "$BASE_URL"; }

# --- commands --------------------------------------------------------------

cmd_up() {
  PORT="$(claim_port)"
  BASE_URL="http://localhost:$PORT"
  export PORT BASE_URL DATA_DIR
  mkdir -p "$DATA_DIR"

  run_setup
  PID="$(run_app)"

  if ! wait_for_http "$(health_url)"; then
    echo "--- last app log ---" >&2; tail -n 20 "$DATA_DIR/app.log" 2>/dev/null >&2 || true
    kill "$PID" 2>/dev/null || true
    rmdir "$PORT_LOCKS/$PORT" 2>/dev/null || true
    return 1
  fi

  {
    echo "BASE_URL=$BASE_URL"
    echo "PORT=$PORT"
    echo "PID=$PID"
    echo "DATA_DIR=$DATA_DIR"
  } >"$ENV_FILE"

  echo "$BASE_URL"
}

cmd_url() {
  # shellcheck disable=SC1090
  [ -f "$ENV_FILE" ] && . "$ENV_FILE" && echo "$BASE_URL"
}

cmd_down() {
  if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    [ -n "${PID:-}" ] && kill "$PID" 2>/dev/null || true
    # release the atomic port reservation
    [ -n "${PORT:-}" ] && rmdir "$PORT_LOCKS/$PORT" 2>/dev/null || true
    rm -f "$ENV_FILE"
  fi
  rm -rf "$DATA_DIR"
}

case "${1:-}" in
  up)   cmd_up ;;
  url)  cmd_url ;;
  down) cmd_down ;;
  *)    echo "usage: $0 {up|url|down}" >&2; exit 2 ;;
esac
