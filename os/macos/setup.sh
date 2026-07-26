#!/usr/bin/env bash
# macOS 初始化安装脚本
# Part 1: OS 基础配置（系统信息、Homebrew）
# Part 2: 按 packages.list 安装常见软件

set -euo pipefail

# ─── bash 版本检查（macOS 自带 bash 3.2，部分特性需要 3.2+ 兼容写法）──────
if [[ "${BASH_VERSINFO[0]}" -lt 3 ]]; then
  echo "ERROR: 此脚本需要 bash 3.2 或更高版本（当前: ${BASH_VERSION}）" >&2
  exit 1
fi

# ─── 颜色定义 ────────────────────────────────────────────────────────────────
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

# ─── 工具函数 ────────────────────────────────────────────────────────────────
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()    { echo -e "\n${BOLD}${CYAN}▶ $*${NC}"; }

# ─── 路径与缓存 ──────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${SCRIPT_DIR}/../../cache"
PACKAGES_LIST="${SCRIPT_DIR}/packages.list"
# shellcheck source=../lib/packages_list.sh
source "${SCRIPT_DIR}/../lib/packages_list.sh"

# 本地缓存优先下载：有缓存用缓存，否则从官方 URL 下载
# 用法: fetch <cache相对路径> <官方URL> <输出文件>
fetch() {
  local cache_rel="$1" url="$2" out="$3"
  if [[ -f "${CACHE_DIR}/${cache_rel}" ]]; then
    info "使用本地缓存: ${cache_rel}"
    cp "${CACHE_DIR}/${cache_rel}" "$out"
  else
    info "网络下载: $(basename "$url")"
    curl -fsSL "$url" -o "$out"
  fi
}

# ─── 用法说明 ────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF

${BOLD}用法:${NC}
  $(basename "$0") [选项]

${BOLD}说明:${NC}
  macOS 初始化脚本，分两段执行：
    1. OS 基础配置（系统信息、Homebrew）
    2. 按 packages.list 安装常见软件

${BOLD}选项:${NC}
  -h, --help          显示此帮助信息并退出
  --info-only         仅显示系统信息，不执行安装
  --check             检查 packages.list 中各软件是否已安装
  --install <name>    仅安装清单中的指定软件（如 bat、rg）
  --kind <cli|tui|gui>
                      按界面类型筛选（可与 --check / 安装联用）
  --tag <tag>         按用途筛选：productivity|diagnostic|dev|ops|shell
  --dry-run           预览将执行的步骤，不实际安装
  --base-only         仅执行 OS 基础配置
  --packages-only     跳过基础配置，仅按 packages.list 安装
  --skip-brew         跳过 Homebrew 安装/更新（基础阶段）
  --skip-casks        跳过 brew-cask 条目
  --skip-formulae     跳过 brew 条目
  --skip-node         跳过 node / nvm 条目
  --skip-omz          跳过 oh-my-zsh 条目
  --skip-docker       跳过 docker cask
  --skip-vscode       跳过 visual-studio-code cask

${BOLD}清单文件:${NC}
  ${PACKAGES_LIST}

${BOLD}示例:${NC}
  $(basename "$0")                    # 完整安装
  $(basename "$0") --info-only        # 仅查看系统信息
  $(basename "$0") --check            # 检查清单安装状态
  $(basename "$0") --check --kind tui # 只看 TUI
  $(basename "$0") --check --tag diagnostic
  $(basename "$0") --install bat      # 只安装 bat
  $(basename "$0") --tag productivity --packages-only
  $(basename "$0") --dry-run          # 预览
  $(basename "$0") --base-only        # 仅 Homebrew

EOF
}

# ─── 系统信息检测 ────────────────────────────────────────────────────────────
detect_system_info() {
  step "系统基本信息"

  local macos_version
  macos_version=$(sw_vers -productVersion)
  local macos_name
  macos_name=$(sw_vers -productName)
  local build
  build=$(sw_vers -buildVersion)

  local chip_type chip_brand arch
  arch=$(uname -m)
  if [[ "$arch" == "arm64" ]]; then
    chip_brand=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Apple Silicon")
    chip_type="${GREEN}Apple Silicon (M 芯片)${NC}"
  else
    chip_brand=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Intel")
    chip_type="${YELLOW}Intel 芯片${NC}"
  fi

  local mem_bytes mem_gb
  mem_bytes=$(sysctl -n hw.memsize)
  mem_gb=$(( mem_bytes / 1024 / 1024 / 1024 ))

  local cpu_cores cpu_logical
  cpu_cores=$(sysctl -n hw.physicalcpu)
  cpu_logical=$(sysctl -n hw.logicalcpu)

  local disk_info
  disk_info=$(df -h / | awk 'NR==2 {printf "总计 %s，已用 %s，可用 %s", $2, $3, $4}')

  local hostname username
  hostname=$(scutil --get ComputerName 2>/dev/null || hostname)
  username=$(whoami)

  echo -e ""
  echo -e "  ${BOLD}操作系统${NC}   : ${macos_name} ${macos_version} (Build ${build})"
  echo -e "  ${BOLD}架构${NC}       : ${arch}"
  echo -e "  ${BOLD}芯片类型${NC}   : $(echo -e "${chip_type}")"
  echo -e "  ${BOLD}芯片型号${NC}   : ${chip_brand}"
  echo -e "  ${BOLD}物理核心${NC}   : ${cpu_cores} 核 (逻辑核心 ${cpu_logical})"
  echo -e "  ${BOLD}内存${NC}       : ${mem_gb} GB"
  echo -e "  ${BOLD}磁盘 (/)${NC}   : ${disk_info}"
  echo -e "  ${BOLD}主机名${NC}     : ${hostname}"
  echo -e "  ${BOLD}当前用户${NC}   : ${username}"
  echo -e ""
}

is_installed() {
  command -v "$1" &>/dev/null
}

# ─── Part 1: OS 基础配置 ─────────────────────────────────────────────────────
install_brew() {
  step "Homebrew（OS 基础）"

  if [[ "${DRY_RUN:-false}" == true ]]; then
    info "[dry-run] 安装/更新 Homebrew"
    return 0
  fi

  if is_installed brew; then
    success "Homebrew 已安装：$(brew --version | head -1)"
    info "正在更新 Homebrew..."
    brew update --quiet && success "Homebrew 已更新"
  else
    info "正在安装 Homebrew..."
    local tmp
    tmp=$(mktemp)
    fetch "scripts/homebrew-install.sh" "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh" "$tmp"
    /bin/bash "$tmp"
    rm -f "$tmp"

    if [[ "$(uname -m)" == "arm64" ]]; then
      local brew_profile='/opt/homebrew/bin/brew'
      if [[ -f "$brew_profile" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        info "已配置 Apple Silicon Homebrew 环境变量"
      fi
    fi

    success "Homebrew 安装完成：$(brew --version | head -1)"
  fi
}

configure_os_base() {
  step "Part 1: OS 基础配置"
  if [[ "${SKIP_BREW:-false}" == true ]]; then
    info "已跳过 Homebrew（--skip-brew）"
    return 0
  fi
  install_brew
}

# ─── Part 2: packages.list 安装适配 ──────────────────────────────────────────
should_skip_package() {
  local name="$1" source="$2"
  case "$source" in
    brew)
      [[ "${SKIP_FORMULAE:-false}" == true ]] && return 0
      ;;
    brew-cask)
      [[ "${SKIP_CASKS:-false}" == true ]] && return 0
      [[ "$name" == "docker" && "${MACOS_SKIP_DOCKER:-false}" == true ]] && return 0
      [[ "$name" == "visual-studio-code" && "${MACOS_SKIP_VSCODE:-false}" == true ]] && return 0
      ;;
    nvm)
      [[ "${SKIP_NODE:-false}" == true ]] && return 0
      ;;
    script)
      [[ "$name" == "oh-my-zsh" && "${SKIP_OMZ:-false}" == true ]] && return 0
      ;;
  esac
  return 1
}

package_is_installed() {
  local name="$1"
  case "$name" in
    visual-studio-code)
      is_installed code || brew list --cask visual-studio-code &>/dev/null
      return $?
      ;;
    iterm2|obsidian)
      brew list --cask "$name" &>/dev/null
      return $?
      ;;
    docker)
      is_installed docker || brew list --cask docker &>/dev/null
      return $?
      ;;
  esac
  packages_list_default_is_installed "$name"
}

install_brew_formula() {
  local name="$1"
  local formula
  formula="$(packages_list_brew_formula "$name")"
  if brew list --formula "$formula" &>/dev/null || packages_list_default_is_installed "$name"; then
    success "${name} 已安装，跳过"
  else
    info "正在安装 ${name}（brew ${formula}）..."
    brew install "$formula" && success "${name} 安装完成"
  fi
}

install_brew_cask() {
  local name="$1"
  local desc="$name"
  case "$name" in
    iterm2) desc="iTerm2 终端" ;;
    visual-studio-code) desc="VS Code 编辑器" ;;
    docker) desc="Docker Desktop" ;;
    obsidian) desc="Obsidian 知识库" ;;
  esac
  if brew list --cask "$name" &>/dev/null; then
    success "${desc} 已安装，跳过"
  else
    info "正在安装 ${desc}..."
    if brew install --cask "$name"; then
      success "${desc} 安装完成"
    else
      warn "${desc} 安装失败，请手动安装"
    fi
  fi
}

install_node_nvm() {
  step "Node.js / npm（nvm）"

  local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
  export NVM_DIR="$nvm_dir"

  if [[ -s "$nvm_dir/nvm.sh" ]]; then
    # shellcheck source=/dev/null
    source "$nvm_dir/nvm.sh"
    success "nvm 已安装：$(nvm --version)"
  else
    info "正在安装 nvm..."
    local tmp
    tmp=$(mktemp)
    fetch "scripts/nvm-install.sh" "https://raw.githubusercontent.com/nvm-sh/nvm/HEAD/install.sh" "$tmp"
    bash "$tmp"
    rm -f "$tmp"
    # shellcheck source=/dev/null
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
    success "nvm 安装完成：$(nvm --version)"
  fi

  local zshrc="$HOME/.zshrc"
  local nvm_init_marker='# nvm init (added by install.sh)'
  if [[ -f "$zshrc" ]] && ! grep -qF "$nvm_init_marker" "$zshrc"; then
    cat >> "$zshrc" <<ZSHRC

$nvm_init_marker
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && source "\$NVM_DIR/nvm.sh"
[ -s "\$NVM_DIR/bash_completion" ] && source "\$NVM_DIR/bash_completion"
ZSHRC
    success "已将 nvm 初始化代码写入 ~/.zshrc"
  elif [[ ! -f "$zshrc" ]]; then
    cat > "$zshrc" <<ZSHRC
$nvm_init_marker
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && source "\$NVM_DIR/nvm.sh"
[ -s "\$NVM_DIR/bash_completion" ] && source "\$NVM_DIR/bash_completion"
ZSHRC
    success "已创建 ~/.zshrc 并写入 nvm 初始化代码"
  else
    info "~/.zshrc 中已有 nvm 初始化代码，跳过"
  fi

  local current_node
  current_node=$(nvm current 2>/dev/null || echo "none")
  if [[ "$current_node" == "none" ]] || ! node --version &>/dev/null; then
    info "正在安装 Node.js LTS..."
    nvm install --lts
    nvm use --lts
    nvm alias default 'lts/*'
    success "Node.js 安装完成：$(node --version)，npm：$(npm --version)"
  else
    success "Node.js 已安装：$(node --version)，npm：$(npm --version)"
    info "可用版本列表：nvm ls"
  fi
}

install_oh_my_zsh() {
  step "Oh My Zsh"

  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    success "Oh My Zsh 已安装，跳过"
  else
    info "正在安装 Oh My Zsh..."
    local tmp
    tmp=$(mktemp)
    fetch "scripts/ohmyzsh-install.sh" "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh" "$tmp"
    if sh "$tmp" "" --unattended; then
      success "Oh My Zsh 安装完成"
    else
      warn "Oh My Zsh 安装失败，请手动安装"
    fi
    rm -f "$tmp"
  fi
}

install_package_entry() {
  local name="$1" version="$2" source="$3" kind="${4:-}" tags="${5:-}"

  if [[ "${PACKAGES_IGNORE_FILTERS:-false}" != true ]] && \
     ! packages_list_match_filters "$kind" "$tags"; then
    return 0
  fi

  if should_skip_package "$name" "$source"; then
    info "跳过 ${name}（${source}）"
    return 0
  fi

  if [[ "${DRY_RUN:-false}" == true ]]; then
    info "[dry-run] ${name} ${version} (${source}) [${kind}] ${tags}"
    return 0
  fi

  case "$source" in
    brew)
      install_brew_formula "$name"
      ;;
    brew-cask)
      install_brew_cask "$name"
      ;;
    nvm)
      [[ "$name" == "node" ]] || { warn "未知 nvm 条目: $name"; return 0; }
      install_node_nvm
      ;;
    script)
      case "$name" in
        oh-my-zsh) install_oh_my_zsh ;;
        *) warn "未知 script 条目: $name" ;;
      esac
      ;;
    *)
      warn "不支持的 source: ${source}（${name}）"
      ;;
  esac
}

install_packages_from_list() {
  step "Part 2: 按 packages.list 安装常见软件"
  if [[ ! -f "$PACKAGES_LIST" ]]; then
    error "找不到软件清单: $PACKAGES_LIST"
    return 1
  fi
  info "清单: $PACKAGES_LIST"
  if [[ -n "${PACKAGES_FILTER_KIND:-}" || -n "${PACKAGES_FILTER_TAG:-}" ]]; then
    info "筛选: kind=${PACKAGES_FILTER_KIND:-*} tag=${PACKAGES_FILTER_TAG:-*}"
  fi
  packages_list_foreach "$PACKAGES_LIST" install_package_entry
}

check_packages_status() {
  step "检查 packages.list 安装状态"
  info "清单: $PACKAGES_LIST"
  packages_list_check "$PACKAGES_LIST"
}

install_one_package() {
  local want_name="$1"
  local entry name version source kind tags

  step "安装单个软件: ${want_name}"
  if ! entry="$(packages_list_lookup "$PACKAGES_LIST" "$want_name")"; then
    error "清单中不存在: ${want_name}"
    info "可用名称见: $PACKAGES_LIST 或运行 --check"
    return 1
  fi
  IFS=$'\t' read -r name version source kind tags <<<"$entry"
  info "${name} ${version} (${source}) [${kind}] ${tags}"

  # brew / cask / nvm / script 依赖 Homebrew 或基础环境
  if [[ "$source" == "brew" || "$source" == "brew-cask" ]]; then
    if ! is_installed brew; then
      warn "未检测到 Homebrew，先执行基础安装..."
      configure_os_base
    fi
  fi

  # 单包安装时忽略 --skip-* / --kind / --tag 过滤
  local saved_skip_formulae="${SKIP_FORMULAE:-false}"
  local saved_skip_casks="${SKIP_CASKS:-false}"
  local saved_skip_node="${SKIP_NODE:-false}"
  local saved_skip_omz="${SKIP_OMZ:-false}"
  SKIP_FORMULAE=false
  SKIP_CASKS=false
  SKIP_NODE=false
  SKIP_OMZ=false
  MACOS_SKIP_DOCKER=false
  MACOS_SKIP_VSCODE=false
  PACKAGES_IGNORE_FILTERS=true
  install_package_entry "$name" "$version" "$source" "$kind" "$tags"
  PACKAGES_IGNORE_FILTERS=false
  SKIP_FORMULAE="$saved_skip_formulae"
  SKIP_CASKS="$saved_skip_casks"
  SKIP_NODE="$saved_skip_node"
  SKIP_OMZ="$saved_skip_omz"
}

# ─── 安装后提示 ──────────────────────────────────────────────────────────────
post_install_notes() {
  step "安装后注意事项"

  echo -e "  ${YELLOW}iTerm2${NC}: 建议配置 Shell Integration:"
  echo -e "    打开 iTerm2 → 菜单 Install Shell Integration"
  echo -e ""
  echo -e "  ${YELLOW}fzf${NC}: 快捷键已启用 (Ctrl+T 模糊搜索文件，Ctrl+R 搜索历史)"
  echo -e "    如需重新配置，运行: \$(brew --prefix)/opt/fzf/install"
  echo -e ""
  echo -e "  ${YELLOW}tmux${NC}: 终端复用器"
  echo -e "    常用命令: tmux new -s <name>, tmux attach -t <name>"
  echo -e ""
  echo -e "  ${YELLOW}yazi${NC}: 终端文件管理器 — 启动: yazi"
  echo -e ""
  echo -e "  ${YELLOW}zoxide${NC}: 快速目录跳转，添加到 ~/.zshrc:"
  echo -e "    eval \"\$(zoxide init zsh)\""
  echo -e ""
  echo -e "  ${YELLOW}gh (GitHub CLI)${NC}: 安装完成后需登录：${BOLD}gh auth login${NC}"
  echo -e ""
  echo -e "  ${YELLOW}nvm / Node.js${NC}: 运行 ${BOLD}source ~/.zshrc${NC} 或打开新终端"
  echo -e ""
  echo -e "  ${YELLOW}VS Code${NC}: AI 扩展可通过 ./editors/vscode/setup.sh 安装"
  echo -e ""
  echo -e "  ${YELLOW}下一步（AI 研发环境）${NC}："
  echo -e "    languages/python/setup.sh    # Python + AI 包"
  echo -e "    languages/go/setup.sh        # Go 环境"
  echo -e "    agents/claude/setup.sh       # Claude Code"
  echo -e ""
}

# ─── 主入口 ──────────────────────────────────────────────────────────────────
main() {
  local info_only=false
  local check_only=false
  local install_name=""
  local base_only=false
  local packages_only=false
  DRY_RUN=false
  SKIP_BREW=false
  SKIP_CASKS=false
  SKIP_FORMULAE=false
  SKIP_NODE=false
  SKIP_OMZ=false
  MACOS_SKIP_DOCKER=false
  MACOS_SKIP_VSCODE=false
  PACKAGES_FILTER_KIND=""
  PACKAGES_FILTER_TAG=""
  PACKAGES_IGNORE_FILTERS=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)        usage; exit 0 ;;
      --info-only)      info_only=true ;;
      --check)          check_only=true ;;
      --install)
        shift
        [[ $# -gt 0 ]] || { error "--install 需要软件名"; usage; exit 1; }
        install_name="$1"
        ;;
      --kind)
        shift
        [[ $# -gt 0 ]] || { error "--kind 需要 cli|tui|gui"; usage; exit 1; }
        PACKAGES_FILTER_KIND="$1"
        packages_list_valid_kind "$PACKAGES_FILTER_KIND" || {
          error "--kind 无效: $PACKAGES_FILTER_KIND（使用 cli|tui|gui）"
          exit 1
        }
        ;;
      --tag)
        shift
        [[ $# -gt 0 ]] || { error "--tag 需要用途标签"; usage; exit 1; }
        PACKAGES_FILTER_TAG="$1"
        ;;
      --dry-run)        DRY_RUN=true ;;
      --base-only)      base_only=true ;;
      --packages-only)  packages_only=true ;;
      --skip-brew)      SKIP_BREW=true ;;
      --skip-casks)     SKIP_CASKS=true ;;
      --skip-formulae)  SKIP_FORMULAE=true ;;
      --skip-node)      SKIP_NODE=true ;;
      --skip-omz)       SKIP_OMZ=true ;;
      --skip-docker)    MACOS_SKIP_DOCKER=true ;;
      --skip-vscode)    MACOS_SKIP_VSCODE=true ;;
      *)
        error "未知参数: $1"
        usage
        exit 1
        ;;
    esac
    shift
  done

  if [[ "$base_only" == true && "$packages_only" == true ]]; then
    error "--base-only 与 --packages-only 不能同时使用"
    exit 1
  fi
  if [[ "$check_only" == true && -n "$install_name" ]]; then
    error "--check 与 --install 不能同时使用"
    exit 1
  fi

  echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${CYAN}║   macOS 初始化安装脚本               ║${NC}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════╝${NC}"

  detect_system_info

  if [[ "$info_only" == true ]]; then
    info "仅显示系统信息模式，退出。"
    exit 0
  fi

  if [[ "$check_only" == true ]]; then
    check_packages_status
    exit 0
  fi

  if [[ -n "$install_name" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
      info "dry-run 模式：不会实际安装"
    fi
    install_one_package "$install_name"
    echo -e "\n${GREEN}${BOLD}✓ 完成！${NC}\n"
    exit 0
  fi

  if [[ "$DRY_RUN" != true ]]; then
    echo -e "${YELLOW}即将开始安装，是否继续？[y/N]${NC} \c"
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      info "已取消安装。"
      exit 0
    fi
  else
    info "dry-run 模式：不会实际安装"
  fi

  if [[ "$packages_only" != true ]]; then
    configure_os_base
  fi

  if [[ "$base_only" != true ]]; then
    install_packages_from_list
  fi

  if [[ "$DRY_RUN" != true ]]; then
    post_install_notes
  fi

  echo -e "\n${GREEN}${BOLD}✓ 所有任务执行完成！${NC}\n"
}

main "$@"
