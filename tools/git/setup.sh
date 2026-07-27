#!/usr/bin/env bash
# One-shot Git setup: orchestrates git-delta install plus the three helper
# scripts under scripts/ (sub-command.sh, config.sh, alias.sh).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
DRY_RUN=false
SKIP_ALIAS=false
SKIP_CONFIG=false
SKIP_DELTA=false
SKIP_SUBCMD=false

info()    { echo -e "\033[34m[INFO]\033[0m $1"; }
success() { echo -e "\033[32m[OK]\033[0m $1"; }
warn()    { echo -e "\033[33m[WARN]\033[0m $1"; }
error()   { echo -e "\033[31m[ERROR]\033[0m $1"; }
step()    { echo -e "\033[36m[STEP]\033[0m $1"; }

show_help() {
  cat <<'EOF'
用法: ./setup.sh [选项]

一键配置 Git 开发环境（各步骤也可单独运行对应的 scripts/*.sh）:
  - 安装 GitHub CLI (gh)，用于 GitHub PR / issue / review 操作
  - 安装 git-delta 并配置为 diff/log/show pager
  - scripts/sub-command.sh：安装 git rb / bc / wc / review / sparse-clone 子命令到 ~/.local/bin
  - scripts/config.sh：写入推荐的 git 全局配置与性能/工作流优化
  - scripts/alias.sh：安装 gitroot（cd 到仓库根目录）

选项:
  -h, --help        显示帮助
  -d, --dry-run     试运行，只打印将要执行的操作
  --skip-delta      跳过 git-delta 安装
  --skip-subcmd     跳过 git 子命令安装
  --skip-config     跳过 git config 配置
  --skip-alias      跳过 shell alias 配置

示例:
  ./setup.sh
  ./setup.sh --dry-run
  ./setup.sh --skip-delta
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)     show_help; exit 0 ;;
    -d|--dry-run)  DRY_RUN=true; shift ;;
    --skip-alias)  SKIP_ALIAS=true; shift ;;
    --skip-config) SKIP_CONFIG=true; shift ;;
    --skip-delta)  SKIP_DELTA=true; shift ;;
    --skip-subcmd) SKIP_SUBCMD=true; shift ;;
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

require_git() {
  if ! command -v git &>/dev/null; then
    error "需要 git，请先安装 Git"
    exit 1
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

install_gh() {
  step "安装/检查 GitHub CLI (gh) ..."
  if command -v gh &>/dev/null; then
    success "GitHub CLI 已安装: $(gh --version | head -1)"
    info "请执行: gh auth login"
    return
  fi

  case "$(uname -s)" in
    Darwin)
      if ! command -v brew &>/dev/null; then
        warn "未找到 Homebrew，跳过 GitHub CLI 安装。可手动执行: brew install gh"
        return
      fi
      if ! try_cmd brew install gh; then
        warn "GitHub CLI 安装失败，继续执行后续 Git 配置"
        return
      fi
      ;;
    Linux)
      if command -v apt-get &>/dev/null; then
        if ! try_cmd sudo apt-get update || ! try_cmd sudo apt-get install -y gh; then
          warn "GitHub CLI 安装失败，继续执行后续 Git 配置"
          return
        fi
      elif command -v dnf &>/dev/null; then
        if dnf --version 2>/dev/null | head -1 | grep -q '^5'; then
          if ! try_cmd sudo dnf install -y dnf5-plugins \
            || ! try_cmd sudo dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo \
            || ! try_cmd sudo dnf install -y gh; then
            warn "GitHub CLI 安装失败，继续执行后续 Git 配置"
            return
          fi
        elif ! try_cmd sudo dnf install -y 'dnf-command(config-manager)' \
          || ! try_cmd sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo \
          || ! try_cmd sudo dnf install -y gh; then
          warn "GitHub CLI 安装失败，继续执行后续 Git 配置"
          return
        fi
      elif command -v yum &>/dev/null; then
        if ! try_cmd sudo yum install -y gh; then
          warn "GitHub CLI 安装失败，继续执行后续 Git 配置"
          return
        fi
      elif command -v pacman &>/dev/null; then
        if ! try_cmd sudo pacman -S --needed gh; then
          warn "GitHub CLI 安装失败，继续执行后续 Git 配置"
          return
        fi
      elif command -v zypper &>/dev/null; then
        if ! try_cmd sudo zypper install -y gh; then
          warn "GitHub CLI 安装失败，继续执行后续 Git 配置"
          return
        fi
      else
        warn "未找到可用包管理器，跳过 GitHub CLI 安装"
        warn "可手动安装 gh 后重跑本脚本以启用 GitHub git review 工作流"
        return
      fi
      ;;
    *)
      warn "不支持的系统: $(uname -s)，跳过 GitHub CLI 安装"
      return
      ;;
  esac

  if [[ "$DRY_RUN" == "true" ]]; then
    info "GitHub CLI 安装完成后，请执行: gh auth login"
  elif command -v gh &>/dev/null; then
    success "GitHub CLI 安装完成"
    info "请执行: gh auth login"
  else
    warn "GitHub CLI 安装命令已执行，但当前 PATH 未找到 gh"
  fi
}

install_subcommands() {
  if [[ "$SKIP_SUBCMD" == "true" ]]; then
    info "跳过 git 子命令安装"
    return
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    bash "$SCRIPTS_DIR/sub-command.sh" --dry-run
  else
    bash "$SCRIPTS_DIR/sub-command.sh"
  fi
}

run_config() {
  if [[ "$SKIP_CONFIG" == "true" ]]; then
    info "跳过 git config 配置"
    return
  fi
  step "写入 git config ..."
  if [[ "$DRY_RUN" == "true" ]]; then
    bash "$SCRIPTS_DIR/config.sh" --dry-run
  else
    bash "$SCRIPTS_DIR/config.sh"
  fi
}

install_aliases() {
  if [[ "$SKIP_ALIAS" == "true" ]]; then
    info "跳过 shell alias 配置"
    return
  fi
  step "安装 shell aliases ..."
  if [[ "$DRY_RUN" == "true" ]]; then
    run_cmd bash "$SCRIPTS_DIR/alias.sh"
  else
    bash "$SCRIPTS_DIR/alias.sh"
  fi
}

main() {
  info "Git 一键配置脚本"
  info "运行模式: $([[ "$DRY_RUN" == "true" ]] && echo "试运行" || echo "实际执行")"
  echo ""

  require_git
  install_delta
  install_gh
  install_subcommands
  run_config
  install_aliases

  echo ""
  success "Git 配置完成"
  echo ""
  echo "  验证命令:"
  echo "    git config --global --list --show-origin"
  echo "    git status"
  echo "    git rb --help / git bc --help / git wc --help / git review --help"
  echo ""
  echo "  若刚安装 gitroot alias 或子命令 PATH，请重新打开终端，或 source 当前 shell rc 文件。"
}

if [[ "${SETUP_NO_MAIN:-false}" != "true" && "${SETUP_NO_MAIN:-false}" != "1" ]]; then
  main
fi
