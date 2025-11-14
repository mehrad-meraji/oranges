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
  echo "export BW_SESSION=$BW_SESSION" >> "$HOME/.zshenv"
  echo "✓ Bitwarden login successful"
elif [ "$BW_STATUS" == "locked" ]; then
  echo "Please unlock Bitwarden:"
  BW_SESSION=$(bw unlock --raw </dev/tty)
  export BW_SESSION
  echo "export BW_SESSION=$BW_SESSION" >> "$HOME/.zshenv"
  echo "✓ Bitwarden unlocked successfully"
else
  echo "✓ Bitwarden already authenticated"
  # Load existing session from zshenv
  . "$HOME/.zshenv"
  export BW_SESSION
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

# Try to get the GitHub token - if it fails, the session is invalid
GITHUB_TOKEN=$(bw get item 1372d340-bd72-4cdf-a458-afc700e924c8 --session "$BW_SESSION" --nointeraction 2>/dev/null | jq -r '.fields[] | select(.name=="Token") | .value' 2>/dev/null || echo "")

# If we couldn't get the token, session might be expired - try to unlock
if [ -z "$GITHUB_TOKEN" ]; then
  echo "Bitwarden session expired or invalid. Please unlock again:"
  BW_SESSION=$(bw unlock --raw </dev/tty)
  export BW_SESSION
  echo "export BW_SESSION=$BW_SESSION" >> "$HOME/.zshenv"
  echo "✓ Bitwarden re-unlocked successfully"

  # Try again with the new session
  GITHUB_TOKEN=$(bw get item 1372d340-bd72-4cdf-a458-afc700e924c8 --session "$BW_SESSION" --nointeraction 2>/dev/null | jq -r '.fields[] | select(.name=="Token") | .value' 2>/dev/null || echo "")

  if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ Failed to retrieve GitHub token from Bitwarden"
    exit 1
  fi
fi

echo "✓ GitHub credentials retrieved"
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
