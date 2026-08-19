# Discord notifier (optional — OFF by default)

The default rotation notifier files **Notion tasks** (see `notion-rotation-tasks.md`). A Discord notifier ships alongside it as a reference, **disabled by default**, so you can see the pattern and turn it on if you prefer chat alerts.

## Enabling it

1. Create a Discord webhook: a server channel → Integrations → Webhooks → New Webhook → Copy URL.
2. Store the URL as a 1P item (treat it as a secret — webhook URLs grant post access):
   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/scripts/lib-op.sh"
   ITEM_NAME="DISCORD_ROTATION_WEBHOOK"
   read -rs VALUE
   TAGS="global,prod,local-dev,manual_rotate_only"; CADENCE_DAYS=365; METHOD=manual; ROT_CLASS=local-dev
   CONSUMERS="secrets-manager:discord-notifier"; NOTES="Rotation alert webhook, minted $(date +%F)"
   op_create_secret; unset VALUE
   ```
3. Flip the config flag in `secrets-manager.local.md`:
   ```yaml
   enable_discord: true
   discord_webhook_item: DISCORD_ROTATION_WEBHOOK
   ```

## Behavior when enabled

`notify-discord.sh` reads the webhook URL via `op read` at send time (never stored in plaintext) and posts a short message per due secret. Severity by emoji:

- ⚠️ secret overdue for rotation
- 🟢 rotation completed
- 🔴 rotation failed at mint

## Why it's off by default

Notion tasks are assignable, trackable, and persist until closed — better for "don't forget to do this" than a chat ping that scrolls away. Discord is here for people who already live in a server and want the nudge there too. **Both can run at once** (Notion task + Discord ping) if you enable Discord; the Notion task remains the system of record.

## Note on the webhook leak footgun

The original migration leaked a Discord webhook URL by running an `op item create` with an unquoted `credential[concealed]=$VALUE` under zsh (the glob error echoed the value). The create helper used above quotes the assignment, so following these steps is safe. Never paste the webhook URL into chat.
