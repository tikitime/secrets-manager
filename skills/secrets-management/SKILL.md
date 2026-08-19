---
name: secrets-management
description: Move plaintext .env secrets into 1Password and consume them via op:// references, then keep them rotated. Use when the user wants to "set up secrets", "move secrets to 1Password", "migrate a .env file", "add a secret", "store an API key", "rotate a credential", "stop committing secrets", "get off plaintext env files", or asks how this plugin's onboarding / migration / rotation works. Shared mental model + op-CLI reference behind the /secrets-onboard, /secrets-migrate-repo, /secrets-add, /secrets-rotate, and /secrets-rotation-check commands.
---

# Secrets Management

This skill teaches one pattern: **every secret lives as one 1Password item; apps read it at runtime via `op://` references; nothing sensitive sits in a plaintext file.** It is account-agnostic — it reads your personal setup from a config file (see below), so the same plugin works for anyone with their own 1Password account.

## Read the per-user config first

Before running any `op` command, load the user's settings from `secrets-manager.local.md` at the **project root** of wherever they're working (the file the `/secrets-onboard` command writes). It has YAML frontmatter:

```yaml
op_account: <their 1Password account, e.g. myteam.1password.com>
op_vault: <their vault name — ASK, never assume; quote it, it may contain spaces>
notion_tasks_db: <their Notion database id for rotation tasks>
notion_assignee: <their Notion user id>
enable_discord: false
```

- If the file is missing, the user hasn't onboarded — run `/secrets-onboard` first.
- **Always quote the vault** in `op` commands: `--vault "$OP_VAULT"`. Vault names like `Developer Vault - Jordan` contain spaces and a hyphen; unquoted they break.
- Never print the config's values back into chat beyond what's needed to confirm an action.

## The journey (three phases → three+ commands)

| Phase | Command | What it does |
|-------|---------|--------------|
| 1. Onboard (once) | `/secrets-onboard` | Install + authenticate `op`, set up the Keychain bootstrap, then ask for account/vault/Notion config and write `secrets-manager.local.md`. |
| 2. Migrate a repo | `/secrets-migrate-repo` | Convert a repo's plaintext `.env*` into 1Password items + a `.env.template` of `op://` refs + an `op run` boot wrap, verify it boots, delete the plaintext. |
| 3a. Add a secret | `/secrets-add` | Create one new 1Password item with all the mandatory fields, then wire an `op://` reference. |
| 3b. Rotate a secret | `/secrets-rotate` | Mint a new value upstream, update the 1P item, verify, revoke the old. |
| 3c. Check rotations | `/secrets-rotation-check` | Find secrets past their cadence and file a Notion task (assigned to you) for each. |

## The mental model

- ✅ **One unique secret VALUE = one 1P item.** Shared across repos? One item, multiple project tags — never copies (copies drift).
- ✅ **Apps read secrets at boot** via `op run --env-file=.env.template -- <command>`, which resolves `op://` references into the process environment. Values live only in that process, never on disk.
- ❌ **No plaintext secrets in `.env*`.** A repo keeps a checked-in `.env.template` of `op://` references; non-secret config (URLs, `NODE_ENV`, public IDs) stays inline.
- ❌ **Never paste a secret value into chat, tool inputs, or a commit.** The user types values via `read -rs` (silent stdin) in their own terminal, or pulls from `op read`.

## ⚠️ The zsh glob footgun (real leak vector)

zsh treats `credential[concealed]=$VALUE` as a glob pattern. It fails with "no matches found" AND echoes the resolved argument — including the secret — to stderr. This is exactly how a webhook leaked during the original migration. **Mitigation, used everywhere in this plugin: always quote the field assignment** (`"credential[concealed]=$VALUE"`), which is safe in both bash and zsh. The shipped helpers in `${CLAUDE_PLUGIN_ROOT}/scripts/lib-op.sh` already do this — prefer them over hand-writing `op item create`.

## op CLI: create vs update

Two shapes. Pick the right one.

**CREATE** — brand-new item. First **search** (`op item list --vault "$OP_VAULT" --tags <project>`) — if this value already lives in an item, add a tag instead of minting a copy (see `references/rotation.md` → "Add a tag"). Otherwise use the helper:

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib-op.sh"
ITEM_NAME="ANTHROPIC_API_KEY_MYAPP_PROD"
read -rs VALUE            # paste value, press enter — not echoed, not in history
TAGS="myapp,prod,readonly-api,manual_rotate_only"
CADENCE_DAYS=180; METHOD=manual; ROT_CLASS=readonly-api
CONSUMERS="myapp/.env.template:ANTHROPIC_API_KEY"
NOTES="Origin: console.anthropic.com, minted $(date +%F)"
op_create_secret          # reads OP_VAULT from config; fully quoted
unset VALUE
```

**UPDATE** — item exists (rotate value, add a tag, fix a field). `op item edit` preserves anything you don't pass.

```bash
# rotate a value (helper bumps rotation_count + last_rotated_at + hash):
ITEM_NAME="ANTHROPIC_API_KEY_MYAPP_PROD"; read -rs NEW_VALUE; op_rotate_secret; unset NEW_VALUE

# add a tag (tags REPLACE on edit — read existing, append):
EXISTING=$(op item get "$ITEM_NAME" --vault "$OP_VAULT" --format json | jq -r '.tags | join(",")')
op item edit "$ITEM_NAME" --vault "$OP_VAULT" --tags "${EXISTING},newproject"
```

Full lexicon (rename, edit-by-id, archive, notesPlain append, field reference table) is in `${CLAUDE_PLUGIN_ROOT}/skills/secrets-management/references/rotation.md`.

## Naming convention

`<KEY_NAME>_<PROJECT_HINT>[_<ENV>]` — e.g. `SUPABASE_SERVICE_ROLE_KEY_MYAPP_PROD`. A globally-unique key needs no suffix (`ANTHROPIC_API_KEY`). The project hint routes; the env (`PROD`/`STAGING`/`DEV`) scopes rotation urgency.

## Tags (four axes)

| Axis | Example values | Purpose |
|------|----------------|---------|
| Project | `myapp`, `global` | Routing. `global` = broadly useful; search it first for a new project. |
| Environment | `prod`, `staging`, `dev`, `local` | Rotation cadence + urgency. |
| Rotation class | `prod-phi-payment` (90d), `readonly-api` (180d), `local-dev` (365d), `no_rotation` | Drives the due-date math. |
| Lifecycle | `auto_rotate_eligible`, `manual_rotate_only`, `needs_rotation`, `leaked_<YYYY-MM-DD>` | Drives the rotation reminder + leak handling. |

## Mandatory fields on every item

`credential` + `value_hash_prefix` (SHA256 first 12) + `created_at` + `last_rotated_at` + `rotation_count` + `rotation_cadence_days` + `rotation_class` + `rotation_method` + `rotation_runbook_url` (optional; set `RUNBOOK_URL` before `op_create_secret`, or empty) + `consumers` (semicolon-separated sync targets) + `notesPlain`. The create helper sets all of them.

## Rotation

Cadence comes from `rotation_class`. `rotation-check.py` computes `last_rotated_at + rotation_cadence_days`; anything past due gets a **Notion task assigned to you**. Manual rotations follow the upstream's revoke/mint flow (see `references/rotation.md`); a few platforms support automated mint-and-revoke (`references/engine.md` — advanced, grow into it).

## References (load on demand)

- `references/bootstrap.md` — install `op`, the macOS Keychain bootstrap for `OP_SERVICE_ACCOUNT_TOKEN`, Linux/server path.
- `references/rotation.md` — full op-CLI lexicon + cadence model + manual rotation discipline.
- `references/notion-rotation-tasks.md` — how a due secret becomes a Notion task; required DB schema.
- `references/engine.md` — the rotate-*.sh pattern + leak-response hook, documented for growth (not shipped as live automation).
- `references/discord-notifier.md` — optional Discord alerting (OFF by default).
- `references/worked-example.md` — a full worked example to make the abstract concrete.

The full config schema lives in `secrets-manager.local.md.example` at the plugin root. A read-only SessionStart hook (`hooks/check-due.sh`) prints a one-line "N secrets due" nudge each session — it never writes; task filing is always `/secrets-rotation-check` or the optional daily routine.

## Hard rules

- **NEVER** display, paste, or log a secret value. Reference by name.
- **NEVER** put plaintext secrets in `.env*` — only `.env.template` with `op://` refs.
- **ALWAYS** quote `op` field assignments and `--vault "$OP_VAULT"`.
- **ALWAYS** `unset VALUE` / `unset NEW_VALUE` after the command.
- **NEVER** copy one value into two items — one item, multiple tags.
- **NEVER** use interactive `op signin`; the Keychain-loaded `OP_SERVICE_ACCOUNT_TOKEN` authenticates non-interactively.
