#!/usr/bin/env bash
# Bitwarden (rbw) authentication and setup

setup_rbw() {
  echo ""
  echo "Password manager (rbw)"

  # Ensure rbw is configured with email
  if ! command -v rbw >/dev/null 2>&1; then
    echo "❌ rbw not found after install"
    exit 1
  fi

  # Configure pinentry for nicer prompts on macOS
  if [ -x "/opt/homebrew/bin/pinentry-mac" ]; then
    rbw config set pinentry "/opt/homebrew/bin/pinentry-mac" >/dev/null 2>&1 || true
  fi

  # Set email if provided, otherwise prompt once via /dev/tty
  if [ -z "${RBW_EMAIL:-}" ]; then
    printf "Bitwarden email: " > /dev/tty
    IFS= read -r RBW_EMAIL < /dev/tty
  fi
  if [ -n "$RBW_EMAIL" ]; then
    rbw config set email "$RBW_EMAIL" >/dev/null 2>&1 || true
  fi

  # Try to unlock; if not registered, register then unlock
  if ! rbw unlock >/dev/null 2>&1; then
    echo "Registering rbw device (you may be prompted by pinentry)..."
    rbw register >/dev/null 2>&1 || true
    # Final unlock attempt (prompts handled by pinentry)
    rbw unlock >/dev/null 2>&1 || true
  fi

  echo "✓ rbw is ready"
  echo ""
}

get_rbw_token() {
  local item_name="${1:-Github Terminal Token}"
  local token=""

  # Attempt unlock (no-op if already unlocked); pinentry handles the prompt
  rbw unlock >/dev/null 2>&1 || true

  # Try to read the custom field named Token from the item by name
  token=$(rbw get --field Token "$item_name" 2>/dev/null || true)

  # Fallback to password field for the same item name
  if [ -z "$token" ] || [ "$token" = "null" ]; then
    token=$(rbw get "$item_name" 2>/dev/null || true)
  fi

  # Trim whitespace/newlines
  if [ -n "$token" ]; then
    token=$(printf '%s' "$token" | tr -d '\r\n ')
  fi

  echo "$token"
}

