#!/usr/bin/env bash
set -e  # Exit on error

# Configuration
GITHUB_USERNAME="${GITHUB_USERNAME:-mehrad-meraji}"
GITHUB_ITEM_NAME="${GITHUB_ITEM_NAME:-Github Terminal Token}"
GITHUB_REPO_RAW="https://raw.githubusercontent.com/mehrad-meraji/oranges/main/lib"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SCRIPT_DIR="$HOME/.oranges-tmp"
LIB_DIR="$SCRIPT_DIR/lib"

# Function to source a library file (local or remote)
source_lib() {
  local lib_name="$1"
  local local_path="$LIB_DIR/$lib_name"

  # Try local file first
  if [ -f "$local_path" ]; then
    source "$local_path"
  else
    # Download from GitHub if running via curl
    echo "Downloading $lib_name..."
    local tmp_file="/tmp/oranges-$lib_name"
    if curl -fsSL "$GITHUB_REPO_RAW/$lib_name" -o "$tmp_file" 2>/dev/null; then
      source "$tmp_file"
      rm -f "$tmp_file"
    else
      echo "❌ Failed to download $lib_name"
      exit 1
    fi
  fi
}

# Source library files
source_lib "sudo-keepalive.sh"
source_lib "system-deps.sh"
source_lib "bitwarden.sh"
source_lib "git-config.sh"
source_lib "chezmoi.sh"

# Initialize environment files
touch "$HOME/.zshenv"
touch "$HOME/.zprofile"

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

# Step 1: Sudo Authentication
echo "Step 1: Sudo Authentication"
echo "Please enter your sudo password:"
sudo -v || exit 1
echo "✓ Sudo access granted"
echo ""

# Step 2: Install system dependencies
install_xcode_cli_tools
install_rosetta
install_homebrew

# Step 3: Install prerequisites
echo "Step 2: Installing prerequisites (rbw, pinentry-mac)..."
brew install rbw pinentry-mac </dev/null

# Step 4: Setup Bitwarden (rbw)
echo "Step 3: Bitwarden Authentication"
setup_rbw

# Step 5: Start sudo keepalive
echo "Step 4: Sudo Keepalive"
start_sudo_keepalive

# Step 6: Install remaining packages
echo "Step 5: Installing git and chezmoi..."
brew install git chezmoi </dev/null
echo "✓ All packages installed"
echo ""

# Step 7: Retrieve GitHub credentials
echo "Step 6: Retrieving GitHub credentials from Bitwarden..."

# If GITHUB_TOKEN is already provided in env, use it
if [ -n "${GITHUB_TOKEN:-}" ] && [ "$GITHUB_TOKEN" != "null" ]; then
  echo "✓ Using pre-set GITHUB_TOKEN from environment"
else
  # Get token from rbw
  GITHUB_TOKEN=$(get_rbw_token "$GITHUB_ITEM_NAME")

  if [ -z "$GITHUB_TOKEN" ] || [ "$GITHUB_TOKEN" = "null" ]; then
    echo "❌ Failed to retrieve GitHub token from Bitwarden"
    echo "   - Item name: $GITHUB_ITEM_NAME"
    echo "   - Looked for custom field 'Token' or password field"
    exit 1
  fi

  echo "✓ GitHub credentials retrieved"
fi

echo ""

# Step 8: Configure git credentials
echo "Step 7: Git Configuration"
configure_git_credentials "$GITHUB_USERNAME" "$GITHUB_TOKEN"

# Step 9: Initialize chezmoi
echo "Step 8: Chezmoi Initialization"
init_chezmoi "$GITHUB_USERNAME"
