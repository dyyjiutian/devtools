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
├── tmux/                   # tmux 3.7b installer + config (extended-keys)
└── vim/                    # Vim configuration with vim-plug and coc.nvim

editors/
└── cursor/                 # Cursor editor backup/restore scripts

vcs/git/
├── setup.sh                # Git one-shot setup
├── bin/                    # Portable git subcommands: git-rb/bc/wc/review
├── man/man1/               # man pages for the subcommands
└── scripts/                # Each maps to one setup.sh step
    ├── sub-command.sh      # Installs the git subcommands + man pages
    ├── config.sh           # Interactive git global configurator + perf tweaks
    └── alias.sh            # Shell alias installer (gitroot only)
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

**tmux** (`terminal/tmux/`):
- `setup.sh` - Installs tmux 3.7b (Linux: build from source to `~/.local` or `TMUX_PREFIX`; macOS: Homebrew), links `tmux.conf`, installs TPM plugins
- `tmux.conf` - Prefix `Ctrl-Space`, vi copy-mode, status bar, `extended-keys` for Codex Shift+Enter
- Linux OS init scripts call `setup.sh --install-bin-only` with `TMUX_PREFIX=/usr/local` (do not use distro tmux 2.7)

## Editor Configuration

**Cursor** (`editors/cursor/`):
- `setup.sh --backup`  - Backs up settings.json, keybindings.json, and extensions list
- `setup.sh --restore` - Restores configuration to new machine
- Detects config paths across macOS (`~/Library/Application Support/Cursor/User/`), Linux, and Windows

## Git Utilities

**Global Configuration** (`vcs/git/scripts/config.sh`):
```bash
./config.sh          # Interactive setup for user.name, user.email, and recommended settings
./config.sh --dry-run # Preview without applying
```
Sets: core.editor, pull.rebase, push.autoSetupRemote, diff.algorithm, credential.helper, plus status/pull/fetch/checkout performance tweaks, and 15+ other recommended configs.

**Git Subcommand Installer** (`vcs/git/scripts/sub-command.sh`):
```bash
./sub-command.sh          # Install git rb/bc/wc/review + man pages to ~/.local/bin
./sub-command.sh --dry-run
```

**Portable Git Subcommands** (`vcs/git/bin/`, installed to `~/.local/bin` by `setup.sh`):
- `git rb [branch]` - fetch and rebase onto the remote default (or given) branch
- `git bc [branch] [--dry-run]` - delete local branches merged into the target branch
- `git wc [branch] [--dry-run]` - remove merged linked worktrees and their branches
- `git review [branch]` - open a review, auto-detecting the platform from origin (GitHub PR / Alibaba GitLab `refs/for/<target>/<branch>` / GitLab MR / Gerrit)

These are self-contained scripts (not gitconfig aliases), so they survive removal of this repo. All support `--help` and auto-detect the default branch via `origin/HEAD`.

**Shell Alias** (`vcs/git/scripts/alias.sh`):
```bash
./alias.sh         # Install gitroot to ~/.zshrc or ~/.bashrc
./alias.sh --clean # Remove it
```
Provides only `gitroot` (cd to repo root); it stays an alias because `cd` must run in the active shell.

## Common Patterns

All setup scripts:
- Use `set -euo pipefail` for strict error handling
- Include `--help` flag with usage information
- Create backups before modifying existing files
- Support `--dry-run` or similar preview modes where applicable
- Output color-coded status messages
