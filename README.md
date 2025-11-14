# Oranges - macOS Bootstrap Script

A modular macOS setup script that automates the installation of development tools and dotfiles.

## Structure

```
oranges/
├── rind.sh              # Main orchestration script
├── peel.sh              # Alternative script (preserved)
└── lib/                 # Modular library files
    ├── sudo-keepalive.sh   # Sudo session management
    ├── system-deps.sh      # System dependencies (Xcode, Rosetta, Homebrew)
    ├── bitwarden.sh        # Bitwarden (rbw) authentication and retrieval
    ├── git-config.sh       # Git credential configuration
    └── chezmoi.sh          # Chezmoi initialization
```

## Usage

### Standard Usage

```bash
curl -fsSL 'https://raw.githubusercontent.com/mehrad-meraji/oranges/refs/heads/main/rind.sh' | bash
```

### With Environment Variables

You can customize the behavior with environment variables:

```bash
# Specify Bitwarden email to skip the prompt
RBW_EMAIL="your-email@example.com" \
curl -fsSL 'https://raw.githubusercontent.com/mehrad-meraji/oranges/refs/heads/main/rind.sh' | bash

# Provide GitHub token directly (skips Bitwarden lookup)
GITHUB_TOKEN="ghp_yourtoken" \
curl -fsSL 'https://raw.githubusercontent.com/mehrad-meraji/oranges/refs/heads/main/rind.sh' | bash

# Specify custom GitHub username or Bitwarden item name
GITHUB_USERNAME="your-github-username" \
GITHUB_ITEM_NAME="Your Bitwarden Item Name" \
curl -fsSL 'https://raw.githubusercontent.com/mehrad-meraji/oranges/refs/heads/main/rind.sh' | bash
```

## What It Does

1. **Sudo Authentication** - Requests sudo password once and maintains the session
2. **System Dependencies** - Installs Xcode CLI Tools, Rosetta (on ARM), and Homebrew
3. **Password Manager** - Sets up rbw (Bitwarden CLI) with pinentry for secure credential access
4. **GitHub Credentials** - Retrieves GitHub PAT from Bitwarden and configures git
5. **Dotfiles** - Initializes chezmoi with your private dotfiles repository

## Requirements

- macOS (tested on Apple Silicon and Intel)
- Internet connection
- Bitwarden account with GitHub PAT stored in an item with a "Token" custom field

## Library Modules

Each library file is focused on a specific concern:

- **sudo-keepalive.sh**: Prevents sudo timeout during long-running operations
- **system-deps.sh**: Handles installation of system-level dependencies
- **bitwarden.sh**: Manages rbw authentication and credential retrieval
- **git-config.sh**: Configures git with GitHub credentials
- **chezmoi.sh**: Initializes and applies chezmoi dotfiles

## Development

To test locally:

```bash
./rind.sh
```

Or with custom variables:

```bash
RBW_EMAIL="test@example.com" GITHUB_ITEM_NAME="Test Token" ./rind.sh
```

## Notes

- The script uses `rbw` (Rust Bitwarden CLI) instead of the official `bw` for better stdin handling
- All interactive prompts are isolated to prevent conflicts with piped script execution
- Sudo password is cached in the background to avoid repeated prompts
- Git credentials are stored in `~/.git-credentials` with secure permissions (600)

