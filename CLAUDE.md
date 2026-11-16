# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This repository is a script-orchestration + configuration-asset library for
bootstrapping development environments on macOS and Linux (Ubuntu/Debian,
CentOS/RHEL, Alibaba Cloud Linux 3/4). It provides OS initialization, language
runtimes (Python / Go / Java / Rust), interactive shell / terminal / editor
configuration, network infrastructure (FRP / proxy / VPN), AI agent CLI setup
(Claude / Codex / Cursor Agent), Git utilities, and an Alinux 3 devbox Docker
image. Installer behavior is verified by a three-layer Bazel test system
(L1 host fakes / L2 Docker fakes / L3 real install), not by running real
installers during development.

## Directory Structure

```
setup.sh                    # Root orchestrator: interactive / --all / --modules
os/
├── lib/                    # Shared OS-init logic: packages.list parsing, DNF mirrors
├── macos/                  # macOS initialization, power, notifications, remote desktop
└── linux/                  # Ubuntu/Debian/CentOS/RHEL/Alinux initialization

languages/                  # Python / Go / Java / Rust runtimes; bash/ = Bash language notes
shell/                      # Interactive Bash / Zsh / Oh My Zsh / Starship (not script-language docs)
terminal/                   # Ghostty / iTerm2 / tmux / Yazi
editors/                    # Neovim / Vim / Cursor / VS Code
network/                    # FRP / proxy / VPN infrastructure
tools/                      # Bazel / Git / SSH (fssh) standalone tools
agents/                     # Claude / Codex / Cursor Agent / cookbook recipes
docker/                     # Alinux 3 devbox image (docker/alinux3/)
cache/                      # Offline installation assets
docs/                       # Design specs and implementation plans (docs/superpowers/)
tests/                      # Shell regression tests + shared Bazel test infrastructure
```

## Root Entry Point

The root `setup.sh` only parses arguments, selects modules, and orchestrates
module `setup.sh` scripts; it contains no tool-specific install logic.

```bash
bash setup.sh                          # Interactive menu (multi-select)
bash setup.sh --all                    # Non-interactive full install
bash setup.sh --modules python,go,claude
bash setup.sh --modules python --dry-run
```

Module names: `os`, `python`, `go`, `java`, `rust`, `nodejs`, `claude`,
`codex`, `cursor-agent`, `vscode`, `terminal`, `git`. Note `--all` covers
OS + languages + agent CLIs + VS Code; `nodejs`, `terminal`, and `git` are
only reachable via the menu or `--modules`. When adding a module, update the
help text, menu, module dispatch, and dry-run behavior together.

Directories such as `network/`, `tools/`, `agents/cookbook/`, and
`os/macos/remote-desktop/` have their own entry points and are NOT installed
by `./setup.sh --all`; run their `setup.sh` directly or read their README.

## OS Initialization Scripts

The three OS scripts (`os/macos/setup.sh`, `os/linux/setup_ubuntu.sh`,
`os/linux/setup_centos.sh`) follow the same architecture: bash 3.2+
compatible, color-coded output functions (`info()`, `success()`, `warn()`,
`error()`, `step()`), system info detection, confirmation prompts, skip
flags, and post-install notes. Shared logic lives in `os/lib/`:
`packages_list.sh` parses `packages*.list` lines (`name version source kind
tags`, filterable by kind cli/tui/gui and tags) for all three scripts;
`dnf_mirrors.sh` adds Aliyun companion mirrors while keeping official DNF
repos. Bash script-language baseline, pitfalls, patterns, and testing notes
live under `languages/bash/` (interactive shell config remains in `shell/`).

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

**Ubuntu/Debian** (`os/linux/setup_ubuntu.sh` + `packages.ubuntu.list`):
```bash
./setup_ubuntu.sh          # Full installation
./setup_ubuntu.sh --dry-run
./setup_ubuntu.sh --skip-docker   # Skip Docker CE
```

**CentOS/RHEL/Alinux** (`os/linux/setup_centos.sh` + `packages.centos.list`):
```bash
./setup_centos.sh          # Full installation
./setup_centos.sh --info-only
./setup_centos.sh --dry-run
./setup_centos.sh --skip-docker   # Skip Docker CE
```
Part 1: base deps. Part 2: Docker CE, Git, Node.js LTS, terminal tools from the packages list. `os/linux/aliyun_ecs_init.sh` is a separate Aliyun ECS first-boot initializer.

## Module Installers

Each module directory owns a self-contained `setup.sh` with `--help` and
(when it has side effects) `--dry-run` or an equivalent preview mode; the
root orchestrator and OS scripts delegate to them. Read the module README
before changing its installer. Notable entry points beyond the root menu:

- `languages/{python,go,java,rust}/setup.sh` — runtime installers (e.g. Python: pyenv + uv + AI packages; Go: runtime + gopls/dlv/air).
- `agents/{claude,codex,cursor-agent}/setup.sh install` — agent CLI install and managed config sync; sync must preserve user content that is not repo-managed.
- `agents/cookbook/setup.sh sync [--dry-run] [--target all|codex|...]` — links cookbook skills and Cursor rules into local agent consumption paths (e.g. `~/.cursor/skills`).
- `tools/ssh/setup.sh` — SSH client optimization and the `fssh` remote-session selector; back up SSH config before changes and state remote impact.
- `network/{frp,proxy,vpn}/` — independent entry points, not covered by the root `--all` (safety rules: see Repository Conventions).

## Docker Devbox

`docker/alinux3/` builds an x86_64 Alibaba Cloud Linux 3 `devbox` image
(Git + subcommands, Vim/Neovim + LSP, tmux, Bash tooling, Docker CE DinD,
Bazel, Go, Java, agent CLIs without API keys). The entrypoint starts an
inner `dockerd` as root, then drops to `admin`.

```bash
bash docker/alinux3/bake.sh                      # Build (Buildx bake)
docker run --privileged --rm -it alinux3-devbox:latest
```

See `docker/alinux3/README.md` for the plain `docker build` fallback and
details.

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

All `.sh` scripts in this repository:
- **Must** start with `set -euo pipefail` (after shebang / file header) for strict error handling
- Target macOS Bash 3.2+; prefer `${VAR}` when a parameter expansion is adjacent to multibyte characters (see `languages/bash/pitfalls.md`)
- Docker CLI commands must stay compatible with Docker CE 26. Do not unconditionally pass flags that 26's Buildx lacks (for example `docker buildx bake --allow`); probe the local CLI and add them only when advertised.
- Include `--help` flag with usage information
- Create backups before modifying existing files
- Support `--dry-run` or similar preview modes where applicable
- Output color-coded status messages

Language notes for writing Bash (pitfalls, compatibility, patterns, testing): `languages/bash/`.

## Repository Conventions

Follow this order when instructions conflict:

1. The user's current request
2. Repository-level `AGENTS.md` rules
3. More specific `AGENTS.md`, `CLAUDE.md`, or README files in the target directory
4. `README.md`, `BAZEL.md`, and each script's `--help` output

Keep module boundaries clear: put tool- or platform-specific logic in the
relevant subdirectory, never in the root orchestrator (see Root Entry Point).

For new or changed shell functionality:

- Follow `AGENTS.md` Shell conventions and `languages/bash/` (especially
  `compatibility.md` and `pitfalls.md`). Every `.sh` file must use
  `set -euo pipefail`.
- Keep scripts Bash 3.2-compatible and safe to rerun. Configuration changes must
  be idempotent and use markers, backups, or an equivalent managed update
  strategy; repeated runs must not duplicate or damage correct state.
- Keep Docker CLI usage compatible with Docker CE 26. Do not require newer
  bake/build flags such as `--allow` unless the local CLI advertises them.
- Prefer existing interfaces and markers over global state or copied logic.
  Keep CLI handling, use-case orchestration, and system/package/network
  adapters separated.
- Add or update Bazel tests for installer and configuration behavior. Prefer
  OS-profile × module coverage and run the applicable `macos`,
  `linux_ubuntu`, `linux_alinux3`, and `linux_alinux4` profiles. The current
  compatibility baseline is x86_64 only.
- Prefer cached installation assets under `cache/`. If a source, version,
  checksum, or architecture changes, update the corresponding tests.
- When choosing cache artifacts or installer packages, prefer fewer runtime
  dependencies and broader compatibility (e.g. static/musl binaries or
  official portable tarballs over AppImages that need FUSE/`fusermount`, or
  builds that require a newer glibc than Alinux/CentOS baselines).
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
# L1 default (no Docker, no real install) — run after script changes
bazel test //...
bazel test --config=l1 //languages/go/... //tools/git/...
# Single test target (naming: <module>_<profile>_test)
bazel test //os/linux:linux_setup_linux_alinux4_test
bazel test //tests:repository_structure_check
# Optional L2 (Docker + fakes; --config=docker is an alias)
bazel test --config=l2 //tools/git/...
# Optional L3 (REAL install in disposable containers / macOS host — slow)
bazel test --config=l3 --test_tag_filters=l3,-requires-macos //languages/go/...
```

Test infrastructure lives in `tests/common/`: `rules/devtools_tests.bzl`
(`devtools_module_tests`) generates the OS-profile × module targets from
`tests/common/profiles/` metadata; L1/L2 use fake `uname`/`apt`/`dnf`/`brew`,
L2 Docker targets are named `*_docker_test`, L3 real-install targets
`*_e2e_test`. Default to L1; add L2 when GNU/BSD or Linux userspace behavior
matters; consider L3 only when real-install paths or operational assertions
change (e.g. tmux prefix, vim/neovim behavior). Layer rules, per-module
minimum layers, and CI selectors (`[test#L1]`, `[test#L1,L2]`, `[test#skip]`;
aliases `ut`/`it`/`e2e`) are in `tests/README.md`; target examples and Bazel
setup are in `BAZEL.md`.

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
