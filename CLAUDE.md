# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This repository contains automated setup scripts for developer tools across different operating systems and environments. It provides initialization scripts for macOS and Linux (CentOS/RHEL), terminal configurations (iTerm2, Oh My Zsh, Vim), editor configurations (Cursor), and Git utilities.

## Directory Structure

```
os/
├── macos/setup.sh          # macOS system initialization
└── linux/setup_centos.sh   # CentOS/RHEL system initialization

terminal/
├── iterm2/                 # iTerm2 configuration and SSH login scripts
├── oh-my-zsh/              # Oh My Zsh configuration (theme, plugins)
└── vim/                    # Vim configuration with vim-plug and coc.nvim

editors/
└── cursor/                 # Cursor editor backup/restore scripts

vcs/git/
├── scripts/
│   ├── git_config.sh       # Interactive git global configurator
│   └── alias.sh            # Shell aliases for git workflows
└── config/
    └── github.gitconfig    # GitHub-specific settings
```

## OS Initialization Scripts

Both scripts follow the same architecture: bash 3.2+ compatible, color-coded output functions (`info()`, `success()`, `warn()`, `error()`, `step()`), system info detection, confirmation prompts, skip flags, and post-install notes.

**macOS** (`os/macos/setup.sh`):
```bash
./setup.sh                 # Full installation
./setup.sh --info-only     # Show system info only
./setup.sh --skip-casks    # Skip GUI applications
./setup.sh --skip-omz      # Skip Oh My Zsh
```
Installs: Homebrew, CLI tools (git, curl, wget, jq, tree, htop, gh, neovim), GUI apps (iTerm2, Sublime Text, Sogou Input, Obsidian), Node.js via nvm, Oh My Zsh.

**CentOS/RHEL** (`os/linux/setup_centos.sh`):
```bash
./setup_centos.sh          # Full installation
./setup_centos.sh --info-only
./setup.sh --skip-docker   # Skip Docker CE
```
Installs: Docker CE (with docker-compose-plugin), Git, Node.js LTS via NodeSource.

## Terminal Configuration

**Oh My Zsh** (`terminal/oh-my-zsh/`):
- `setup.sh` - Configures powerlevel10k theme, installs plugins (zsh-autosuggestions, zsh-syntax-highlighting), disables auto-updates
- `.p10k.zsh` - Powerlevel10k theme configuration backup
- Automatically installs Meslo Nerd Font via Homebrew

**Vim** (`terminal/vim/`):
- `setup.sh` - Installs vim-plug, plugins, and coc.nvim language servers
- `vimrc` - Complete vim configuration with NERDTree, fzf, coc.nvim, vim-fugitive
- Language servers: Python (pyright), Go, Java, Shell, JSON, YAML
- Leader key is comma (`,`)

**iTerm2** (`terminal/iterm2/`):
- `config/` - iTerm2 profile exports
- `scripts/login.exp` - Expect script for password-based SSH login: `./login.exp <user> <host> <password>`

## Editor Configuration

**Cursor** (`editors/cursor/`):
- `setup.sh --backup`  - Backs up settings.json, keybindings.json, and extensions list
- `setup.sh --restore` - Restores configuration to new machine
- Detects config paths across macOS (`~/Library/Application Support/Cursor/User/`), Linux, and Windows

## Git Utilities

**Global Configuration** (`vcs/git/scripts/git_config.sh`):
```bash
./git_config.sh          # Interactive setup for user.name, user.email, and recommended settings
./git_config.sh --dry-run # Preview without applying
```
Sets: core.editor, pull.rebase, push.autoSetupRemote, diff.algorithm, credential.helper, and 15+ other recommended configs.

**Shell Aliases** (`vcs/git/scripts/alias.sh`):
```bash
./alias.sh         # Install git aliases to ~/.zshrc or ~/.bashrc
./alias.sh --clean # Remove git aliases
```
Provides: `gitroot` (cd to repo root), `gitrebase` (fetch and rebase onto default branch), `gitprune` (delete merged branches), `gitalias` (list aliases).

## Common Patterns

All setup scripts:
- Use `set -euo pipefail` for strict error handling
- Include `--help` flag with usage information
- Create backups before modifying existing files
- Support `--dry-run` or similar preview modes where applicable
- Output color-coded status messages
