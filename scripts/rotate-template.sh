#!/usr/bin/env bash
set -euo pipefail
# rotate-template.sh — skeleton for AUTOMATED secret rotation (see references/engine.md).
#
# Copy this file to rotate-<platform>.sh and implement platform_mint_new and
# platform_revoke_old. The flow is always the same:
#   mint new → update 1P → (mirror consumers) → verify → revoke old.
#
# Most secrets do NOT need this — manual rotation via /secrets-rotate is the
# default. Use automation only for platforms with a real key-management API
# and credentials that rotate often.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/lib-op.sh"
_sm_load_config

ITEM_NAME="${1:?usage: rotate-template.sh <ITEM_NAME>}"

# 1. (optional) read this platform's ADMIN key from YOUR 1P:
# ADMIN_KEY=$(op read "op://$OP_VAULT/<PLATFORM>_ADMIN_KEY/credential")

platform_mint_new() {
  # TODO: call the platform API to mint a new value. Echo the new value to stdout.
  echo "IMPLEMENT_ME"
}

platform_revoke_old() {
  # TODO: call the platform API to revoke the OLD value (passed as $1).
  : "$1"
}

verify_new() {
  # TODO: a real check that the new value works (an API ping, an app boot, etc.).
  return 0
}

OLD_VALUE="$(op read "op://$OP_VAULT/$ITEM_NAME/credential")"
NEW_VALUE="$(platform_mint_new)"
if [ -z "$NEW_VALUE" ] || [ "$NEW_VALUE" = "IMPLEMENT_ME" ]; then
  echo "platform_mint_new not implemented — nothing rotated." >&2
  exit 1
fi

export ITEM_NAME NEW_VALUE
op_rotate_secret
unset NEW_VALUE

if verify_new; then
  platform_revoke_old "$OLD_VALUE"
  echo "✓ Rotated $ITEM_NAME and revoked the old value."
else
  echo "⚠ New value stored in 1P but verify_new failed — old value NOT revoked. Investigate." >&2
fi
unset OLD_VALUE
