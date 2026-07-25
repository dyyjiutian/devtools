# Documentation and Structure Reference Synchronization Implementation Plan

> Required execution sub-skill: use superpowers:executing-plans to implement this plan task by task.

**Goal:** Synchronize all repository references with the current directory layout and add useful README files for every functional or module directory.

**Architecture:** Keep the current directory layout unchanged. Add a structure regression test first, update executable scripts and tests, update all active and historical documentation references, then add concise module READMEs. Pure asset directories remain undocumented unless they already have a README.

**Tech Stack:** Bash, Markdown, ripgrep, existing shell regression tests, optional Bats/Bazel checks.

## Global constraints

- Preserve the current top-level directories: agents, cache, docs, editors, languages, network, os, shell, terminal, tests, tools.
- Use current paths: agents, shell, editors, network, os/macos/agent-notify, os/macos/power, os/macos/remote-desktop, tools/git, and tools/ssh.
- Do not change installer behavior except for correcting moved-path references.
- Add READMEs only to user-facing, executable, platform, category, or module directories.
- Do not add repetitive READMEs to config, profiles, rules, bin, man, docker, nginx, binaries, or other pure asset directories.
- Update historical plans and specs when they contain copyable commands, so all repository examples resolve.

---

### Task 1: Add a failing structure regression test

Files:
- Create: tests/repository_structure_test.sh

Required README directories:
agents, agents/claude, agents/codex, agents/cursor-agent, cache, editors, editors/cursor, editors/nvim, editors/vim, editors/vscode, languages, languages/go, languages/java, languages/python, languages/rust, network, network/frp, network/frp/client, network/frp/server, network/proxy, network/proxy/client, network/proxy/server, network/vpn, network/vpn/client, network/vpn/exit, network/vpn/relay, os, os/linux, os/macos, os/macos/agent-notify, os/macos/power, os/macos/remote-desktop, shell, shell/bash, shell/oh-my-zsh, shell/starship, shell/zsh, terminal, terminal/ghostty, terminal/iterm2, terminal/tmux, terminal/yazi, tests, tools, tools/bazel, tools/git, tools/ssh.

Test behavior:
- Fail if any required directory lacks README.md.
- Fail if tracked content contains obsolete prefixes: agent/, agent-cli/, ai/coding/, ai/local-llm/, ai/testing/, terminal/bash/, terminal/zsh/, terminal/oh-my-zsh/, terminal/starship/, terminal/nvim/, terminal/vim/, terminal/ssh/, tools/frp/, tools/proxy/, tools/vpn/, vcs/git/, mac/remote/, or os/macos/nosleep.sh.
- Exclude .git and .worktrees from the scan.

Verification:
- Run bash tests/repository_structure_test.sh.
- Confirm it fails for the current missing READMEs and stale references.

Commit: test: enforce current structure documentation

### Task 2: Update executable scripts and tests

Files to inspect and update:
- setup.sh
- os/macos/setup.sh
- os/linux/setup_ubuntu.sh
- os/linux/setup_centos.sh
- terminal/ghostty/setup.sh
- cache/download.sh
- tests/git_setup_test.sh
- tests/linux_setup_scripts_test.sh
- network/vpn scripts and operational docs containing old paths.

Required mapping:
- agent/ to agents/
- agent/notify/ to os/macos/agent-notify/
- terminal/bash, terminal/zsh, terminal/oh-my-zsh, terminal/starship to shell/ equivalents.
- terminal/nvim and terminal/vim to editors/ equivalents.
- tools/frp, tools/proxy, tools/vpn to network/ equivalents.
- mac/remote to os/macos/remote-desktop/.
- os/macos/nosleep.sh to os/macos/power/nosleep.sh.
- vcs/git to tools/git.
- terminal/ssh to tools/ssh.

Update root help and post-install notes to remove deleted ai modules and describe current categories. Do not reintroduce deleted installers.

Verification:
- Run bash -n on all shell scripts and Bats files.
- Run tests/git_setup_test.sh and tests/linux_setup_scripts_test.sh.

### Task 3: Update documentation references

Files:
- README.md
- AGENTS.md
- CLAUDE.md
- terminal/README.md
- all module README files containing old paths
- docs/superpowers/plans/*.md
- docs/superpowers/specs/*.md

Update structure trees, cd commands, links, examples, help text, contributor guidance, and copyable plan/spec commands. Preserve behavior descriptions and historical intent.

Verification:
- Run tests/repository_structure_test.sh.
- Confirm it reports no obsolete path references.

### Task 4: Add functional/module README files

Add or update README.md for every required directory listed in Task 1. Each README must state responsibility, entry points, platform or dependency constraints, and a minimal usage example when executable setup exists.

Do not add new README files to subordinate pure asset directories. Link to those assets from the nearest module README when useful.

Verification:
- Run tests/repository_structure_test.sh.
- Confirm all required functional/module directories are covered.

### Task 5: Full verification

Run:
- bash -n on all .sh and .bats files.
- bash tests/repository_structure_test.sh.
- bash tests/git_setup_test.sh.
- bash tests/linux_setup_scripts_test.sh.
- bash os/macos/run_bats.sh; if Bats or Bazel is unavailable, record that explicitly.
- git diff --check.

Review git status, changed paths, and sensitive content before committing.

Commit: docs: synchronize structure references and module guides
