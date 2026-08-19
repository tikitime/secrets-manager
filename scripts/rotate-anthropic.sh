#!/usr/bin/env bash
set -euo pipefail
# rotate-anthropic.sh — WORKED EXAMPLE of automated rotation (see references/engine.md).
#
# Rotates an Anthropic API key: mints a new key via the Admin API using YOUR
# Anthropic admin key (stored in your 1P), updates the 1P item, and tells you to
# revoke the old key.
#
# This is an EXAMPLE to copy and adapt — VERIFY the Admin API endpoint, request
# body, and response fields against current Anthropic documentation before
# trusting it unattended. It is intentionally conservative: it stores the new
# value but leaves the final revoke to you.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/lib-op.sh"
_sm_load_config

ITEM_NAME="${1:?usage: rotate-anthropic.sh <ITEM_NAME>}"
ADMIN_ITEM="${ANTHROPIC_ADMIN_ITEM:-ANTHROPIC_ADMIN_KEY}"

ADMIN_KEY="$(op read "op://$OP_VAULT/$ADMIN_ITEM/credential")"

# 1. mint a new key (verify endpoint/shape against current Anthropic docs)
resp="$(curl -sS https://api.anthropic.com/v1/organizations/api_keys \
  -H "x-api-key: $ADMIN_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "{\"name\":\"rotated-$(date +%F)\"}")"

NEW_VALUE="$(printf '%s' "$resp" | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin).get("api_key",""))
except Exception:
    print("")')"
unset ADMIN_KEY

if [ -z "$NEW_VALUE" ]; then
  echo "Mint failed or response shape unexpected. Raw response:" >&2
  printf '%s\n' "$resp" >&2
  exit 1
fi

# 2. update 1P
export ITEM_NAME NEW_VALUE
op_rotate_secret
unset NEW_VALUE

echo "✓ New Anthropic key minted and stored in 1P for $ITEM_NAME."
echo "Next: verify the new key works, then revoke the OLD key in the Anthropic console/API."
echo "(This example does not auto-revoke — implement revoke once you've confirmed the new key.)"
