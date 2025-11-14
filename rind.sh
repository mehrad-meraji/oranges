#!/usr/bin/env bash
set -e  # Exit on error

HOMEBREW_INSTALLER_URL='https://raw.githubusercontent.com/Homebrew/install/master/install.sh'

touch $HOME/.zshenv
touch $HOME/.zprofile


## Spawn sudo in background subshell to refresh the sudo timestamp
prevent_sudo_timeout() {
  echo "Please enter your sudo password to make changes to your machine"
  sudo -v || return 1

  # Spawn background loop to refresh sudo timestamp
  ( while true; do
      sudo -v
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

# Hack to make sure sudo caches sudo password correctly...
# And so it stays available for the duration of the run
prevent_sudo_timeout
readonly sudo_loop_PID # Make PID readonly for security

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

# Install only the absolute prerequisites needed to run chezmoi
# Everything else (80+ packages, casks, fish, etc.) will be installed by chezmoi
brew install jq bitwarden-cli git chezmoi

# Login to BitWarden if needed
BW_STATUS=$(bw status | jq -r ".status")
if [ "$BW_STATUS" == "unauthenticated" ]; then
  echo "Logging into Bitwarden..."
  # Run bw login with stdin and stderr from tty, capture stdout
  BW_SESSION=$(bw login --raw </dev/tty 2>/dev/tty)
  echo "export BW_SESSION=$BW_SESSION" >> "$HOME/.zshenv"
  # Source the updated file to get the BW_SESSION variable
  . "$HOME/.zshenv"
elif [ "$BW_STATUS" == "locked" ]; then
  echo "Unlocking Bitwarden..."
  # Run bw unlock with stdin and stderr from tty, capture stdout
  BW_SESSION=$(bw unlock --raw </dev/tty 2>/dev/tty)
  echo "export BW_SESSION=$BW_SESSION" >> "$HOME/.zshenv"
  . "$HOME/.zshenv"
fi


# Get GitHub credentials from BitWarden
GITHUB_USERNAME=mehrad-meraji
GITHUB_TOKEN=$(bw get item 1372d340-bd72-4cdf-a458-afc700e924c8 --session "$BW_SESSION" | jq -r '.fields[] | select(.name=="Token") | .value')

# Configure git credentials (git-credential-manager will be installed by chezmoi)
git config --global credential.interactive false
git config --global credential.ghe.contoso.com.provider github
git config --global credential.gitHubAuthModes "pat"

# Initialize chezmoi with private dotfiles repo
echo "Initializing chezmoi (this will take several minutes)..."
chezmoi init --apply "$GITHUB_USERNAME"
