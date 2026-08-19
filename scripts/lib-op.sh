#!/usr/bin/env bash
# lib-op.sh — sourced helpers for creating and rotating 1Password secret items.
#
# Safe under bash AND zsh: every field assignment is quoted, which avoids the
# zsh `[concealed]=$VALUE` glob expansion that can echo a secret to stderr.
#
# Usage:
#   source "${CLAUDE_PLUGIN_ROOT}/scripts/lib-op.sh"
#   ITEM_NAME=... ; read -rs VALUE ; TAGS=... ; CADENCE_DAYS=... ; METHOD=... ;
#   ROT_CLASS=... ; CONSUMERS=... ; NOTES=... ; op_create_secret ; unset VALUE
#
# OP_VAULT / OP_ACCOUNT are read from secrets-manager.local.md if not already set.

_sm_config_file="${SM_CONFIG:-secrets-manager.local.md}"

_sm_frontmatter_value() {
  # $1 = key, $2 = file. Prints the value with surrounding quotes stripped.
  sed -n "s/^$1:[[:space:]]*//p" "$2" 2>/dev/null | head -1 | sed 's/^"//; s/"$//; '"s/^'//; s/'\$//"
}

_sm_load_config() {
  local f="$_sm_config_file"
  [ -f "$f" ] || f="./secrets-manager.local.md"
  if [ -f "$f" ]; then
    [ -z "${OP_VAULT:-}" ]   && OP_VAULT="$(_sm_frontmatter_value op_vault "$f")"
    [ -z "${OP_ACCOUNT:-}" ] && OP_ACCOUNT="$(_sm_frontmatter_value op_account "$f")"
  fi
  if [ -z "${OP_VAULT:-}" ]; then
    echo "ERROR: OP_VAULT not set and no secrets-manager.local.md found. Run /secrets-onboard." >&2
    return 1
  fi
  export OP_VAULT OP_ACCOUNT
}

_sm_sha_prefix() {
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | cut -c1-12
  else
    printf '%s' "$1" | sha256sum | cut -c1-12
  fi
}

op_create_secret() {
  _sm_load_config || return 1
  : "${ITEM_NAME:?ITEM_NAME required}"
  : "${VALUE:?VALUE required (use: read -rs VALUE)}"
  local hash today
  hash="$(_sm_sha_prefix "$VALUE")"
  today="$(date +%F)"
  op item create --vault "$OP_VAULT" --category 'API Credential' \
    --title "$ITEM_NAME" \
    --tags "${TAGS:-}" \
    "credential[concealed]=$VALUE" \
    "value_hash_prefix[text]=$hash" \
    "created_at[text]=$today" \
    "last_rotated_at[text]=$today" \
    "rotation_count[text]=0" \
    "rotation_cadence_days[text]=${CADENCE_DAYS:-365}" \
    "rotation_method[text]=${METHOD:-manual}" \
    "rotation_class[text]=${ROT_CLASS:-local-dev}" \
    "rotation_runbook_url[text]=${RUNBOOK_URL:-}" \
    "consumers[text]=${CONSUMERS:-}" \
    "notesPlain[text]=${NOTES:-}"
}

op_rotate_secret() {
  _sm_load_config || return 1
  : "${ITEM_NAME:?ITEM_NAME required}"
  : "${NEW_VALUE:?NEW_VALUE required (use: read -rs NEW_VALUE)}"
  local new_hash today count
  new_hash="$(_sm_sha_prefix "$NEW_VALUE")"
  today="$(date +%F)"
  count="$(op item get "$ITEM_NAME" --vault "$OP_VAULT" --fields label=rotation_count 2>/dev/null | tr -dc '0-9')"
  op item edit "$ITEM_NAME" --vault "$OP_VAULT" \
    "credential[concealed]=$NEW_VALUE" \
    "value_hash_prefix[text]=$new_hash" \
    "last_rotated_at[text]=$today" \
    "rotation_count[text]=$(( ${count:-0} + 1 ))"
}
