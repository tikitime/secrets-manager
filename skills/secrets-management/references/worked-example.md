# Worked example — one team's full setup

> **This is illustration, not configuration.** Nothing here is hardcoded into the plugin. Your own `secrets-manager.local.md` (written during `/secrets-onboard`) drives everything. This file just shows one fully-built setup so the abstract pattern clicks.

## The setup

Say you run a few projects out of one 1Password account. The lead's config looks like:

```yaml
op_account: myteam.1password.com
op_vault: Developer                      # the org-wide developer vault
notion_tasks_db: <your Tasks database id>
notion_assignee: <your Notion user id>
enable_discord: true                     # the team already lives in a Discord server
```

Someone you onboard (a teammate, a contractor) gets their **own** vault and config:

```yaml
op_account: myteam.1password.com
op_vault: "Developer Vault - Jordan"     # note the spaces + hyphen → always quoted
notion_tasks_db: <Jordan's Tasks database id>
notion_assignee: <Jordan's Notion user id>
enable_discord: false                    # Notion tasks are enough to start
```

## A real item

A shared Anthropic key used by two projects becomes one item with two project tags (not two copies):

```
title:  ANTHROPIC_API_KEY_MYAPP_PROD
tags:   myapp, myworker, prod, readonly-api, manual_rotate_only
fields: credential, value_hash_prefix, created_at, last_rotated_at,
        rotation_count, rotation_cadence_days=180, rotation_method=manual,
        rotation_class=readonly-api,
        consumers="myapp/.env.template:ANTHROPIC_API_KEY;myworker/.env.template:ANTHROPIC_API_KEY"
```

## A migrated repo

`myapp` is the first repo to move. Its `.env.template` (checked in) looks like:

```bash
# non-secret config inline
NODE_ENV=production
SUPABASE_URL=https://example.supabase.co

# secrets resolved from 1P at boot
DISCORD_BOT_TOKEN=op://Developer/DISCORD_BOT_TOKEN_MYAPP_PROD/credential
ANTHROPIC_API_KEY=op://Developer/ANTHROPIC_API_KEY_MYAPP_PROD/credential
```

`package.json` wraps boot in `op run`:

```json
"scripts": {
  "start": "op run --env-file=.env.template -- tsx src/index.ts",
  "build": "tsc"
}
```

`build` is unwrapped — it just compiles and needs no secrets.

## Scale you may grow into (you may not need this)

Once you have a few hundred items across many repos and deploy targets, the heavier machinery in `engine.md` starts to pay off: per-platform auto-rotate scripts, cloud-mirroring sync scripts (GitHub Actions / Vercel / Cloudflare), and a leak-response Stop hook. **Start with the Notion-task reminder.** Reach for that machinery only when manual rotation across many secrets becomes the bottleneck — not before.
