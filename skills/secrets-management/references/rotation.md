# op CLI lexicon + rotation discipline

Everything below assumes `OP_VAULT` is set from `secrets-manager.local.md` and **quoted** in every command. Field assignments are **always quoted** to dodge the zsh `[concealed]` glob leak.

> **Prefer the helpers.** The raw `op item create` / `op item edit` forms below are shown for understanding. In practice, `source "${CLAUDE_PLUGIN_ROOT}/scripts/lib-op.sh"` and call `op_create_secret` / `op_rotate_secret` — they handle the hash portably (`shasum` on macOS, `sha256sum` on Linux) and guard the `rotation_count` arithmetic. The raw snippets here hard-code `shasum`; on Linux substitute `sha256sum`.

## Search before you create

Never duplicate a value that already exists in another item. If the value is already in 1P, add a tag instead of minting a copy.

```bash
op item list --vault "$OP_VAULT" --tags global
op item list --vault "$OP_VAULT" --tags <project>,<env>
```

## CREATE — new item

Prefer the helper (`source "${CLAUDE_PLUGIN_ROOT}/scripts/lib-op.sh"; op_create_secret`). The raw form it runs:

```bash
op item create --vault "$OP_VAULT" --category 'API Credential' \
  --title "$ITEM_NAME" \
  --tags "$TAGS" \
  "credential[concealed]=$VALUE" \
  "value_hash_prefix[text]=$(printf '%s' "$VALUE" | shasum -a 256 | cut -c1-12)" \
  "created_at[text]=$(date +%F)" \
  "last_rotated_at[text]=$(date +%F)" \
  "rotation_count[text]=0" \
  "rotation_cadence_days[text]=$CADENCE_DAYS" \
  "rotation_method[text]=$METHOD" \
  "rotation_class[text]=$ROT_CLASS" \
  "consumers[text]=$CONSUMERS" \
  "notesPlain[text]=$NOTES"
```

## UPDATE — existing item (`op item edit` preserves untouched fields)

**Rotate the value** (helper: `op_rotate_secret`):

```bash
new_hash=$(printf '%s' "$NEW_VALUE" | shasum -a 256 | cut -c1-12)   # sha256sum on Linux
count=$(op item get "$ITEM_NAME" --vault "$OP_VAULT" --fields label=rotation_count 2>/dev/null | tr -dc '0-9')
op item edit "$ITEM_NAME" --vault "$OP_VAULT" \
  "credential[concealed]=$NEW_VALUE" \
  "value_hash_prefix[text]=$new_hash" \
  "last_rotated_at[text]=$(date +%F)" \
  "rotation_count[text]=$(( ${count:-0} + 1 ))"
```

**Add a tag** (tags REPLACE — read existing, append):

```bash
EXISTING=$(op item get "$ITEM_NAME" --vault "$OP_VAULT" --format json | jq -r '.tags | join(",")')
op item edit "$ITEM_NAME" --vault "$OP_VAULT" --tags "${EXISTING},newproject"
```

**Edit/correct one field:**

```bash
op item edit "$ITEM_NAME" --vault "$OP_VAULT" "consumers[text]=myapp/.env.template:KEY;gha:owner/repo:KEY"
```

**Mark leaked** (combine with rotation):

```bash
EXISTING=$(op item get "$ITEM_NAME" --vault "$OP_VAULT" --format json | jq -r '.tags | join(",")')
op item edit "$ITEM_NAME" --vault "$OP_VAULT" --tags "${EXISTING},leaked_$(date +%F),needs_rotation"
```

**Rename:**

```bash
op item edit "$OLD_NAME" --vault "$OP_VAULT" --title "$NEW_NAME"
# then update op:// references in any .env.template that point at the old title
```

**Edit by id** (survives renames; robust if the title has odd characters):

```bash
ID=$(op item get "$ITEM_NAME" --vault "$OP_VAULT" --format json | jq -r '.id')
op item edit "$ID" --vault "$OP_VAULT" "rotation_cadence_days[text]=180"
```

**Append to notesPlain** (replaces on edit — read, modify, write):

```bash
CUR=$(op item get "$ITEM_NAME" --vault "$OP_VAULT" --fields label=notesPlain --format json | jq -r '.value // ""')
op item edit "$ITEM_NAME" --vault "$OP_VAULT" "notesPlain[text]=${CUR}

$(date +%F) — rotated; new consumer gha:owner/newrepo:KEY"
```

**Archive** (soft-delete, recoverable):

```bash
op item delete "$ITEM_NAME" --vault "$OP_VAULT" --archive
op item list --vault "$OP_VAULT" --include-archive | grep ARCHIVED
```

> `op item delete` without `--archive` is permanent. Default to `--archive`.

## Field reference

| Field | Type | Purpose | Create? | Rotate touches? |
|-------|------|---------|---------|-----------------|
| `credential` | concealed | the value | ✅ | ✅ |
| `value_hash_prefix` | text | SHA256 first 12 | ✅ | ✅ |
| `created_at` | text | YYYY-MM-DD, immutable | ✅ | ❌ |
| `last_rotated_at` | text | YYYY-MM-DD of last value change | ✅ (=created) | ✅ |
| `rotation_count` | text | integer, ++ per rotation | ✅ (=0) | ✅ |
| `rotation_cadence_days` | text | 90 / 180 / 365 | ✅ | ❌ |
| `rotation_method` | text | auto / manual | ✅ | ❌ |
| `rotation_class` | text | prod-phi-payment / readonly-api / local-dev / no_rotation | ✅ | ❌ |
| `rotation_runbook_url` | text | doc for manual steps | optional | ❌ |
| `consumers` | text | semicolon-separated sync targets | ✅ | ❌ |
| `notesPlain` | text | origin + history | ✅ | append (optional) |

## Consumer string formats (mix freely, semicolon-separated)

- `<repo-relative-path>:<env-var>` — a `.env.template` reference
- `gha:<owner>/<repo>:<secret>` — GitHub Actions secret
- `vercel:<project>:<env>:<var>` — Vercel env var
- `cf-pages:<project>:<env>:<var>:<as-type>` — Cloudflare Pages
- `cf-worker:<worker>:<secret>` — Cloudflare Worker secret

## Cadence → rotation class

| Class | Cadence | Use for |
|-------|---------|---------|
| `prod-phi-payment` | 90d | production keys touching PHI or payments |
| `readonly-api` | 180d | read-mostly third-party API keys |
| `local-dev` | 365d | dev/local-only credentials |
| `no_rotation` | — | reference IDs (account numbers, project IDs) — not secrets |

## Manual rotation flow (the default)

1. Mint a new value in the upstream console (or via its API).
2. `op_rotate_secret` to update 1P (value + hash + last_rotated_at + count).
3. Update consumers (re-deploy / re-sync anything in the `consumers` field).
4. Verify the app/integration works with the new value.
5. Revoke the old value upstream.
6. If the rotation was triggered by a leak, the item already carries `leaked_<date>` — remove `needs_rotation` once done.

Automated mint-and-revoke for supported platforms is documented in `engine.md` (advanced).
