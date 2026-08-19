---
name: secrets-add
description: Add one new secret — search 1Password for an existing item first, otherwise create a new item with all mandatory rotation/consumer fields, then wire an op:// reference into the consuming repo's .env.template. Use when storing a new API key, token, password, or connection string.
---

# /secrets-add

Store one new secret in 1Password and wire it for consumption. Invoke the `secrets-management` skill first. Load config from `secrets-manager.local.md`; if missing, run `/secrets-onboard`.

**Never display, paste, or log the value.** The user enters it via `read -rs` in their terminal, or it comes from `op read` if it already exists elsewhere.

## Step 1 — Search first (avoid duplicates)

```bash
op item list --vault "$OP_VAULT" --tags global
op item list --vault "$OP_VAULT" --tags <project>,<env>
```

If the same value already exists in an item, DON'T create a copy — add the new project tag to the existing item (see the "add a tag" pattern in `${CLAUDE_PLUGIN_ROOT}/skills/secrets-management/references/rotation.md`) and skip to Step 3.

## Step 2 — Create the item

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib-op.sh"

ITEM_NAME="<KEY>_<PROJECT>_<ENV>"   # e.g. STRIPE_API_KEY_MYAPP_PROD
read -rs VALUE                       # silent paste
TAGS="<project>,<env>,<rotation-class>,<lifecycle>"   # e.g. myapp,prod,readonly-api,manual_rotate_only
CADENCE_DAYS=180                     # 90 prod-phi-payment | 180 readonly-api | 365 local-dev
METHOD=manual                        # auto only if you have a rotate script
ROT_CLASS=readonly-api
CONSUMERS="<repo>/.env.template:<ENV_VAR>"
NOTES="Origin: <where it came from>, minted $(date +%F)"
op_create_secret
unset VALUE
```

Confirm the item was created (the helper prints the new id). Ask the user for the cadence/class if you're unsure — don't guess for production keys.

## Step 3 — Wire the consumer

Add the reference to the repo's `.env.template`:

```
<ENV_VAR>=op://<Vault>/<ITEM_NAME>/credential
```

If the app is running, remind them it picks up the new value on next boot through `op run`.

## Step 4 — Verify

```bash
op read "op://<Vault>/<ITEM_NAME>/credential" >/dev/null && echo "resolves OK"
```

(Don't print the value.)

## Done

Report: item created (or tag added to existing), reference wired, resolution verified. The rotation reminder will track it automatically from its cadence.
