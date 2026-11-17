#!/usr/bin/env bash
set -euo pipefail

resolve_source_path() {
  local path="$1" dir target
  while [[ -L "$path" ]]; do
    dir="$(cd "$(dirname "$path")" && pwd -P)"
    target="$(readlink "$path")"
    if [[ "$target" = /* ]]; then
      path="$target"
    else
      path="$dir/$target"
    fi
  done
  dir="$(cd "$(dirname "$path")" && pwd -P)"
  printf '%s/%s\n' "$dir" "$(basename "$path")"
}

SCRIPT_PATH="$(resolve_source_path "${BASH_SOURCE[0]}")"
ROOT="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd -P)"
if ! git -C "$ROOT" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "repository_structure_test.sh: cannot locate source Git worktree from $SCRIPT_PATH" >&2
  exit 1
fi

failures=0
required_dirs=(
  agents agents/claude agents/codex agents/cursor-agent
  cache
  editors editors/cursor editors/nvim editors/vim editors/vscode
  languages languages/go languages/java languages/python languages/rust
  network network/frp network/frp/client network/frp/server
  network/proxy network/proxy/client network/proxy/server
  network/vpn network/vpn/client network/vpn/exit network/vpn/relay
  os os/lib os/linux os/macos os/macos/agent-notify os/macos/power os/macos/remote-desktop
  shell shell/bash shell/oh-my-zsh shell/starship shell/zsh
  terminal terminal/ghostty terminal/iterm2 terminal/tmux terminal/yazi
  tests
  tools tools/bazel tools/git tools/ssh
)

for dir in "${required_dirs[@]}"; do
  if [[ ! -f "${ROOT}/${dir}/README.md" ]]; then
    echo "MISSING README: ${dir}/README.md" >&2
    failures=$((failures + 1))
  fi
done

obsolete_pattern='(^|[^[:alnum:]_-])(agent/|agent-cli/|ai/coding/|ai/local-llm/|ai/testing/|terminal/bash/|terminal/zsh/|terminal/oh-my-zsh/|terminal/starship/|terminal/nvim/|terminal/vim/|terminal/ssh/|tools/frp/|tools/proxy/|tools/vpn/|vcs/git/|mac/remote/|os/macos/nosleep\.sh|//testing[:/]|testing/)'
obsolete_refs=$(cd "$ROOT" && git grep -n -E "$obsolete_pattern" -- ':!docs/superpowers/**' ':!tests/repository_structure_test.sh' || true)
if [[ -n "$obsolete_refs" ]]; then
  echo "OBSOLETE PATH REFERENCES:" >&2
  echo "$obsolete_refs" >&2
  failures=$((failures + 1))
fi

# Editor e2e must fail fast. The enormous default allows a 3600s timeout, and a
# hung vim once burned a whole CI hour (editors/vim/README.md Issues 2026-11-17).
# Slow real-install suites (rust/vpn/proxy) legitimately need enormous, so only
# the editor targets are constrained here.
for editor_build in editors/vim/BUILD.bazel editors/nvim/BUILD.bazel; do
  bounded=$(grep -c 'size = "large"' "${ROOT}/${editor_build}" || true)
  if [[ "$bounded" -lt 2 ]]; then
    echo "MISSING BOUNDED E2E TIMEOUT: ${editor_build} must set size = \"large\" (900s) on both e2e targets (found ${bounded})" >&2
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  echo "FAIL: ${failures} repository structure checks failed" >&2
  exit 1
fi

echo "PASS: repository structure documentation and references"
