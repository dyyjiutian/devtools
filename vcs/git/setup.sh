#!/usr/bin/env bash
# One-shot Git setup: delta, global git config, shell aliases, and workflow tweaks.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BIN_DIR="$HOME/.local/bin"
LOCAL_MAN_DIR="$HOME/.local/share/man/man1"
GIT_COMMAND_DIR="$SCRIPT_DIR/bin"
GIT_MAN_DIR="$SCRIPT_DIR/man/man1"
DRY_RUN=false
SKIP_ALIAS=false
SKIP_CONFIG=false
SKIP_DELTA=false

info()    { echo -e "\033[34m[INFO]\033[0m $1"; }
success() { echo -e "\033[32m[OK]\033[0m $1"; }
warn()    { echo -e "\033[33m[WARN]\033[0m $1"; }
error()   { echo -e "\033[31m[ERROR]\033[0m $1"; }
step()    { echo -e "\033[36m[STEP]\033[0m $1"; }

show_help() {
  cat <<'EOF'
用法: ./setup.sh [选项]

一键配置 Git 开发环境:
  - 安装 git-delta 并配置为 diff/log/show pager
  - 安装 git rb / git bc 子命令到 ~/.local/bin
  - 运行 scripts/git_config.sh 写入推荐 git config
  - 安装 scripts/alias.sh 中的 gitroot/gitrebase/gitprune/gitreview/gitalias
  - 写入 git status / pull / fetch / checkout 等性能与工作流优化配置
  - include config/github.gitconfig，提供 GitHub/GitLab/Gerrit 通用 git review alias

选项:
  -h, --help       显示帮助
  -d, --dry-run    试运行，只打印将要执行的操作
  --skip-alias     跳过 shell alias 配置
  --skip-config    跳过 git config 配置
  --skip-delta     跳过 git-delta 安装

示例:
  ./setup.sh
  ./setup.sh --dry-run
  ./setup.sh --skip-delta
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)    show_help; exit 0 ;;
    -d|--dry-run) DRY_RUN=true; shift ;;
    --skip-alias) SKIP_ALIAS=true; shift ;;
    --skip-config) SKIP_CONFIG=true; shift ;;
    --skip-delta) SKIP_DELTA=true; shift ;;
    *) error "未知选项: $1"; show_help; exit 1 ;;
  esac
done

run_cmd() {
  if [[ "$DRY_RUN" == "true" ]]; then
    printf '[DRY RUN] '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

try_cmd() {
  if [[ "$DRY_RUN" == "true" ]]; then
    run_cmd "$@"
    return 0
  fi

  "$@"
}

git_config() {
  local key="$1" value="$2" desc="${3:-}"
  printf "  %-36s %s\n" "$key = $value" "${desc:+# $desc}"
  run_cmd git config --global "$key" "$value"
}

require_git() {
  if ! command -v git &>/dev/null; then
    error "需要 git，请先安装 Git"
    exit 1
  fi
}

install_git_commands() {
  step "安装 Git 子命令 ..."

  if [[ ! -d "$GIT_COMMAND_DIR" ]]; then
    warn "未找到 Git 子命令目录: $GIT_COMMAND_DIR"
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    run_cmd mkdir -p "$LOCAL_BIN_DIR"
  else
    mkdir -p "$LOCAL_BIN_DIR"
  fi

  local cmd src dst
  for cmd in git-rb git-bc; do
    src="$GIT_COMMAND_DIR/$cmd"
    dst="$LOCAL_BIN_DIR/$cmd"
    if [[ ! -f "$src" ]]; then
      warn "未找到 $src，跳过"
      continue
    fi
    run_cmd install -m 0755 "$src" "$dst"
  done

  install_git_manpages

  ensure_local_bin_path
}

install_git_manpages() {
  if [[ ! -d "$GIT_MAN_DIR" ]]; then
    warn "未找到 Git manpage 目录: $GIT_MAN_DIR"
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    run_cmd mkdir -p "$LOCAL_MAN_DIR"
  else
    mkdir -p "$LOCAL_MAN_DIR"
  fi

  local page src dst
  for page in git-rb.1 git-bc.1; do
    src="$GIT_MAN_DIR/$page"
    dst="$LOCAL_MAN_DIR/$page"
    if [[ ! -f "$src" ]]; then
      warn "未找到 $src，跳过"
      continue
    fi
    run_cmd install -m 0644 "$src" "$dst"
  done
}

detect_rc_file() {
  local shell_name
  shell_name="$(basename "${SHELL:-}")"
  case "$shell_name" in
    zsh) echo "$HOME/.zshrc" ;;
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

ensure_local_bin_path() {
  local marker="# devtools git commands PATH"
  local line='[[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin:$PATH"'
  local man_marker="# devtools git commands MANPATH"
  local man_line='[[ ":${MANPATH:-}:" != *":$HOME/.local/share/man:"* ]] && export MANPATH="$HOME/.local/share/man:${MANPATH:-}"'
  local rc_file
  rc_file="$(detect_rc_file)"

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

install_delta() {
  if [[ "$SKIP_DELTA" == "true" ]]; then
    info "跳过 git-delta 安装"
    return
  fi

  step "安装/检查 git-delta ..."
  if command -v delta &>/dev/null; then
    success "git-delta 已安装: $(delta --version | head -1)"
    return
  fi

  case "$(uname -s)" in
    Darwin)
      if ! command -v brew &>/dev/null; then
        warn "未找到 Homebrew，跳过 git-delta 安装。可手动执行: brew install git-delta"
        return
      fi
      if ! try_cmd brew install git-delta; then
        warn "git-delta 安装失败，继续执行后续 Git 配置"
        return
      fi
      ;;
    Linux)
      if command -v apt-get &>/dev/null; then
        if ! try_cmd sudo apt-get update || ! try_cmd sudo apt-get install -y git-delta; then
          warn "git-delta 安装失败，继续执行后续 Git 配置"
          return
        fi
      elif command -v dnf &>/dev/null; then
        if ! try_cmd sudo dnf install -y git-delta; then
          warn "git-delta 安装失败，继续执行后续 Git 配置"
          return
        fi
      elif command -v yum &>/dev/null; then
        if ! try_cmd sudo yum install -y git-delta; then
          warn "git-delta 安装失败，继续执行后续 Git 配置"
          return
        fi
      elif command -v pacman &>/dev/null; then
        if ! try_cmd sudo pacman -S --needed git-delta; then
          warn "git-delta 安装失败，继续执行后续 Git 配置"
          return
        fi
      elif command -v zypper &>/dev/null; then
        if ! try_cmd sudo zypper install -y git-delta; then
          warn "git-delta 安装失败，继续执行后续 Git 配置"
          return
        fi
      elif command -v cargo &>/dev/null; then
        if ! try_cmd cargo install git-delta; then
          warn "git-delta 安装失败，继续执行后续 Git 配置"
          return
        fi
      else
        warn "未找到可用包管理器，跳过 git-delta 安装"
        warn "可手动安装后重跑本脚本以启用 delta 配置"
        return
      fi
      ;;
    *)
      warn "不支持的系统: $(uname -s)，跳过 git-delta 安装"
      return
      ;;
  esac

  if [[ "$DRY_RUN" == "false" ]]; then
    command -v delta &>/dev/null && success "git-delta 安装完成" || warn "git-delta 安装命令已执行，但当前 PATH 未找到 delta"
  fi
}

run_git_config_script() {
  if [[ "$SKIP_CONFIG" == "true" ]]; then
    info "跳过 git config 配置"
    return
  fi

  step "写入基础 git config ..."
  if [[ "$DRY_RUN" == "true" ]]; then
    bash "$SCRIPT_DIR/scripts/git_config.sh" --dry-run
  else
    bash "$SCRIPT_DIR/scripts/git_config.sh"
  fi
}

apply_extra_git_config() {
  if [[ "$SKIP_CONFIG" == "true" ]]; then
    return
  fi

  step "写入 status / pull / fetch 性能配置 ..."

  git_config pull.ff                         "only"  "avoid implicit merge commits on pull"
  git_config rebase.updateRefs               "true"  "move local branches that point into rebased range"
  git_config branch.autoSetupRebase          "always" "new tracking branches pull with rebase"
  git_config rerere.enabled                  "true"  "reuse recorded conflict resolutions"

  git_config core.untrackedCache             "true"  "speed up git status in large worktrees"
  git_config feature.manyFiles               "true"  "enable large-repository defaults where supported"
  git_config index.threads                   "true"  "use multiple threads for index operations"
  git_config status.renames                  "true"  "detect renames in git status"
  git_config status.submoduleSummary         "true"  "show concise submodule changes in status"

  git_config fetch.parallel                  "8"     "fetch multiple remotes/submodules in parallel"
  git_config submodule.fetchJobs             "8"     "fetch submodules in parallel"
  git_config fetch.writeCommitGraph          "true"  "write commit-graph after fetch"
  git_config protocol.version                "2"     "use Git protocol v2"

  git_config checkout.workers                "0"     "auto-size parallel checkout workers"
  git_config checkout.thresholdForParallelism "100"  "only parallelize larger checkouts"
  git_config maintenance.auto                "true"  "allow incremental repository maintenance"
  git_config gc.writeCommitGraph             "true"  "write commit graph during gc"

  include_github_config
}

include_github_config() {
  local include_path="$SCRIPT_DIR/config/github.gitconfig"

  if [[ ! -f "$include_path" ]]; then
    warn "未找到 GitHub gitconfig: $include_path"
    return
  fi

  if [[ "$DRY_RUN" == "false" ]] && git config --global --get-all include.path 2>/dev/null | grep -Fxq "$include_path"; then
    success "已 include GitHub gitconfig，跳过"
    return
  fi

  printf "  %-36s %s\n" "include.path = $include_path" "# Git review aliases"
  run_cmd git config --global --add include.path "$include_path"
}

install_aliases() {
  if [[ "$SKIP_ALIAS" == "true" ]]; then
    info "跳过 shell alias 配置"
    return
  fi

  step "安装 shell aliases ..."
  if [[ "$DRY_RUN" == "true" ]]; then
    run_cmd bash "$SCRIPT_DIR/scripts/alias.sh"
  else
    bash "$SCRIPT_DIR/scripts/alias.sh"
  fi
}

main() {
  info "Git 一键配置脚本"
  info "运行模式: $([[ "$DRY_RUN" == "true" ]] && echo "试运行" || echo "实际执行")"
  echo ""

  require_git
  install_delta
  install_git_commands
  run_git_config_script
  apply_extra_git_config
  install_aliases

  echo ""
  success "Git 配置完成"
  echo ""
  echo "  验证命令:"
  echo "    git config --global --list --show-origin"
  echo "    git status"
  echo "    gitalias"
  echo ""
  echo "  若刚安装 aliases，请重新打开终端，或 source 当前 shell rc 文件。"
}

main
