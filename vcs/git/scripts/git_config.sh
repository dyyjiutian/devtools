#!/usr/bin/env bash
# Git global configuration initializer
# Interactively sets user identity and applies recommended git settings.
#
# Usage:
#   ./git_config.sh            Apply all recommended git configurations
#   ./git_config.sh --dry-run  Show what would be set without changing anything

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTION]

Interactively initialise git global configuration with recommended settings.
Prompts for user.name and user.email (existing values shown as defaults).

Options:
  (none)       Apply all recommended git global configurations
  --dry-run    Print what would be set without making any changes
  --help       Show this help message and exit

Configuration applied:
  Identity     user.name, user.email
  Core         editor, autocrlf, whitespace, ignorecase, precomposeunicode
  Pull/Rebase  pull.rebase, rebase.autoStash, rebase.autoSquash,
               merge.conflictstyle, merge.ff
  Push         push.default, push.autoSetupRemote, push.followTags
  Fetch        fetch.prune, fetch.prunetags
  Diff         diff.algorithm, diff.colorMoved
  Log/UI       color.ui, log.abbrevCommit, log.date
  Branch       branch.sort, init.defaultBranch
  Security     credential.helper, transfer.fsckObjects

Examples:
  $(basename "$0")             # interactive setup
  $(basename "$0") --dry-run   # preview without applying
EOF
}

DRY_RUN=false
case "${1:-}" in
  --help)     usage; exit 0 ;;
  --dry-run)  DRY_RUN=true ;;
  "")         ;;
  *)
    echo "Unknown option: $1" >&2
    echo "Run '$(basename "$0") --help' for usage." >&2
    exit 1
    ;;
esac

# ── Helpers ───────────────────────────────────────────────────────────────────

git_config() {
  # git_config <key> <value> [<description>]
  local key="$1" value="$2" desc="${3:-}"
  if [[ -n "$desc" ]]; then
    printf "  %-45s %s\n" "$key = $value" "# $desc"
  fi
  if [[ "$DRY_RUN" == false ]]; then
    git config --global "$key" "$value"
  fi
}

prompt_with_default() {
  # prompt_with_default <var_name> <prompt> <default>
  local var_name="$1" prompt_text="$2" default="$3"
  printf "%s [%s]: " "$prompt_text" "$default"
  read -r input
  printf -v "$var_name" '%s' "${input:-$default}"
}

header() {
  echo ""
  echo "── $* ──"
}

# ── Dry-run banner ────────────────────────────────────────────────────────────

if [[ "$DRY_RUN" == true ]]; then
  echo "[DRY RUN] No changes will be made."
fi

# ── User identity ─────────────────────────────────────────────────────────────

header "User Identity"

current_name=$(git config --global user.name  2>/dev/null || true)
current_email=$(git config --global user.email 2>/dev/null || true)

prompt_with_default GIT_NAME  "Full name " "${current_name:-Your Name}"
prompt_with_default GIT_EMAIL "Email     " "${current_email:-you@example.com}"

git_config user.name  "$GIT_NAME"
git_config user.email "$GIT_EMAIL"

# ── Core behavior ─────────────────────────────────────────────────────────────

header "Core Behavior"

git_config core.editor          "vim"         "default editor"
git_config core.autocrlf        "input"       "convert CRLF→LF on commit (safe for macOS/Linux)"
git_config core.whitespace      "trailing-space,space-before-tab" "warn on common whitespace issues"
git_config core.ignorecase      "false"       "treat filenames as case-sensitive"
git_config core.precomposeunicode "true"      "normalize Unicode filenames (macOS)"

# ── Pull / merge / rebase ─────────────────────────────────────────────────────

header "Pull / Merge / Rebase"

git_config pull.rebase          "true"        "rebase instead of merge on pull"
git_config rebase.autoStash     "true"        "auto-stash dirty working tree before rebase"
git_config rebase.autoSquash    "true"        "auto-apply fixup!/squash! commits during rebase"
git_config merge.conflictstyle  "diff3"       "show base version in conflict markers"
git_config merge.ff             "false"       "always create a merge commit (no fast-forward)"

# ── Push ──────────────────────────────────────────────────────────────────────

header "Push"

git_config push.default         "current"     "push to the same-named remote branch"
git_config push.autoSetupRemote "true"        "auto --set-upstream on first push"
git_config push.followTags      "true"        "push annotated tags along with commits"

# ── Fetch ─────────────────────────────────────────────────────────────────────

header "Fetch"

git_config fetch.prune          "true"        "auto-remove stale remote-tracking branches"
git_config fetch.prunetags      "true"        "auto-remove stale remote tags"

# ── Diff ──────────────────────────────────────────────────────────────────────

header "Diff"

git_config diff.algorithm       "histogram"   "more accurate diff (better than myers for code)"
git_config diff.colorMoved      "zebra"       "highlight moved lines in a different color"

# ── Log / UI ─────────────────────────────────────────────────────────────────

header "Log / UI"

git_config color.ui             "auto"        "colorize output when connected to a terminal"
git_config log.abbrevCommit     "true"        "show short commit hashes in log"
git_config log.date             "iso"         "use ISO 8601 date format in log"

# ── Branch ────────────────────────────────────────────────────────────────────

header "Branch"

git_config branch.sort          "-committerdate" "sort branches by most recently committed"
git_config init.defaultBranch   "main"           "default branch name for new repositories"

# ── Credential / Security ─────────────────────────────────────────────────────

header "Credential / Security"

git_config credential.helper    "osxkeychain" "store credentials in macOS Keychain"
git_config transfer.fsckObjects "true"        "verify object integrity on receive"

# ── Delta (diff pager) ────────────────────────────────────────────────────────

header "Delta (diff pager)"

if command -v delta &>/dev/null; then
  git_config core.pager                "delta"          "use delta as the default pager"
  git_config interactive.diffFilter    "delta --color-only" "delta in interactive mode"
  git_config delta.navigate            "true"           "use n/N to jump between diff sections"
  git_config delta.side-by-side        "true"           "side-by-side diff layout"
  git_config delta.line-numbers        "true"           "show line numbers in diff"
  git_config delta.syntax-theme        "Dracula"        "syntax highlighting theme"
  git_config delta.diff-highlight      "true"           "highlight changed words within a line"
else
  echo "  delta not found — skipping (install with: brew install git-delta)"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
if [[ "$DRY_RUN" == true ]]; then
  echo "[DRY RUN] No changes were made. Remove --dry-run to apply."
else
  echo "Done. Run 'git config --global --list' to review all settings."
fi
