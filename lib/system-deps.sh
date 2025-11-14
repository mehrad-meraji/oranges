#!/usr/bin/env bash
# System dependencies installation

install_xcode_cli_tools() {
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
}

install_rosetta() {
  if [[ $(uname -m) == 'arm64' ]]; then
    /usr/sbin/softwareupdate --install-rosetta --agree-to-license
  fi
}

install_homebrew() {
  local HOMEBREW_INSTALLER_URL='https://raw.githubusercontent.com/Homebrew/install/master/install.sh'

  if ! type brew >/dev/null 2>/dev/null; then
    echo "Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL "$HOMEBREW_INSTALLER_URL")"
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >>~/.zprofile
  fi

  . "$HOME/.zprofile"
}
