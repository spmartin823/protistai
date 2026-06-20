# Verifying per-worktree isolation

The whole point of this skill is a per-worktree env that **actually** isolates.
"The config looks right" is not evidence. Prove it by running two worktrees at
once and watching them stay independent across every dimension below.

**Do this with raw `git worktree` + background processes — never subagents.** The
enforcement hook blocks `Task` until the verified marker exists, so a subagent
here would deadlock. Subagents come later, in the caller, after this passes.

## Setup: two live worktrees

```bash
ROOT="$(git rev-parse --show-toplevel)"
BR="$(git rev-parse --abbrev-ref HEAD)"
git worktree add -d "$ROOT/../wt-a" "$BR"
git worktree add -d "$ROOT/../wt-b" "$BR"

A="$(cd "$ROOT/../wt-a" && scripts/worktree-env.sh up)"   # prints BASE_URL for A
B="$(cd "$ROOT/../wt-b" && scripts/worktree-env.sh up)"   # prints BASE_URL for B
echo "A=$A  B=$B"
```

## The matrix — all five must pass

1. **Port isolation.** `A` and `B` are different URLs and both respond *at the
   same time*:
   ```bash
   [ "$A" != "$B" ] || { echo FAIL: same URL; exit 1; }
   curl -fsS -o /dev/null "$A" && curl -fsS -o /dev/null "$B" || { echo FAIL: not both live; exit 1; }
   ```

2. **Data isolation.** Create a record through A's app (sign up a user, add a
   row — use the app's real API/UI), then confirm it is **absent** in B. Read B
   fresh; do not reuse A's response. If B can see A's record, the data store is
   shared → not isolated.

3. **Auth isolation.** Log in against A and capture its session
   (cookie/token). Send that exact session to B. B must treat it as
   **unauthenticated**. Shared session/JWT signing state means a login in one
   worktree authenticates in another → not isolated.

4. **Lifecycle isolation.** Tear A down and confirm B is still healthy:
   ```bash
   ( cd "$ROOT/../wt-a" && scripts/worktree-env.sh down )
   curl -fsS -o /dev/null "$B" || { echo FAIL: B died with A; exit 1; }
   ```

5. **Cold-start cleanliness.** The setup ran from a *fresh* worktree with no
   pre-existing state (it did, above) — confirm `run_setup` created the DB/state
   it needed rather than depending on the root checkout's data.

## Teardown

```bash
( cd "$ROOT/../wt-b" && scripts/worktree-env.sh down ) || true
git worktree remove --force "$ROOT/../wt-a" 2>/dev/null || true
git worktree remove --force "$ROOT/../wt-b" 2>/dev/null || true
git worktree prune
```

## If a dimension fails

- **Port:** make the boot command honor `$PORT`/`$CONDUCTOR_PORT` instead of a
  hard-coded one; move companion services to `$CONDUCTOR_PORT+1..9`.
- **Data:** point the DB/state at `$DATA_DIR` (per-worktree sqlite file, a
  per-worktree Postgres database/schema, or a docker-compose project name keyed
  to the port). A single fixed shared DB that can't be parameterized = cannot
  isolate.
- **Auth:** key session/cookie storage and any signing secret to `$DATA_DIR` or
  the port, not a global location.
- **Lifecycle:** ensure each instance runs in its own process group and `down`
  only kills its own PID.

Fix, then re-run the whole matrix. Only when all five pass do you write the
verified marker (step 4 of the skill). If data or auth genuinely cannot be
parameterized, report it and tell the caller to run **single-threaded**.
