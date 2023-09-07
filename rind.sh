HOMEBREW_INSTALLER_URL='https://raw.githubusercontent.com/Homebrew/install/master/install.sh'

touch $HOME/.zshenv
touch $HOME/.zprofile

. $HOME/.zshenv
. $HOME/.zprofile

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

# Install Rosetta
if [[ $(uname -m) == 'arm64' ]]; then
	/usr/sbin/softwareupdate --install-rosetta --agree-to-license
fi

# Homebrew install
brew --version
if ! type brew >/dev/null 2>/dev/null; then 
	NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL "$HOMEBREW_INSTALLER_URL")"
	echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile && source ~/.zprofile
fi

. $HOME/.zprofile
brew install zsh jq ansible bitwarden-cli git
brew tap microsoft/git
brew install --cask git-credential-manager

. $HOME/.zprofile
BW_STATUS=$(bw status | jq -r ".status")
if [ $BW_STATUS == "unauthenticated" ]; then
	# Login to BitWarden Vault
 	export BW_SESSION=$(bw login --raw)
	echo "export BW_SESSION=$BW_SESSION" >> $HOME/.zshenv
	. $HOME/.zshenv
fi

eval "$(ssh-agent -s)"
PRIVATE_SSH_KEY="private_rsa"
PRIVATE_SSH_LOC="$HOME/.ssh/$PRIVATE_SSH_KEY"
if [ ! -f $PRIVATE_SSH_LOC ]; then
	# Add private ssh key
	KEY="$(bw get notes ssh --session $BW_SESSION)"
	mkdir $HOME/.ssh
	touch $PRIVATE_SSH_LOC
	echo $KEY >> $PRIVATE_SSH_LOC
fi
ssh-add --apple-use-keychain $PRIVATE_SSH_LOC

GITHUB_USERNAME="$(bw get notes a351877d-b841-4323-8c12-b0750151a00d --session $BW_SESSION)"
GITHUB_TOKEN="$(bw get notes 1372d340-bd72-4cdf-a458-afc700e924c8 --session $BW_SESSION)"

git config --global credential.interactive false
git config --global credential.ghe.contoso.com.provider github
git config --global credential.gitHubAuthModes "pat"
git credential-manager github login --username $GITHUB_USERNAME --pat $GITHUB_TOKEN --no-ui

if [ ! -d ~/.configurations ]; then
	git clone https://github.com/mehrad-meraji/dotfiles.git ~/.configurations
  	~/.configurations/go.sh
fi

# Install OH-MY-ZSH
if ! type omz >/dev/null 2>/dev/null; then 
	sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" --unattended --keep-zshrc
fi

BW_STATUS=$(bw status | jq -r ".status")

if [ $BW_STATUS == "unauthenticated" ]; then
	# Login to BitWarden Vault
	echo "BW_SESSION=$(bw login --raw)" >> ~/.zshenv && source ~/.zshenv
fi

eval "$(ssh-agent -s)"
PRIVATE_SSH_KEY="private_rsa"
PRIVATE_SSH_LOC="~/.ssh/$PRIVATE_SSH_KEY"
if [ ! -f $PRIVATE_SSH_LOC ]; then
	# Add private ssh key
	KEY="$(bw get notes ssh --session $BW_SESSION)"
	mkdir ~/.ssh
	touch $PRIVATE_SSH_LOC
	echo $KEY >> $PRIVATE_SSH_LOC
  chmod 600 $PRIVATE_SSH_LOC
fi

ssh-add --apple-use-keychain $PRIVATE_SSH_LOC

if [ ! -d ~/.configurations ]; then
	git clone https://github.com/mehrad-meraji/dotfiles.git ~/.configurations
  ~/.configurations/go.sh
fi

exec zsh -l
