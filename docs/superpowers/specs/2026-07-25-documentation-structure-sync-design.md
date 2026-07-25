# Documentation and Structure Reference Synchronization

## Goal

Synchronize all repository documentation, scripts, tests, and help text with the
current directory structure, and add concise README files to every functional
or module directory.

## Current Structure

The current layout is intentionally preserved:

- `agents/` contains Agent-specific CLI configuration and future best practices.
- `editors/` contains Vim, Neovim, Cursor, and VS Code assets.
- `lang/` contains language runtime setup scripts.
- `network/` contains FRP, proxy, and VPN infrastructure.
- `os/` contains platform initialization and macOS-specific services.
- `shell/` contains Bash, Zsh, Oh My Zsh, and Starship configuration.
- `terminal/` contains terminal emulators and terminal applications.
- `tools/` is a temporary home for Bazel, Git, and SSH utilities that may be
  classified more narrowly in a later restructuring.

No directories will be moved in this change.

## Path Mapping

All active references will use these paths:

| Old path | Current path |
|---|---|
| `agent/` | `agents/` |
| `agent/notify/` | `os/macos/agent-notify/` |
| `terminal/bash/` | `shell/bash/` |
| `terminal/zsh/` | `shell/zsh/` |
| `terminal/oh-my-zsh/` | `shell/oh-my-zsh/` |
| `terminal/starship/` | `shell/starship/` |
| `terminal/nvim/` | `editors/nvim/` |
| `terminal/vim/` | `editors/vim/` |
| `tools/frp/` | `network/frp/` |
| `tools/proxy/` | `network/proxy/` |
| `tools/vpn/` | `network/vpn/` |
| `mac/remote/` | `os/macos/remote-desktop/` |
| `os/macos/nosleep.sh` | `os/macos/power/nosleep.sh` |
| `vcs/git/` | `tools/git/` |
| `terminal/ssh/` | `tools/ssh/` |

References in historical design and plan documents will also be updated so all
copyable commands in the repository resolve to existing paths.

## README Scope

Add or update README files for directories that represent a user-facing
capability, executable module, platform module, or repository-level support
area. Do not add repetitive README files to pure asset directories such as
`config/`, `profiles/`, `bin/`, `man/`, `docker/`, `nginx/`, `binaries/`, or
other directories whose contents are subordinate data files.

Each new README will state the directory's responsibility, entry points,
dependencies or platform constraints, and a minimal usage example where the
directory contains executable setup logic.

## Verification

The change will add a repository-structure regression test that checks:

1. Required functional/module directories have a README.
2. Known obsolete directory references do not remain in tracked content.
3. Existing shell syntax and regression tests pass after path updates.
4. `git diff --check` reports no whitespace errors.
