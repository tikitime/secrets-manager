#!/usr/bin/env bash
set -euo pipefail
# bootstrap.sh — store the 1Password Service Account token in the macOS login
# Keychain and add a loader line to ~/.zshrc, so `op` works non-interactively.
# macOS only. For Linux/servers see references/bootstrap.md.

SERVICE="secrets-manager-op-token"
ACCOUNT="${USER}"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "This bootstrap is macOS-only. See references/bootstrap.md for the Linux/server path." >&2
  exit 1
fi

OP_BIN="$(command -v op || true)"
if [[ -z "$OP_BIN" ]]; then
  echo "op CLI not found. Install it first:  brew install 1password-cli" >&2
  exit 1
fi

echo "Paste your 1Password Service Account token (input hidden), then press Enter."
echo "Don't have one? Create it at: 1Password → Developer → Service Accounts → Create"
echo "(scope it to read YOUR vault only)."
read -rs OPS_TOKEN
echo
if [[ -z "${OPS_TOKEN:-}" ]]; then
  echo "No token entered. Aborting." >&2
  exit 1
fi

# Replace any existing entry, then store with op + security on the allow list.
security delete-generic-password -s "$SERVICE" -a "$ACCOUNT" >/dev/null 2>&1 || true
security add-generic-password -s "$SERVICE" -a "$ACCOUNT" -w "$OPS_TOKEN" \
  -T "$OP_BIN" -T /usr/bin/security
unset OPS_TOKEN
echo "✓ Token stored in login Keychain as '$SERVICE'."

# Add the loader to ~/.zshrc if not already present.
LOADER='export OP_SERVICE_ACCOUNT_TOKEN=$(security find-generic-password -w -s secrets-manager-op-token -a "$USER" 2>/dev/null)'
if ! grep -qF 'secrets-manager-op-token' "${HOME}/.zshrc" 2>/dev/null; then
  printf '\n# secrets-manager: load 1Password service-account token from Keychain\n%s\n' "$LOADER" >> "${HOME}/.zshrc"
  echo "✓ Added loader to ~/.zshrc."
else
  echo "✓ Loader already present in ~/.zshrc."
fi

# Verify in this shell.
export OP_SERVICE_ACCOUNT_TOKEN="$(security find-generic-password -w -s "$SERVICE" -a "$ACCOUNT" 2>/dev/null)"
if [[ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]] && op whoami >/dev/null 2>&1; then
  echo "✓ op authenticated. Open a fresh shell, then run:  op vault list"
else
  echo "⚠ Could not authenticate in this shell. The Keychain partition list may need widening:" >&2
  echo "  security set-generic-password-partition-list -S \"apple-tool:,apple:,unsigned:\" -s $SERVICE -a $ACCOUNT \"\$HOME/Library/Keychains/login.keychain-db\"" >&2
  echo "  (interactive, prompts once for your Mac password — see references/bootstrap.md)" >&2
fi
