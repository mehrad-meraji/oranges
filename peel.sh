HOMEBREW_INSTALLER_URL='https://raw.githubusercontent.com/Homebrew/install/master/install.sh'

touch ~/.zprofile

## Spawn sudo in background subshell to refresh the sudo timestamp
prevent_sudo_timeout() {
  # Note: Don't use GNU expect... just a subshell (for some reason expect spawn jacks up readline input)
  echo "Please enter your sudo password to make changes to your machine"
  sudo -v # Asks for passwords
  ( while true; do sudo -v; sleep 40; done ) &   # update the user's timestamp
  export sudo_loop_PID=$!
}

# Hack to make sure sudo caches sudo password correctly...
# And so it stays available for the duration of the Chef run
prevent_sudo_timeout
readonly sudo_loop_PID  # Make PID readonly for security ;-)

# Try xcode-select --install first
if [[ "$TRY_XCI_OSASCRIPT_FIRST" == '1' ]]; then
	# Try the AppleScript automation method rather than relying on manual .xip / .dmg download & mirroring
	# Note: Apple broke automated Xcode installer downloads.  Now requires manual Apple ID sign-in.
	# Source: https://web.archive.org/web/20211210020829/https://techviewleo.com/install-xcode-command-line-tools-macos/
  xcode-select --install
  sleep 1
  osascript <<-EOD
	  tell application "System Events"
	    tell process "Install Command Line Developer Tools"
	      keystroke return
	      click button "Agree" of window "License Agreement"
	    end tell
	  end tell
EOD
fi

# Homebrew install
brew --version
[ ! -x "$(which brew)" -a "$?" -eq 0 ] || /bin/bash -c "$(curl -fsSL "$HOMEBREW_INSTALLER_URL" )"
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile && source ~/.zprofile

brew install ansible bitwarden-cli

# Login to BitWarden Vault
BW_SESSION="$(bw login --raw)"

# Add private ssh key
KEY="$(bw get notes ssh)"
mkdir ~/.ssh
touch private_rsa
echo KEY >> private_rsa

