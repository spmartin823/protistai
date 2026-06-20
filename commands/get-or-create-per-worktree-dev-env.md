---
description: Get or create a verified per-worktree dev environment (isolated app per worktree) so agents can parallelize safely
---

Use the **get-or-create-per-worktree-dev-env** skill to guarantee this repo can
boot an isolated copy of the app per git worktree — its own port, data/state, and
auth — checking for a Conductor setup first and creating one (Conductor schema) if
missing. Verify the isolation before reporting success, then return the boot
contract. Follow the skill exactly.

$ARGUMENTS
