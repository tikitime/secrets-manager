#!/usr/bin/env bash
# SessionStart hook — READ-ONLY rotation nudge.
# Prints a one-line notice if any secrets are due/overdue. Never writes anything
# (no Notion calls). Always exits 0 so it can never block a session start.
set -uo pipefail

CONFIG="secrets-manager.local.md"
[ -f "$CONFIG" ] || exit 0                 # not onboarded here → stay silent
command -v op >/dev/null 2>&1 || exit 0
op whoami >/dev/null 2>&1 || exit 0         # not authenticated → stay silent

SCRIPT="${CLAUDE_PLUGIN_ROOT:-}/scripts/rotation-check.py"
[ -f "$SCRIPT" ] || exit 0

# Cap runtime so a large vault can't slow session start.
if command -v timeout >/dev/null 2>&1; then
  json="$(timeout 8 python3 "$SCRIPT" --config "$CONFIG" --dry-run 2>/dev/null || true)"
elif command -v gtimeout >/dev/null 2>&1; then
  json="$(gtimeout 8 python3 "$SCRIPT" --config "$CONFIG" --dry-run 2>/dev/null || true)"
else
  json="$(python3 "$SCRIPT" --config "$CONFIG" --dry-run 2>/dev/null || true)"
fi

count="$(printf '%s' "$json" | python3 -c 'import sys,json
try:
    print(len(json.load(sys.stdin)))
except Exception:
    print(0)' 2>/dev/null || echo 0)"

if [ "${count:-0}" -gt 0 ] 2>/dev/null; then
  echo "⚠️ secrets-manager: ${count} secret(s) due/overdue for rotation — run /secrets-rotation-check to file Notion tasks."
fi
exit 0
