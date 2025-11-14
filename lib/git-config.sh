#!/usr/bin/env bash
# Git credential configuration

configure_git_credentials() {
  local github_username="$1"
  local github_token="$2"

  echo "Configuring git..."
  git config --global credential.helper store
  git config --global credential.interactive false

  # Store the GitHub credentials so git can use them
  mkdir -p "$HOME"
  echo "https://${github_username}:${github_token}@github.com" > "$HOME/.git-credentials"
  chmod 600 "$HOME/.git-credentials"
  echo "✓ Git configured with credentials"
  echo ""
}

