# Bootstrap — getting `op` working non-interactively

The `op` CLI needs a credential to authenticate. We use a **1Password Service Account token** stored in the OS keychain, so `op` works in non-interactive shells (like Claude Code's) without a biometric prompt. The token is the one bootstrap exception — it can't itself live in 1Password (chicken-and-egg).

## macOS (primary path)

### 1. Install op

```bash
brew install 1password-cli
op --version    # confirm
```

### 2. Mint a Service Account token

In a browser: **1Password → Developer → Service Accounts → Create** (or reuse one your admin gives you). Grant it read access to **your** vault only. Copy the token (starts with `ops_`). You will paste it into the terminal in the next step — never into chat.

### 3. Store it in the login Keychain

```bash
# Paste happens in YOUR terminal; the value is read silently and never echoed.
read -rs OPS_TOKEN
security add-generic-password \
  -s secrets-manager-op-token -a "$USER" \
  -w "$OPS_TOKEN" \
  -T /opt/homebrew/bin/op -T /usr/bin/security
unset OPS_TOKEN
```

The `-T` flags add `op` and `security` to the item's always-allow list so they can read it without a prompt.

### 4. Load it on shell startup

Add to `~/.zshrc` (the onboarding command does this for you):

```bash
export OP_SERVICE_ACCOUNT_TOKEN=$(security find-generic-password -w -s secrets-manager-op-token -a "$USER" 2>/dev/null)
```

Open a fresh shell, then verify:

```bash
op whoami        # should print the service-account identity
op vault list    # should list your vault
```

### Keychain partition gotcha

If a subprocess (VS Code, Claude Code) can't read the value (`OP_SERVICE_ACCOUNT_TOKEN` is empty), widen the partition list once — interactive, prompts for your Mac password:

```bash
security set-generic-password-partition-list \
  -S "apple-tool:,apple:,unsigned:" \
  -s secrets-manager-op-token -a "$USER" \
  "$HOME/Library/Keychains/login.keychain-db"
```

## Linux / servers (alternate path)

No Keychain. Put the token in the environment via the process manager:

- **systemd service:** an `Environment=OP_SERVICE_ACCOUNT_TOKEN=...` line in a drop-in that's `chmod 600` and root-owned, OR a `EnvironmentFile=` pointing at a `600` file.
- **plain shell on a server:** export it from a root-only file sourced by the service's launch script.

The principle is the same: the token is injected into the process environment by the platform; everything else resolves from 1Password via `op://`.

## Rotating the bootstrap token

1. Mint a new Service Account token in the browser.
2. Replace the stored copy:
   ```bash
   security delete-generic-password -s secrets-manager-op-token -a "$USER"
   read -rs OPS_TOKEN
   security add-generic-password -s secrets-manager-op-token -a "$USER" \
     -w "$OPS_TOKEN" -T /opt/homebrew/bin/op -T /usr/bin/security
   unset OPS_TOKEN
   ```
3. Open a fresh shell, confirm `op whoami`.
4. Revoke the old token in the browser.

## Last-resort fallback

If `OP_SERVICE_ACCOUNT_TOKEN` is unset and the 1Password desktop app is installed + CLI-integrated, `op` falls back to a biometric prompt. Fine for interactive debugging; production scripts should fail loudly instead of silently waiting on a prompt.
