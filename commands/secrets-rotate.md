---
name: secrets-rotate
description: Rotate one secret — mint a new value upstream, update the 1Password item (value, hash, last_rotated_at, rotation_count), update consumers, verify, and revoke the old value. Use when rotating a credential on schedule, after a leak, or when closing a rotation task.
---

# /secrets-rotate

Rotate one secret end-to-end. Invoke the `secrets-management` skill first. Load config from `secrets-manager.local.md`. **Never display the old or new value.**

Ask which item to rotate (or take it from the rotation task that triggered this). Then:

## Step 1 — Mint the new value upstream

Walk the user through generating a new value in the platform's console/API (or, for an auto-rotatable platform, point them at `${CLAUDE_PLUGIN_ROOT}/skills/secrets-management/references/engine.md` and the relevant `rotate-*.sh`). The user pastes the new value via silent stdin in the next step.

## Step 2 — Update the 1P item

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib-op.sh"
ITEM_NAME="<the item>"
read -rs NEW_VALUE      # silent paste of the freshly-minted value
op_rotate_secret        # updates credential + value_hash_prefix + last_rotated_at + rotation_count++
unset NEW_VALUE
```

## Step 3 — Update consumers

Read the item's `consumers` field and update each downstream that holds a mirror (re-deploy, re-sync, or re-run the app so `op run` picks up the new value):

```bash
op item get "$ITEM_NAME" --vault "$OP_VAULT" --fields label=consumers
```

For deployed apps with mirrored secrets (GitHub Actions / Vercel / Cloudflare), the consumers field tells you what to update by hand (v1 doesn't auto-sync — see `${CLAUDE_PLUGIN_ROOT}/skills/secrets-management/references/engine.md`).

## Step 4 — Verify

Confirm the new value works (app boots, integration call succeeds, `op read` resolves). Don't print the value.

## Step 5 — Revoke the old value

Revoke/delete the old value in the upstream console so it can no longer be used.

## Step 6 — Close out

If this rotation was triggered by a leak, remove the `needs_rotation` tag (keep `leaked_<date>` as history). If a Notion rotation task exists for this item, mark it done.

## Done

Report: new value live, consumers updated, old value revoked, task closed. The next due date is recomputed automatically from the bumped `last_rotated_at`.
