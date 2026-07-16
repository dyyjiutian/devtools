#!/usr/bin/env bash

set -euo pipefail

DEV_USER="${DEV_USER:-admin}"
DEV_HOME="${DEV_HOME:-/home/${DEV_USER}}"
DEV_UID="${DEV_UID:-1000}"
DEV_GID="${DEV_GID:-1000}"
TEMPLATE_ROOT="${DEVTOOLS_TEMPLATE_ROOT:-/etc/devtools/templates}"

copy_file_if_missing() {
  local source="$1" target="$2"
  if [[ ! -e "$target" ]]; then
    mkdir -p "$(dirname "$target")"
    cp "$source" "$target"
  fi
}

copy_tree_missing() {
  local source="$1" target="$2"
  mkdir -p "$target"
  for item in "$source"/*; do
    [[ -e "$item" ]] || continue
    local name="$(basename "$item")"
    if [[ ! -e "$target/$name" ]]; then
      cp -a "$item" "$target/$name"
    fi
  done
}

main() {
  [[ "$(id -u)" -eq 0 ]] || {
    echo "config synchronization requires root" >&2
    exit 1
  }

  mkdir -p "$DEV_HOME/.config"
  copy_file_if_missing /etc/skel/.bashrc "$DEV_HOME/.bashrc"
  copy_file_if_missing /etc/skel/.zshrc "$DEV_HOME/.zshrc"
  copy_file_if_missing /etc/skel/.gitconfig "$DEV_HOME/.gitconfig"
  copy_file_if_missing /etc/skel/.vimrc "$DEV_HOME/.vimrc"
  copy_file_if_missing /etc/skel/.tmux.conf "$DEV_HOME/.tmux.conf"
  copy_file_if_missing /etc/skel/.config/starship.toml "$DEV_HOME/.config/starship.toml"
  copy_tree_missing /etc/skel/.config/nvim "$DEV_HOME/.config/nvim"

  copy_tree_missing "$TEMPLATE_ROOT/claude/config" "$DEV_HOME/.claude"
  copy_tree_missing "$TEMPLATE_ROOT/codex/config" "$DEV_HOME/.codex"
  copy_tree_missing "$TEMPLATE_ROOT/cursor-agent/config" "$DEV_HOME/.cursor"
  chown -R "$DEV_UID:$DEV_GID" "$DEV_HOME"
}

main "$@"
