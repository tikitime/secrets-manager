# secrets-manager

A private Claude Code plugin that teaches one person the **ENV → 1Password** workflow — moving plaintext `.env` secrets into 1Password (consumed at runtime via `op://` references) — and then keeps those secrets healthy by filing **Notion rotation tasks** as they come due.

It's account-agnostic: you configure your own 1Password account, vault, and Notion workspace during onboarding. Nothing about anyone else's setup is baked in.

## Install (private)

This plugin is distributed from a **private** GitHub repo. You can only install it if you've been granted access to the repo.

```
/plugin marketplace add github.com/tikitime/secrets-manager
/plugin install secrets-manager
```

Then, in a project where you want to manage secrets:

```
/secrets-onboard
```

## Commands

| Command | What it does |
|---------|--------------|
| `/secrets-onboard` | One-time: install + authenticate `op`, store the service-account token in your Keychain, and collect your account/vault/Notion config. |
| `/secrets-migrate-repo` | Convert a repo's plaintext `.env*` into 1Password items + a `.env.template` of `op://` references + an `op run` boot wrap; verify, then remove the plaintext. |
| `/secrets-add` | Store one new secret (with all rotation/consumer metadata) and wire its `op://` reference. |
| `/secrets-rotate` | Rotate one secret: mint new upstream → update 1P → verify → revoke old. |
| `/secrets-rotation-check` | Find secrets past their cadence and file a Notion task (assigned to you) for each. |

A SessionStart hook also prints a one-line nudge each session if anything is overdue (read-only — it never files tasks on its own).

## What's shipped vs. what you grow into

**Shipped and ready:** the bootstrap, the `op_create_secret` / `op_rotate_secret` helpers, the repo-migration walkthrough, manual rotation, and the Notion rotation reminder.

**Documented, for growth** (`skills/secrets-management/references/engine.md`): automated per-platform rotation scripts, cloud-mirroring for deployed apps (GitHub Actions / Vercel / Cloudflare), and a leak-response hook. These are heavier and tied to your specific platforms — adopt them only when manual discipline stops scaling. A Discord notifier ships present-but-OFF as a reference.

## Managing access (repo owner)

Access = GitHub repo access. This repo lives on a **personal GitHub account**, where private-repo collaborators are free and unlimited. To add someone: invite them as a collaborator (read access is enough) under the repo's Settings → Collaborators. To revoke: remove their access. Nothing is public or discoverable.

## Security model

- Secret **values** never appear in chat, tool inputs, commits, or this repo. They're entered via silent stdin and stored only in 1Password.
- Repos keep a checked-in `.env.template` of `op://` references; plaintext `.env*` files are removed.
- `op` field assignments are always quoted to avoid the zsh `[concealed]=` glob leak.
- `secrets-manager.local.md` (your per-user config) is gitignored and holds only ids/references, never secret values. See `secrets-manager.local.md.example`.
