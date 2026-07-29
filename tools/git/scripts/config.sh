#!/usr/bin/env bash
# Git global configuration initializer
# Interactively sets user identity and applies recommended git settings.
#
# Usage:
#   ./config.sh            Apply all recommended git configurations
#   ./config.sh --dry-run  Show what would be set without changing anything

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
  Performance  pull.ff, rerere.enabled, status.renames, fetch.parallel,
               protocol.version, checkout.workers, maintenance.auto

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
  read -r input || input=""
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
git_config merge.ff             "true"        "allow fast-forward merges when possible"

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

case "$(uname -s)" in
  Darwin)
    git_config credential.helper "osxkeychain" "store credentials in macOS Keychain"
    ;;
  Linux)
    git_config credential.helper "cache --timeout=86400" "cache credentials for one day"
    ;;
  *)
    echo "  credential.helper skipped (unsupported OS: $(uname -s))"
    ;;
esac
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
  case "$(uname -s)" in
    Darwin) echo "  delta not found — skipping (install with: brew install git-delta)" ;;
    Linux)  echo "  delta not found — skipping (install with: apt / dnf / yum)" ;;
    *)      echo "  delta not found — skipping" ;;
  esac
fi

# ── Status / Pull / Fetch / Checkout performance ───────────────────────────────

header "Performance / Workflow"

git_config pull.ff                          "only"   "avoid implicit merge commits on pull"
git_config rebase.updateRefs                "true"   "move local branches that point into rebased range"
git_config branch.autoSetupRebase           "always" "new tracking branches pull with rebase"
git_config rerere.enabled                   "true"   "reuse recorded conflict resolutions"

git_config core.untrackedCache              "true"   "speed up git status in large worktrees"
git_config index.threads                    "true"   "use multiple threads for index operations"
git_config status.renames                   "true"   "detect renames in git status"
git_config status.submoduleSummary          "true"   "show concise submodule changes in status"

git_config fetch.parallel                   "8"      "fetch multiple remotes/submodules in parallel"
git_config submodule.fetchJobs              "8"      "fetch submodules in parallel"
git_config fetch.writeCommitGraph           "true"   "write commit-graph after fetch"
git_config protocol.version                 "2"      "use Git protocol v2"

git_config checkout.workers                 "0"      "auto-size parallel checkout workers"
git_config checkout.thresholdForParallelism "100"    "only parallelize larger checkouts"
git_config maintenance.auto                 "true"   "allow incremental repository maintenance"
git_config gc.writeCommitGraph             "true"   "write commit graph during gc"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
if [[ "$DRY_RUN" == true ]]; then
  echo "[DRY RUN] No changes were made. Remove --dry-run to apply."
else
  echo "Done. Run 'git config --global --list' to review all settings."
fi
