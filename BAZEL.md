# Bazel Build System for DevTools

This repository uses Bazel 9 with bzlmod. The primary automated tests today are
shell `sh_test` targets, including an OS-profile × module matrix for setup scripts.

## Quick Start

### Install Bazel

```bash
# Using Homebrew (macOS)
brew install bazelisk

# Or using the official installer
curl -Lo bazel https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-amd64
chmod +x bazel
sudo mv bazel /usr/local/bin/
```

### Run Tests

```bash
# Existing macOS bats smoke test
bazel test //os/macos:macos_setup_bats_test

# Git + tmux matrix (L1 host profiles: linux_ubuntu, linux_centos, macos)
bazel test //tools/git/... //terminal/tmux/...

# Optional L2 Docker matrix (requires local Docker daemon)
bazel test --config=docker //tools/git/... //terminal/tmux/...
```

Default `.bazelrc` filters out `requires-docker` tags so plain `bazel test //...`
does not need Docker.

## Matrix Test Layout

| Path | Role |
|------|------|
| `testing/lib/` | Profile fakes, assertions, `run_module_test.sh` |
| `testing/docker/` | Ubuntu/CentOS Dockerfiles + `run_in_docker.sh` |
| `testing/rules/devtools_tests.bzl` | Expands profile × module into `sh_test` targets |
| `tools/git/tests/git_suite.sh` | Git suite |
| `terminal/tmux/tests/tmux_suite.sh` | tmux suite |

Example targets:

- `//tools/git:git_linux_ubuntu_test`
- `//tools/git:git_macos_test`
- `//terminal/tmux:tmux_linux_centos_test`
- `//tools/git:git_linux_ubuntu_docker_test` (tag `requires-docker`)

Design doc: `docs/superpowers/specs/2026-07-25-bazel-matrix-tests-design.md`.

## Key Files

| File | Purpose |
|------|---------|
| `.bazelversion` | Bazel version (9.0.0) |
| `MODULE.bazel` | bzlmod dependencies |
| `.bazelrc` | Test output + docker tag filters |
| `testing/BUILD.bazel` | Shared test assets |

## Module Dependencies

Direct deps in `MODULE.bazel`:

- `rules_shell` — `sh_test`
- `platforms`, `bazel_skylib`
- `rules_pkg` — available for future packaging
- `buildifier_prebuilt` (dev)
- `bats_core` via `http_archive` for `//os/macos:macos_setup_bats_test`

## Development Commands

```bash
bazel test //tools/git/... //terminal/tmux/...
bazel query 'tests(//tools/git/... + //terminal/tmux/...)'
bazel clean
bazel info
```
