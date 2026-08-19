#!/usr/bin/env bash
set -euo pipefail
# notify-discord.sh — OPTIONAL rotation alerter, DISABLED by default.
#
# The default notifier files Notion tasks. This Discord notifier is here as a
# reference to grow into. Enable it by setting in secrets-manager.local.md:
#     enable_discord: true
#     discord_webhook_item: DISCORD_ROTATION_WEBHOOK   # 1P item holding the webhook URL
# See references/discord-notifier.md.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/lib-op.sh"
_sm_load_config

CONFIG="${SM_CONFIG:-secrets-manager.local.md}"
[ -f "$CONFIG" ] || CONFIG="./secrets-manager.local.md"

enabled="$(_sm_frontmatter_value enable_discord "$CONFIG")"
if [ "$enabled" != "true" ]; then
  echo "Discord notifier disabled (enable_discord: false). Skipping." >&2
  exit 0
fi

webhook_item="$(_sm_frontmatter_value discord_webhook_item "$CONFIG")"
webhook_item="${webhook_item:-DISCORD_ROTATION_WEBHOOK}"
MESSAGE="${1:?usage: notify-discord.sh \"message\"}"

URL="$(op read "op://$OP_VAULT/$webhook_item/credential")"
payload="$(python3 -c 'import json,sys; print(json.dumps({"content": sys.argv[1]}))' "$MESSAGE")"
curl -sS -H "Content-Type: application/json" -d "$payload" "$URL" >/dev/null
unset URL
echo "✓ Discord notified."
