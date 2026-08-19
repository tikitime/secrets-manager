# The rotation engine — for growing into

This plugin ships the **core** of automated rotation (`lib-op.sh`, `rotate-template.sh`, one worked example `rotate-anthropic.sh`) but deliberately does NOT ship a full leak-response system. This file explains the bigger pattern so you can grow into it when your setup justifies it.

## Manual vs automated rotation

- **Manual** (the default, `rotation_method: manual`): you mint/revoke in the upstream console; `op_rotate_secret` records it in 1P. Most credentials live here. Safe, no extra infrastructure.
- **Automated** (`rotation_method: auto`): a `rotate-<platform>.sh` script mints a new value via the platform's admin API, updates 1P, mirrors to consumers, and revokes the old value — no human in the loop. Only worth it for platforms with a real key-management API and credentials that rotate often.

## The mint-and-revoke pattern

Every auto-rotation script is the same skeleton (`rotate-template.sh`):

```
1. read the platform admin key from 1P (the user's own, via op read)
2. mint a new value at the platform
3. op_rotate_secret  → update the 1P item (value + hash + last_rotated_at + count++)
4. mirror to consumers (re-deploy / re-sync each target in the `consumers` field)
5. verify the new value works
6. revoke the old value at the platform
7. notify (Notion task closed / status note)
```

`rotate-anthropic.sh` is a complete worked example: it reads **your** Anthropic admin key from **your** 1P, mints a new API key, updates the item, and revokes the old one. Copy it to add another platform — change steps 1, 2, and 6.

## The "minter" variation

Some platforms (e.g. Cloudflare) can issue scoped **child** tokens from a parent "minter" token. Instead of mint-and-revoke of the same credential, you mint a fresh child token and revoke the prior child — the parent never changes. Useful when one person's access should grow over time without changing the credential they hold. Out of scope for v1; noted so you recognize it when you hit it.

## Leak-response automation (NOT shipped — documented only)

A mature setup adds a **Stop hook** that scans each turn's transcript tail for known credential patterns; on a hit it hashes the value, looks it up in a hash-prefix cache of your 1P items, and dispatches the matching `rotate-*.sh` in the background. This is powerful but heavy:

- it needs a maintained hash-prefix cache (`build_hash_cache.py` over every item),
- a regex pattern list per credential type,
- and per-platform rotate scripts wired to admin APIs.

It also tends to be shaped around one org's specific platforms and alerting. **Build it only when you have enough secrets and enough rotation volume that manual discipline + the Notion reminder stops being enough.** Until then, the Notion-task reminder is the right amount of automation.

## Cloud-platform mirroring (NOT shipped — next step once you deploy)

When a secret feeds a deployed app, the deploy platform (GitHub Actions / Vercel / Cloudflare) holds a **mirror** of the 1P value. On rotation you must update those mirrors too, or the deployed app keeps using the stale value. A mature setup has `sync-from-1p.sh` scripts per platform driven by the item's `consumers` field. For v1, the `consumers` field still records where the mirrors are — so when you rotate, you know exactly what to update by hand. Automate the sync when manual updates get tedious.
