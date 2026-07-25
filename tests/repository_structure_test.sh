#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

failures=0
required_dirs=(
  agents agents/claude agents/codex agents/cursor-agent
  cache
  editors editors/cursor editors/nvim editors/vim editors/vscode
  lang lang/go lang/java lang/python lang/rust
  network network/frp network/frp/client network/frp/server
  network/proxy network/proxy/client network/proxy/server
  network/vpn network/vpn/client network/vpn/exit network/vpn/relay
  os os/linux os/macos os/macos/agent-notify os/macos/power os/macos/remote-desktop
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

obsolete_pattern='(^|[^[:alnum:]_-])(agent/|agent-cli/|ai/coding/|ai/local-llm/|ai/testing/|terminal/bash/|terminal/zsh/|terminal/oh-my-zsh/|terminal/starship/|terminal/nvim/|terminal/vim/|terminal/ssh/|tools/frp/|tools/proxy/|tools/vpn/|vcs/git/|mac/remote/|os/macos/nosleep\.sh)'
obsolete_refs=$(cd "$ROOT" && git grep -n -E "$obsolete_pattern" -- ':!docs/superpowers/**' ':!tests/repository_structure_test.sh' || true)
if [[ -n "$obsolete_refs" ]]; then
  echo "OBSOLETE PATH REFERENCES:" >&2
  echo "$obsolete_refs" >&2
  failures=$((failures + 1))
fi

if [[ "$failures" -ne 0 ]]; then
  echo "FAIL: ${failures} repository structure checks failed" >&2
  exit 1
fi

echo "PASS: repository structure documentation and references"
