#!/usr/bin/env bash
# Git alias installer
# Usage:
#   ./alias.sh          Install git aliases into ~/.bashrc or ~/.zshrc
#   ./alias.sh --clean  Remove git aliases from ~/.bashrc or ~/.zshrc

set -euo pipefail

# ── Markers ──────────────────────────────────────────────────────────────────
MARKER_BEGIN="# >>> git-aliases BEGIN <<<"
MARKER_END="# >>> git-aliases END <<<"

# ── Alias definitions ─────────────────────────────────────────────────────────
# gitroot  – jump to the repository root from any subdirectory
# gitrebase – fetch the latest main/master from origin and rebase current branch
# gitprune  – delete local branches already merged into the default branch
# gitalias  – list all git-related aliases defined by this script

read -r -d '' ALIAS_BLOCK << 'ALIASES' || true
# >>> git-aliases BEGIN <<<

# Jump to the git repository root
alias gitroot='cd "$(git rev-parse --show-toplevel)"'

# Fetch latest default branch from origin and rebase current branch onto it
gitrebase() {
  local default_branch
  default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
    | sed 's|refs/remotes/origin/||')
  if [[ -z "$default_branch" ]]; then
    echo "gitrebase: cannot determine default branch (run 'git remote set-head origin -a' to fix)" >&2
    return 1
  fi
  echo "Fetching origin/$default_branch ..."
  git fetch origin "$default_branch"
  echo "Rebasing onto origin/$default_branch ..."
  git rebase "origin/$default_branch"
}

# Delete local branches that have been merged into the default branch
gitprune() {
  local default_branch
  default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
    | sed 's|refs/remotes/origin/||')
  if [[ -z "$default_branch" ]]; then
    echo "gitprune: cannot determine default branch (run 'git remote set-head origin -a' to fix)" >&2
    return 1
  fi
  local merged
  merged=$(git branch --merged "origin/$default_branch" \
    | grep -v -E "^\*|^\s*(main|master|develop|$default_branch)\s*$")
  if [[ -z "$merged" ]]; then
    echo "No merged branches to prune."
    return 0
  fi
  echo "The following local branches will be deleted:"
  echo "$merged"
  printf "Proceed? [y/N] "
  read -r answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    echo "$merged" | xargs git branch -d
    echo "Done."
  else
    echo "Aborted."
  fi
}

# List all git-related aliases defined by this script
gitalias() {
  echo "Git aliases installed by alias.sh:"
  echo "  gitroot   – cd to the repository root"
  echo "  gitrebase – fetch default branch and rebase current branch onto it"
  echo "  gitprune  – delete local branches merged into default branch"
  echo "  gitalias  – show this help"
}

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
  gitrebase  fetch the default branch from origin and rebase current branch
  gitprune   delete local branches already merged into the default branch
  gitalias   list all git aliases added by this script

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
