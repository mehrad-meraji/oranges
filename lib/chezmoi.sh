#!/usr/bin/env bash
# Chezmoi initialization

init_chezmoi() {
  local github_username="$1"

  echo "Initializing chezmoi with your dotfiles..."
  echo "(This will take several minutes - installing 80+ packages...)"
  chezmoi init --apply "https://github.com/${github_username}/dotfiles.git" </dev/null
  echo ""
  echo "================================================"
  echo "  ✓ Setup Complete!"
  echo "================================================"
}

