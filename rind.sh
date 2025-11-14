#!/usr/bin/env bash
set -e  # Exit on error

HOMEBREW_INSTALLER_URL='https://raw.githubusercontent.com/Homebrew/install/master/install.sh'

touch $HOME/.zshenv
touch $HOME/.zprofile

echo "================================================"
echo "  macOS Setup Script"
echo "================================================"
echo ""
echo "This script will:"
echo "  1. Request your sudo password"
echo "  2. Request Bitwarden credentials (if needed)"
echo "  3. Install Xcode Command Line Tools"
echo "  4. Install Homebrew and essential packages"
echo "  5. Initialize chezmoi with your dotfiles"
echo ""

# Get sudo password first
echo "Step 1: Sudo Authentication"
echo "Please enter your sudo password:"
sudo -v || exit 1
echo "✓ Sudo access granted"
echo ""

## Spawn sudo in background subshell to refresh the sudo timestamp
prevent_sudo_timeout() {
  # Spawn background loop to refresh sudo timestamp
  # Note: Don't redirect stdin - sudo -v uses the cached credentials
  ( while true; do
      sudo -n -v 2>/dev/null || true
      sleep 40
    done ) &

  sudo_loop_PID=$!
  readonly sudo_loop_PID

  # Trap to kill the background refresher when the script exits or is terminated
  trap 'if [ -n "$sudo_loop_PID" ] && kill -0 "$sudo_loop_PID" 2>/dev/null; then
          kill "$sudo_loop_PID" 2>/dev/null || true
          wait "$sudo_loop_PID" 2>/dev/null || true
        fi' EXIT INT TERM HUP
}


# Install Xcode Command Line Tools non-interactively
if ! xcode-select -p &> /dev/null; then
  echo "Installing Xcode Command Line Tools..."
  # Create placeholder file to enable non-interactive installation
  touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

  # Find the latest Command Line Tools package
  PROD=$(softwareupdate -l | grep "\*.*Command Line" | tail -n 1 | sed 's/^[^C]* //')

  # Install the package
  softwareupdate -i "$PROD" --verbose

  # Clean up placeholder file
  rm /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

  echo "Xcode Command Line Tools installed successfully"
else
  echo "Xcode Command Line Tools already installed"
fi

# Install Rosetta
if [[ $(uname -m) == 'arm64' ]]; then
  /usr/sbin/softwareupdate --install-rosetta --agree-to-license
fi

# Install Homebrew if not present
if ! type brew >/dev/null 2>/dev/null; then
  echo "Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL "$HOMEBREW_INSTALLER_URL")"
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >>~/.zprofile
fi

. "$HOME/.zprofile"

# Install only jq and bitwarden-cli first (needed for credential setup)
echo "Step 2: Installing jq and bitwarden-cli..."
brew install jq bitwarden-cli </dev/null

# Login to BitWarden if needed - DO THIS BEFORE starting sudo refresh loop
echo ""
echo "Step 3: Bitwarden Authentication"
BW_STATUS=$(bw status | jq -r ".status")
if [ "$BW_STATUS" == "unauthenticated" ]; then
  echo "Please log in to Bitwarden:"
  BW_SESSION=$(bw login --raw </dev/tty)
  export BW_SESSION
  echo "✓ Bitwarden login successful"
  echo "✓ Session token captured and exported"
elif [ "$BW_STATUS" == "locked" ]; then
  echo "Please unlock Bitwarden:"
  BW_SESSION=$(bw unlock --raw </dev/tty)
  export BW_SESSION
  echo "✓ Bitwarden unlocked successfully"
  echo "✓ Session token captured and exported"
else
  echo "✓ Bitwarden already authenticated"
  # If already unlocked, get the session from bw status
  BW_SESSION=$(bw status | jq -r '.userEmail' 2>/dev/null || echo "")
  if [ -z "$BW_SESSION" ]; then
    echo "⚠ Warning: Could not retrieve existing session, will prompt if needed"
  else
    export BW_SESSION
  fi
fi

# Quick test to verify the session works
echo "Verifying Bitwarden session..."
if bw sync --session "$BW_SESSION" >/dev/null 2>&1; then
  echo "✓ Bitwarden session verified and ready"
else
  echo "⚠ Warning: Session verification failed, may need to re-authenticate later"
fi
echo ""

# Now start the sudo refresh loop AFTER all interactive prompts are done
echo "Step 4: Starting background sudo refresh..."
prevent_sudo_timeout
readonly sudo_loop_PID # Make PID readonly for security

# Give the background loop a moment to start and verify it's running
sleep 1
if kill -0 "$sudo_loop_PID" 2>/dev/null; then
  echo "✓ Sudo refresh started (PID: $sudo_loop_PID)"
else
  echo "⚠ Warning: Sudo refresh loop may not have started properly"
fi
echo ""

# Install remaining packages
echo "Step 5: Installing git and chezmoi..."
brew install git chezmoi </dev/null
echo "✓ All packages installed"
echo ""

echo "Step 6: Retrieving GitHub credentials from Bitwarden..."
GITHUB_USERNAME=mehrad-meraji

# Verify BW_SESSION is set (it should be from Step 3)
if [ -z "$BW_SESSION" ]; then
  echo "❌ ERROR: BW_SESSION is not set. This is a bug in the script."
  exit 1
fi

# If GITHUB_TOKEN is already provided in env, prefer it and skip Bitwarden
if [ -n "$GITHUB_TOKEN" ] && [ "$GITHUB_TOKEN" != "null" ]; then
  echo "✓ Using pre-set GITHUB_TOKEN from environment"
else
  # Ensure vault is synced (non-interactive)
  bw sync --session "$BW_SESSION" >/dev/null 2>&1 || true

  # Fetch the item JSON without interaction
  ITEM_JSON=$(bw get item 1372d340-bd72-4cdf-a458-afc700e924c8 --session "$BW_SESSION" --nointeraction 2>/dev/null || true)

  if [ -z "$ITEM_JSON" ]; then
    echo "Bitwarden session may be invalid. Please unlock again:"
    BW_SESSION=$(bw unlock --raw </dev/tty)
    export BW_SESSION
    ITEM_JSON=$(bw get item 1372d340-bd72-4cdf-a458-afc700e924c8 --session "$BW_SESSION" --nointeraction 2>/dev/null || true)
  fi

  # Try custom field named "Token" (case-insensitive)
  TOKEN_FROM_FIELD=$(printf '%s' "$ITEM_JSON" | jq -r '((.fields // []) | map(select(((.name // "") | ascii_downcase) == "token")) | .[0].value) // empty' 2>/dev/null)

  # Fallback: login.password (if item is a Login type)
  TOKEN_FROM_LOGIN=$(printf '%s' "$ITEM_JSON" | jq -r '(.login.password // empty)' 2>/dev/null)

  # Fallback: parse notes for a GitHub token pattern
  NOTES_RAW=$(printf '%s' "$ITEM_JSON" | jq -r '(.notes // empty)' 2>/dev/null)
  TOKEN_FROM_NOTES=""
  if [ -n "$NOTES_RAW" ] && [ "$NOTES_RAW" != "null" ]; then
    # Match modern and classic GitHub PAT formats
    TOKEN_FROM_NOTES=$(printf '%s' "$NOTES_RAW" | grep -Eo 'github_pat_[A-Za-z0-9_]{80,}|gh[pousr]_[A-Za-z0-9]{36,}' | head -n1 || true)
  fi

  # Choose the first non-empty candidate
  for CAND in "$TOKEN_FROM_FIELD" "$TOKEN_FROM_LOGIN" "$TOKEN_FROM_NOTES"; do
    if [ -n "$CAND" ] && [ "$CAND" != "null" ]; then
      GITHUB_TOKEN=$CAND
      break
    fi
  done

  # Trim whitespace/newlines just in case
  if [ -n "$GITHUB_TOKEN" ]; then
    GITHUB_TOKEN=$(printf '%s' "$GITHUB_TOKEN" | tr -d '\r\n ')
  fi

  if [ -z "$GITHUB_TOKEN" ] || [ "$GITHUB_TOKEN" = "null" ]; then
    # Safe debug info (no secrets)
    ITEM_TYPE=$(printf '%s' "$ITEM_JSON" | jq -r '.type // empty' 2>/dev/null || echo "")
    FIELD_NAMES=$(printf '%s' "$ITEM_JSON" | jq -r '((.fields // []) | map(.name) | join(", ")) // ""' 2>/dev/null || echo "")
    echo "❌ Failed to retrieve GitHub token from Bitwarden"
    echo "   - Item type: ${ITEM_TYPE:-unknown}"
    echo "   - Custom fields present: ${FIELD_NAMES:-none}"
    echo "   Expected a custom field named 'Token' or a token in notes/login.password."
    exit 1
  fi

  echo "✓ GitHub credentials retrieved"
fi

echo ""

# Configure git credentials to use the PAT token
echo "Step 7: Configuring git..."
git config --global credential.helper store
git config --global credential.interactive false

# Store the GitHub credentials so git can use them
mkdir -p "$HOME"
echo "https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com" > "$HOME/.git-credentials"
chmod 600 "$HOME/.git-credentials"
echo "✓ Git configured with credentials"
echo ""

# Initialize chezmoi with private dotfiles repo
echo "Step 8: Initializing chezmoi with your dotfiles..."
echo "(This will take several minutes - installing 80+ packages...)"
chezmoi init --apply "https://github.com/${GITHUB_USERNAME}/dotfiles.git" </dev/null
echo ""
echo "================================================"
echo "  ✓ Setup Complete!"
echo "================================================"
