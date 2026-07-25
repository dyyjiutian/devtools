#!/usr/bin/env bash
# Install portable git subcommands (git rb / bc / wc / review) and their man
# pages into ~/.local/bin and ~/.local/share/man, and ensure both are on PATH /
# MANPATH via the shell rc file. Self-contained scripts survive removal of this
# repository.
#
# Usage:
#   ./sub-command.sh            Install subcommands + man pages
#   ./sub-command.sh --dry-run  Print actions without changing anything
#   ./sub-command.sh --help     Show this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_SRC_DIR="$GIT_ROOT_DIR/bin"
MAN_SRC_DIR="$GIT_ROOT_DIR/man/man1"
LOCAL_BIN_DIR="$HOME/.local/bin"
LOCAL_MAN_DIR="$HOME/.local/share/man/man1"

COMMANDS=(git-rb git-bc git-wc git-review)
MANPAGES=(git-rb.1 git-bc.1 git-wc.1 git-review.1)

DRY_RUN=false

info()    { echo -e "\033[34m[INFO]\033[0m $1"; }
success() { echo -e "\033[32m[OK]\033[0m $1"; }
warn()    { echo -e "\033[33m[WARN]\033[0m $1"; }
error()   { echo -e "\033[31m[ERROR]\033[0m $1"; }
step()    { echo -e "\033[36m[STEP]\033[0m $1"; }

usage() {
  cat <<'EOF'
Usage: ./sub-command.sh [OPTION]

Install portable git subcommands and man pages into ~/.local/bin and
~/.local/share/man, then ensure they are on PATH / MANPATH.

Subcommands installed:
  git rb [branch]              fetch and rebase onto the remote default branch
  git bc [branch] [--dry-run]  delete local branches merged into the target branch
  git wc [branch] [--dry-run]  remove merged linked worktrees and their branches
  git review [branch]          open a PR / MR / Gerrit review, auto-detecting platform

Options:
  (none)       Install subcommands and man pages
  -n, --dry-run  Print what would be done without making changes
  -h, --help   Show this help message and exit
EOF
}

case "${1:-}" in
  -h|--help)    usage; exit 0 ;;
  -n|--dry-run) DRY_RUN=true ;;
  "")           ;;
  *)
    echo "Unknown option: $1" >&2
    echo "Run '$(basename "$0") --help' for usage." >&2
    exit 1
    ;;
esac

run_cmd() {
  if [[ "$DRY_RUN" == "true" ]]; then
    printf '[DRY RUN] '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

detect_rc_file() {
  local shell_name
  shell_name="$(basename "${SHELL:-}")"
  case "$shell_name" in
    zsh)  echo "$HOME/.zshrc" ;;
    bash) echo "$HOME/.bashrc" ;;
    *)
      if [[ -f "$HOME/.zshrc" ]]; then
        echo "$HOME/.zshrc"
      else
        echo "$HOME/.bashrc"
      fi
      ;;
  esac
}

install_commands() {
  step "安装 Git 子命令 ..."

  if [[ ! -d "$BIN_SRC_DIR" ]]; then
    warn "未找到 Git 子命令目录: $BIN_SRC_DIR"
    return
  fi

  run_cmd mkdir -p "$LOCAL_BIN_DIR"

  local cmd src dst
  for cmd in "${COMMANDS[@]}"; do
    src="$BIN_SRC_DIR/$cmd"
    dst="$LOCAL_BIN_DIR/$cmd"
    if [[ ! -f "$src" ]]; then
      warn "未找到 $src，跳过"
      continue
    fi
    run_cmd install -m 0755 "$src" "$dst"
  done
}

install_manpages() {
  if [[ ! -d "$MAN_SRC_DIR" ]]; then
    warn "未找到 Git manpage 目录: $MAN_SRC_DIR"
    return
  fi

  run_cmd mkdir -p "$LOCAL_MAN_DIR"

  local page src dst
  for page in "${MANPAGES[@]}"; do
    src="$MAN_SRC_DIR/$page"
    dst="$LOCAL_MAN_DIR/$page"
    if [[ ! -f "$src" ]]; then
      warn "未找到 $src，跳过"
      continue
    fi
    run_cmd install -m 0644 "$src" "$dst"
  done
}

ensure_paths() {
  local rc_file
  rc_file="$(detect_rc_file)"

  local marker="# devtools git commands PATH"
  local line='[[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin:$PATH"'
  local man_marker="# devtools git commands MANPATH"
  local man_line='[[ ":${MANPATH:-}:" != *":$HOME/.local/share/man:"* ]] && export MANPATH="$HOME/.local/share/man:${MANPATH:-}"'

  if [[ "$DRY_RUN" == "true" ]]; then
    if [[ -f "$rc_file" ]] && grep -qF "$marker" "$rc_file"; then
      info "$LOCAL_BIN_DIR PATH 配置已存在，跳过"
    else
      info "[试运行] 将把 $LOCAL_BIN_DIR 加入 $rc_file"
    fi
    if [[ -f "$rc_file" ]] && grep -qF "$man_marker" "$rc_file"; then
      info "$HOME/.local/share/man MANPATH 配置已存在，跳过"
    else
      info "[试运行] 将把 $HOME/.local/share/man 加入 $rc_file"
    fi
    return
  fi

  touch "$rc_file"
  if grep -qF "$marker" "$rc_file"; then
    success "$LOCAL_BIN_DIR PATH 配置已存在，跳过"
  else
    {
      printf '\n%s\n' "$marker"
      printf '%s\n' "$line"
    } >> "$rc_file"
    success "已将 $LOCAL_BIN_DIR 加入 $rc_file"
  fi

  if grep -qF "$man_marker" "$rc_file"; then
    success "$HOME/.local/share/man MANPATH 配置已存在，跳过"
  else
    {
      printf '\n%s\n' "$man_marker"
      printf '%s\n' "$man_line"
    } >> "$rc_file"
    success "已将 $HOME/.local/share/man 加入 $rc_file"
  fi
}

install_commands
install_manpages
ensure_paths

echo ""
if [[ "$DRY_RUN" == "true" ]]; then
  echo "[DRY RUN] No changes were made. Remove --dry-run to apply."
else
  success "Git 子命令安装完成（git rb / bc / wc / review）"
fi
