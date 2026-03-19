# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This repository contains automated setup scripts for developer tools across different operating systems. It provides initialization scripts for macOS and Linux (CentOS/RHEL), along with terminal configuration files.

## Directory Structure

```
os/
├── macos/install.sh      # macOS initialization script
└── linux/install_centos.sh  # CentOS/RHEL initialization script

terminal/iterm2/
├── config/               # iTerm2 configuration exports
├── scripts/login.exp     # expect script for password-based SSH login
└── README.md             # iTerm2 configuration guide (Chinese)
```

## Running the Install Scripts

Both install scripts support similar options:

```bash
# macOS
./os/macos/install.sh                 # Full installation
./os/macos/install.sh --info-only     # Show system info only
./os/macos/install.sh --skip-casks    # Skip GUI applications
./os/macos/install.sh --help          # Show usage

# CentOS/RHEL
./os/linux/install_centos.sh          # Full installation
./os/linux/install_centos.sh --info-only
./os/linux/install_centos.sh --skip-docker
./os/linux/install_centos.sh --help
```

## Script Architecture

Both install scripts follow the same pattern:
- Bash 3.2+ compatible (for macOS default bash)
- Color-coded output functions: `info()`, `success()`, `warn()`, `error()`, `step()`
- System info detection before installation
- Confirmation prompt before proceeding
- Skip flags for selective installation
- Post-install notes with next steps

## What Gets Installed

**macOS** (`os/macos/install.sh`):
- Homebrew (auto-update if installed)
- CLI tools: git, curl, wget, jq, tree, htop, gh
- GUI apps (casks): iTerm2, Sublime Text, Sogou Input, Obsidian
- Node.js via nvm

**CentOS/RHEL** (`os/linux/install_centos.sh`):
- Docker CE (with docker-compose-plugin)
- Git
- Node.js LTS via NodeSource

## iTerm2 Setup

The `terminal/iterm2/` directory contains:
- Configuration exports for iTerm2 profiles
- `login.exp` - expect script for automated SSH login with password
  - Usage: `./login.exp <user> <host> <password>`
  - Can be configured in iTerm2 Profile Command for automatic login