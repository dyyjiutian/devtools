#!/usr/bin/env bash
# Git alias installer
# Usage:
#   ./alias.sh          Install git aliases into ~/.bashrc or ~/.zshrc
#   ./alias.sh --clean  Remove git aliases from ~/.bashrc or ~/.zshrc
#
# Only `gitroot` is provided as a shell alias, because changing the current
# directory (cd) must happen inside the active shell process — a git subcommand
# runs in a child process and cannot move the parent shell.
#
# The rebase / branch-clean / worktree-clean / review workflows are installed as
# portable git subcommands (git rb / git bc / git wc / git review) by ../setup.sh.

set -euo pipefail

# ── Markers ──────────────────────────────────────────────────────────────────
MARKER_BEGIN="# >>> git-aliases BEGIN <<<"
MARKER_END="# >>> git-aliases END <<<"

# ── Alias definitions ─────────────────────────────────────────────────────────
read -r -d '' ALIAS_BLOCK << 'ALIASES' || true
# >>> git-aliases BEGIN <<<

# Jump to the git repository root from any subdirectory
alias gitroot='cd "$(git rev-parse --show-toplevel)"'

# >>> git-aliases END <<<
ALIASES

# ── Helpers ───────────────────────────────────────────────────────────────────

detect_rc_file() {
  local shell_name
  shell_name=$(basename "${SHELL:-}")
  case "$shell_name" in
    zsh)  echo "$HOME/.zshrc" ;;
    bash) echo "$HOME/.bashrc" ;;
    *)
      # Fall back to whichever file exists; prefer zshrc
      if [[ -f "$HOME/.zshrc" ]]; then
        echo "$HOME/.zshrc"
      else
        echo "$HOME/.bashrc"
      fi
      ;;
  esac
}

already_installed() {
  local rc_file="$1"
  [[ -f "$rc_file" ]] && grep -qF "$MARKER_BEGIN" "$rc_file"
}

do_install() {
  local rc_file
  rc_file=$(detect_rc_file)

  if already_installed "$rc_file"; then
    echo "Git aliases are already installed in $rc_file. Nothing to do."
    exit 0
  fi

  printf '\n%s\n' "$ALIAS_BLOCK" >> "$rc_file"
  echo "Git aliases installed into $rc_file."
  echo "Run 'source $rc_file' or open a new terminal to activate them."
}

do_clean() {
  local rc_file
  rc_file=$(detect_rc_file)

  if ! already_installed "$rc_file"; then
    echo "No git aliases found in $rc_file. Nothing to remove."
    exit 0
  fi

  echo "The git-alias block will be removed from $rc_file."
  printf "Proceed? [y/N] "
  read -r answer
  if [[ ! "$answer" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi

  # Remove lines from MARKER_BEGIN through MARKER_END (inclusive)
  local tmp
  tmp=$(mktemp)
  awk "
    /^# >>> git-aliases BEGIN <<</ { skip=1 }
    skip { if (/^# >>> git-aliases END <<</) { skip=0 } next }
    { print }
  " "$rc_file" > "$tmp"
  mv "$tmp" "$rc_file"
  echo "Git aliases removed from $rc_file."
}

# ── Entry point ───────────────────────────────────────────────────────────────

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTION]

Install or remove git convenience aliases from your shell rc file.
Automatically detects the current shell (\$SHELL) and targets ~/.zshrc
or ~/.bashrc accordingly.

Options:
  (none)     Install the git alias block into ~/.zshrc or ~/.bashrc
  --clean    Remove the git alias block (prompts for confirmation)
  --help     Show this help message and exit

Aliases installed:
  gitroot    cd to the repository root from any subdirectory

Rebase / branch-clean / worktree-clean / review are installed as git
subcommands by ../setup.sh: git rb / git bc / git wc / git review.

Examples:
  $(basename "$0")           # install aliases
  $(basename "$0") --clean   # remove aliases
  source ~/.zshrc            # activate after install
EOF
}

case "${1:-}" in
  --help)  usage; exit 0 ;;
  --clean) do_clean ;;
  "")      do_install ;;
  *)
    echo "Unknown option: $1" >&2
    echo "Run '$(basename "$0") --help' for usage." >&2
    exit 1
    ;;
esac
