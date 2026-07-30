# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This repository contains automated setup scripts for developer tools across different operating systems and environments. It provides initialization scripts for macOS and Linux (CentOS/RHEL), terminal configurations (iTerm2, Oh My Zsh, Vim), editor configurations (Cursor), and Git utilities.

## Directory Structure

```
os/
├── macos/                  # macOS initialization, power, notifications, remote desktop
└── linux/                  # Ubuntu/Debian/CentOS/RHEL initialization

languages/                       # Python / Go / Java / Rust runtimes
shell/                      # Bash / Zsh / Oh My Zsh / Starship
terminal/                   # Ghostty / iTerm2 / tmux / Yazi
editors/                    # Neovim / Vim / Cursor / VS Code
network/                    # FRP / proxy / VPN infrastructure
tools/                      # Bazel / Git / SSH standalone tools
agents/                     # Claude / Codex / Cursor Agent / cookbook recipes
cache/                      # Offline installation assets
tests/                      # Shell regression tests
```

## OS Initialization Scripts

Both scripts follow the same architecture: bash 3.2+ compatible, color-coded output functions (`info()`, `success()`, `warn()`, `error()`, `step()`), system info detection, confirmation prompts, skip flags, and post-install notes.

**macOS** (`os/macos/setup.sh` + `packages.list`):
```bash
./setup.sh                 # Full installation (base + packages.list)
./setup.sh --info-only     # Show system info only
./setup.sh --dry-run       # Preview
./setup.sh --base-only     # Homebrew only
./setup.sh --skip-casks    # Skip GUI applications
./setup.sh --skip-omz      # Skip Oh My Zsh
```
Part 1: Homebrew. Part 2: CLI/GUI/Node/Oh My Zsh from `packages.list`.

**Ubuntu/Debian** (`os/linux/setup_ubuntu.sh` + `packages.ubuntu.list`) and **CentOS/RHEL** (`os/linux/setup_centos.sh` + `packages.centos.list`):
```bash
./setup_centos.sh          # Full installation
./setup_centos.sh --info-only
./setup_centos.sh --dry-run
./setup_centos.sh --skip-docker   # Skip Docker CE
```
Part 1: base deps. Part 2: Docker CE, Git, Node.js LTS, terminal tools from the packages list.

## Terminal Configuration

**Oh My Zsh** (`shell/oh-my-zsh/`):
- `setup.sh` - Configures powerlevel10k theme, installs plugins (zsh-autosuggestions, zsh-syntax-highlighting), disables auto-updates
- `.p10k.zsh` - Powerlevel10k theme configuration backup
- Automatically installs Meslo Nerd Font via Homebrew

**Vim** (`editors/vim/`):
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

**Global Configuration** (`tools/git/scripts/config.sh`):
```bash
./config.sh          # Interactive setup for user.name, user.email, and recommended settings
./config.sh --dry-run # Preview without applying
```
Sets: core.editor, pull.rebase, push.autoSetupRemote, diff.algorithm, credential.helper, plus status/pull/fetch/checkout performance tweaks, and 15+ other recommended configs.

**Git Subcommand Installer** (`tools/git/scripts/sub-command.sh`):
```bash
./sub-command.sh          # Install git rb/bc/wc/review/sparse-clone + man pages to ~/.local/bin
./sub-command.sh --dry-run
```

**Portable Git Subcommands** (`tools/git/bin/`, installed to `~/.local/bin` by `setup.sh`):
- `git rb [branch]` - fetch and rebase onto the remote default (or given) branch
- `git bc [branch] [--dry-run]` - delete local branches merged into the target branch
- `git wc [branch] [--dry-run]` - remove merged linked worktrees and their branches
- `git review [branch]` - open a review, auto-detecting the platform from origin (GitHub PR / Alibaba GitLab `refs/for/<target>/<branch>` / GitLab MR / Gerrit)
- `git sparse-clone <url> [paths...]` - sparse-clone selected directories (cone); `--append` adds paths to an existing sparse repo

These are self-contained scripts (not gitconfig aliases), so they survive removal of this repo. All support `--help` and auto-detect the default branch via `origin/HEAD`.

**Shell Alias** (`tools/git/scripts/alias.sh`):
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

## Repository Conventions

Follow this order when instructions conflict:

1. The user's current request
2. Repository-level `AGENTS.md` rules
3. More specific `AGENTS.md`, `CLAUDE.md`, or README files in the target directory
4. `README.md`, `BAZEL.md`, and each script's `--help` output

Keep module boundaries clear. The root `setup.sh` should only parse arguments,
select modules, orchestrate workflows, and implement dry-run behavior. Put
tool- or platform-specific logic in the relevant subdirectory. Directories
such as `network/`, `tools/`, `agents/`, and `os/macos/remote-desktop/` may
have their own entry points and are not necessarily included by
`./setup.sh --all`.

For new or changed shell functionality:

- Keep scripts Bash-compatible and safe to rerun. Configuration changes must
  be idempotent and use markers, backups, or an equivalent managed update
  strategy; repeated runs must not duplicate or damage correct state.
- Prefer existing interfaces and markers over global state or copied logic.
  Keep CLI handling, use-case orchestration, and system/package/network
  adapters separated.
- Add or update Bazel tests for installer and configuration behavior. Prefer
  OS-profile × module coverage and run the applicable `macos`,
  `linux_ubuntu`, `linux_alinux3`, and `linux_alinux4` profiles. The current
  compatibility baseline is x86_64 only.
- Prefer cached installation assets under `cache/`. If a source, version,
  checksum, or architecture changes, update the corresponding tests.
- Do not commit API keys, passwords, UUIDs, private keys, personal machine
  paths, or temporary generated configuration.

Preview installation behavior before making real system changes:

```bash
bash setup.sh --help
bash setup.sh --modules python --dry-run
bash languages/python/setup.sh --help
bash languages/python/setup.sh --dry-run
```

Network, service, firewall, VPN, proxy, FRP, SSH, and remote-host operations
must state their permissions, exact targets, risks, and rollback path. Do not
run real installations merely to validate syntax or run remote/network
changes without an explicit target and recovery plan.

## Documentation and Issue Records

The root README is user-facing; module READMEs describe module operation and
maintenance; this file and `AGENTS.md` guide development agents. Keep
commands copyable and document when `sudo`, network access, a particular OS,
or extra tools are required. Treat scripts and tests as the source of truth;
do not expand undocumented or unverified promises.

When fixing an issue in an existing module, add an entry to that module's
`README.md` under `## Issues` or `## Issues / FAQ` using this format:

```text
YYYY-MM-DD — Short problem description
```

Include the symptom, root cause, and solution, with reproduction or repair
commands when useful.

## Verification Workflow

Choose the smallest sufficient checks for the changed scope. At minimum,
inspect the diff and run `git diff --check`. For shell changes, use `bash -n`
and the relevant regression tests. When available, validate installer changes
with `--help`, `--dry-run`, cached paths, repeated execution, and rollback
paths.

```bash
bash -n setup.sh
bazel test //os/linux/... //shell/bash/...
bash os/macos/run_bats.sh
bazel test //...
bazel test //os/macos:macos_setup_bats_test
bazel test //tools/git/... //terminal/tmux/...
```

If `bazel` or `bats` is unavailable, report that it was not run; never treat
missing tooling as a passing result. Do not run real installers during routine
validation.

## Git Workflow

Preserve unrelated user changes and inspect the worktree before editing. Do
not use destructive Git cleanup commands unless the user explicitly requests
them. When using a Superpowers implementation workflow, work in a dedicated
Git worktree.

Before submitting changes, check:

```bash
git status --short
git diff --check
git diff
```

Use concise conventional commit messages. After verification, prefer the
repository workflow:

```bash
git rb && git review
```

If that workflow fails, fetch and rebase the default branch before falling
back to the normal push and PR flow. Resolve conflicts and verify before
continuing. Never force-push over another person's work without explicit
authorization.
