---
name: secrets-onboard
description: One-time setup — install/authenticate the 1Password CLI, store the service-account token in the OS keychain, then collect the user's account/vault/Notion config and write secrets-manager.local.md. Run this first, before any other secrets-manager command.
---

# /secrets-onboard

Guide the user through first-time setup. Be conversational and patient — assume they have never used `op` before. **Never display, paste, or log any secret or token value.** All sensitive values are entered by the user via silent stdin (`read -rs`) in their own terminal.

Invoke the `secrets-management` skill for the mental model. Walk through these steps in order, confirming each before moving on.

## Step 1 — Check / install op

```bash
op --version
```

If missing, walk them through `brew install 1password-cli` (macOS) or the equivalent for their OS. See `${CLAUDE_PLUGIN_ROOT}/skills/secrets-management/references/bootstrap.md` for the Linux/server path.

## Step 2 — Bootstrap the service-account token

Run the helper, which handles the Keychain store + the `~/.zshrc` export line:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap.sh"
```

The script prompts the user to paste their service-account token via silent stdin. If they don't have one, point them to **1Password → Developer → Service Accounts → Create**, scoped to read **their** vault only. After it runs, confirm in a fresh shell:

```bash
op whoami && op vault list
```

If `op whoami` fails, debug per the "Keychain partition gotcha" section of `bootstrap.md`.

## Step 3 — Collect config (ask, don't assume)

Ask the user, one at a time:

1. **1Password account** (e.g. `myteam.1password.com`) — confirm against `op whoami`.
2. **Vault name** — show `op vault list` and ask which one is theirs. **Quote it** when you store it; it may contain spaces/hyphens (e.g. `Developer Vault - Jordan`).
3. **Notion tasks database** — the database where rotation tasks should land. Ask for the database id or share-URL.
4. **Notion assignee** — who rotation tasks get assigned to (their Notion user). Use the Notion MCP if available to look up their user id.

## Step 4 — Validate the Notion database

Before saving, confirm the target database has the required properties (a title, a `people` assignee, a `date` due date, and a status/select). See `${CLAUDE_PLUGIN_ROOT}/skills/secrets-management/references/notion-rotation-tasks.md`. If a property is missing, tell the user exactly which one and either have them add it or record the alternate property name in the config mapping.

## Step 5 — Write the config

Write `secrets-manager.local.md` at the root of the project they'll be working in (it's gitignored — never commit it). Use YAML frontmatter:

```yaml
---
op_account: <their account>
op_vault: "<their vault>"
notion_tasks_db: <db id>
notion_assignee: <user id>
enable_discord: false
---
# secrets-manager local config — do not commit. Written by /secrets-onboard.
```

## Step 6 — Offer the daily rotation routine (optional)

Ask if they want a daily scheduled check that auto-files Notion tasks for due secrets. If yes, set it up via the `/schedule` skill to run `/secrets-rotation-check` daily. If no, tell them the SessionStart nudge will remind them and they can run `/secrets-rotation-check` manually.

## Done

Summarize: op authenticated ✓, config saved ✓, rotation reminders on (routine or manual) ✓. Tell them the next step is `/secrets-migrate-repo` in a repo that still has plaintext `.env` files, or `/secrets-add` to store a single new secret.
