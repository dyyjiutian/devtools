# Dotfile Copy Deploy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy vimrc and tmux.conf via real `cp` (with backup), not symlinks.

**Architecture:** Keep deploy logic inside each module `setup.sh`. Match nvim / vim `--restore` copy semantics. Update tmux suite assertions.

**Tech Stack:** Bash, existing `testing/lib` module suite + Bazel `devtools_module_tests`.

## Global Constraints

- Overwrite every run; backup non-symlink destinations first.
- Remove existing symlink before `cp` (do not write through).
- Do not change binary/tool symlink behavior or cookbook defaults.
- Prefer portable Bash (`cp`, `rm -f`); no GNU-only `cp` flags.

---

### Task 1: Update tmux deploy_config test (TDD)

**Files:**
- Modify: `terminal/tmux/tests/tmux_suite.sh`

- [x] Change `test_deploy_config` to assert regular file + content match, not symlink
- [x] Run suite; expect FAIL against current symlink implementation

### Task 2: Implement tmux copy deploy

**Files:**
- Modify: `terminal/tmux/setup.sh`
- Modify: `terminal/tmux/README.md`

- [x] Replace `ln -sf` with backup + remove-symlink + `cp`
- [x] Update help text
- [x] Add Issues entry
- [x] Re-run suite; expect PASS

### Task 3: Implement vim copy deploy

**Files:**
- Modify: `editors/vim/setup.sh`
- Modify: `editors/vim/README.md`

- [x] Align main path and `--restore` with same backup/rm-symlink/`cp` semantics
- [x] Update help + README + Issues
- [x] `bash -n editors/vim/setup.sh`

### Task 4: Verify

- [x] `bash -n` on both setup scripts
- [x] `git diff --check`
- [x] Run tmux module suite (host or `bazel test //terminal/tmux/...` if available)
