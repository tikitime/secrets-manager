---
name: secrets-migrate-repo
description: Convert one repo's plaintext .env files into 1Password items consumed via op:// references. Inventories env keys, creates 1P items for the secrets, writes a .env.template, wraps the boot command in op run, verifies the app still starts, then archives and deletes the plaintext. Run after /secrets-onboard.
---

# /secrets-migrate-repo

Migrate the current repo (or one the user names) off plaintext `.env*` onto 1Password-backed `op://` references. Invoke the `secrets-management` skill first. Load the user's config from `secrets-manager.local.md`; if missing, tell them to run `/secrets-onboard`.

**Golden rule:** delete plaintext ONLY after a successful boot-test. Keep an archived copy for rollback. Never paste any secret value into chat.

## Step 1 — Inventory

Find the repo's env files (`.env`, `.env.local`, `.env.production`, etc.). For each key, classify:

- **Secret** (API keys, tokens, passwords, connection strings with credentials, webhook URLs) → becomes a 1P item.
- **Non-secret config** (`NODE_ENV`, public URLs, public IDs, feature flags) → stays inline in the template.

Present the classification as a table and let the user correct it before proceeding.

## Step 2 — Create 1P items for the secrets

For each secret key, first **search** for an existing item that already holds this value (`op item list --vault "$OP_VAULT" --tags ...`) — if found, reuse it (add a project tag) rather than creating a duplicate. Otherwise create it with the helper:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib-op.sh"
```

Then per the CREATE flow in the skill (`op_create_secret`). The value is read from the existing `.env` programmatically WITHOUT printing it — e.g. extract into a variable and pass to the helper, never echo it. Name items `<KEY>_<PROJECT>_<ENV>`. Set `consumers` to at least `<repo>/.env.template:<KEY>`.

## Step 3 — Write `.env.template`

Create a checked-in `.env.template`: `op://` references for secrets, inline values for non-secrets.

```bash
ANTHROPIC_API_KEY=op://<VaultForRefs>/ANTHROPIC_API_KEY_MYAPP_PROD/credential
NODE_ENV=production
```

Note: the `op://` reference vault segment must match where the item lives. If the vault name has spaces, that's fine inside an `op://` URL but confirm references resolve in Step 5.

## Step 4 — Wrap the boot command

Update `package.json` (or Procfile, Makefile, etc.) so the app boots through `op run`:

```json
"start": "op run --env-file=.env.template -- <original start command>"
```

Leave compile-only scripts (`build`, `typecheck`, `lint`) unwrapped — they need no secrets.

## Step 5 — Boot-test

Run the wrapped start command. Confirm: the app starts, connects to its upstream services, and reports no missing-env errors. Also spot-check a reference resolves:

```bash
op run --env-file=.env.template -- printenv ANTHROPIC_API_KEY >/dev/null && echo "resolves OK"
```

(Do not print the value.) If anything fails, fix the template/item names — do NOT delete plaintext yet.

## Step 6 — Archive + delete plaintext

Only after a green boot-test:

```bash
mkdir -p .secrets-archive/$(date +%F)
mv .env .env.local .secrets-archive/$(date +%F)/ 2>/dev/null
```

Confirm `.secrets-archive/` and `.env*` are gitignored. Remove the plaintext from the working tree. Keep the archive locally for ~30 days as rollback insurance.

## Step 7 — Update .envrc / docs

If direnv was auto-loading `.env`, remove `dotenv .env` and leave a comment pointing at the `op run` pattern. Note in the repo README how to boot (`npm start` now runs through `op run`).

## Done

Report: N secrets moved to 1P, `.env.template` written, boot verified, plaintext archived + removed. Suggest committing `.env.template` + the `package.json` change (NOT the archive). Remind them new secrets use `/secrets-add`.
