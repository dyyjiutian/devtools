#!/usr/bin/env bash
# AI DevTools 根入口脚本
# 用途：交互式菜单，一键初始化 AI 研发环境

set -euo pipefail

if [[ "${BASH_VERSINFO[0]}" -lt 3 ]]; then
  echo "ERROR: 此脚本需要 bash 3.2 或更高版本" >&2; exit 1
fi

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'; CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()    { echo -e "\n${BOLD}${CYAN}▶ $*${NC}"; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(uname -s)"

usage() {
  cat <<EOF

${BOLD}用法:${NC}
  $(basename "$0") [选项]

${BOLD}选项:${NC}
  -h, --help              显示此帮助
  --all                   全量安装（无交互）
  --modules <list>        选择性安装，逗号分隔
                          可选值: os,python,go,java,rust,nodejs,
                                  claude,codex,cursor-agent,
                                  vscode,terminal,git
  --dry-run               预览，不实际安装

${BOLD}目录结构:${NC}
  os/                     OS 初始化（macOS / Ubuntu / CentOS）
  languages/              语言运行时（Python / Go / Java / Rust）
  shell/                  Shell 与 Prompt 配置
  terminal/               终端模拟器与终端工具
  editors/                Vim / Neovim / Cursor / VS Code
  agents/                 Claude / Codex / Cursor Agent 配置
  network/                FRP / Proxy / VPN 网络工具
  tools/                  Bazel / Git / SSH 独立工具

${BOLD}示例:${NC}
  $(basename "$0")                          # 交互式安装
  $(basename "$0") --all                    # 全量安装
  $(basename "$0") --modules python,go,claude
  $(basename "$0") --modules python --dry-run

EOF
}

# ─── OS 检测 ─────────────────────────────────────────────────────────────────
detect_os() {
  case "$OS" in
    Darwin) echo "macos" ;;
    Linux)
      if [[ -f /etc/os-release ]]; then
        local os_id
        os_id=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
        case "$os_id" in
          ubuntu|debian|linuxmint|pop) echo "ubuntu" ;;
          centos|rhel|rocky|almalinux) echo "centos" ;;
          *) echo "linux-generic" ;;
        esac
      else
        echo "linux-generic"
      fi
      ;;
    *) echo "unknown" ;;
  esac
}

# ─── 脚本执行器 ──────────────────────────────────────────────────────────────
run_script() {
  local script="$1"
  shift
  local args=("$@")

  if [[ ! -f "$script" ]]; then
    warn "脚本不存在: $script"
    return 0
  fi

  chmod +x "$script"

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] 将运行: $script ${args[*]:-}"
    return 0
  fi

  bash "$script" "${args[@]:-}"
}

# ─── 各模块安装函数 ──────────────────────────────────────────────────────────
install_os() {
  step "OS 基础环境初始化"
  local detected_os
  detected_os=$(detect_os)
  case "$detected_os" in
    macos)
      run_script "$REPO_ROOT/os/macos/setup.sh" ;;
    ubuntu)
      run_script "$REPO_ROOT/os/linux/setup_ubuntu.sh" ;;
    centos)
      run_script "$REPO_ROOT/os/linux/setup_centos.sh" ;;
    *)
      warn "未识别的 Linux 发行版，请手动选择："
      warn "  os/linux/setup_ubuntu.sh  （Ubuntu / Debian）"
      warn "  os/linux/setup_centos.sh  （CentOS / RHEL）"
      ;;
  esac
}

install_python() {
  run_script "$REPO_ROOT/languages/python/setup.sh"
}

install_go() {
  run_script "$REPO_ROOT/languages/go/setup.sh"
}

install_java() {
  run_script "$REPO_ROOT/languages/java/setup.sh"
}

install_rust() {
  run_script "$REPO_ROOT/languages/rust/setup.sh"
}

install_nodejs() {
  # 如果已通过 os/ 安装了 Node.js，这里可跳过
  if command -v node &>/dev/null; then
    success "Node.js 已安装：$(node --version)"
    return 0
  fi
  # 根据 OS 选择安装方式
  local detected_os; detected_os=$(detect_os)
  case "$detected_os" in
    macos)
      info "通过 nvm 安装 Node.js（macOS）..."
      local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
      if [[ -s "$nvm_dir/nvm.sh" ]]; then
        # shellcheck source=/dev/null
        source "$nvm_dir/nvm.sh"
        nvm install --lts && nvm alias default 'lts/*'
      else
        warn "未找到 nvm，请先运行 os/macos/setup.sh"
      fi
      ;;
    ubuntu|centos)
      info "请通过对应 os/linux/ 脚本安装 Node.js"
      ;;
  esac
}

install_claude() {
  run_script "$REPO_ROOT/agents/claude/setup.sh" install
}

install_codex() {
  run_script "$REPO_ROOT/agents/codex/setup.sh" install
}

install_cursor_agent() {
  run_script "$REPO_ROOT/agents/cursor-agent/setup.sh" install
}

install_vscode() {
  run_script "$REPO_ROOT/editors/vscode/setup.sh"
}

install_terminal() {
  step "终端配置"
  info "可用的终端配置脚本："
  info "  shell/oh-my-zsh/setup.sh    Oh My Zsh + powerlevel10k"
  info "  editors/nvim/setup.sh         Neovim + lazy.nvim + LSP"
  info "  editors/vim/setup.sh          Vim + coc.nvim"
  info "  terminal/ghostty/setup.sh      Ghostty 终端（macOS）"
  echo ""
  if [[ "$DRY_RUN" != true ]]; then
    read -r -p "运行 Oh My Zsh 配置？[y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] && run_script "$REPO_ROOT/shell/oh-my-zsh/setup.sh"
    read -r -p "运行 Neovim 配置？[y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] && run_script "$REPO_ROOT/editors/nvim/setup.sh"
  fi
}

install_git_config() {
  run_script "$REPO_ROOT/tools/git/scripts/config.sh"
}

# ─── 交互式菜单 ──────────────────────────────────────────────────────────────
show_menu() {
  local detected_os
  detected_os=$(detect_os)

  echo -e ""
  echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${CYAN}║        AI DevTools 初始化脚本                ║${NC}"
  echo -e "${BOLD}${CYAN}║   支持 macOS / Ubuntu / CentOS               ║${NC}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════╝${NC}"
  echo -e ""
  echo -e "  检测到系统: ${BOLD}${detected_os}${NC}"
  echo -e ""
  echo -e "  请选择要安装的组件（可多选，空格分隔，或输入 a 全选）："
  echo -e ""
  echo -e "  ${BOLD}OS 基础${NC}"
  echo -e "    ${CYAN}[1]${NC} OS 基础环境    Docker / Git / curl / 终端工具"
  echo -e ""
  echo -e "  ${BOLD}语言运行时${NC}"
  echo -e "    ${CYAN}[2]${NC} Python         pyenv + uv + AI 包（anthropic, langchain, jupyter）"
  echo -e "    ${CYAN}[3]${NC} Go             Go 运行时 + gopls + dlv + air"
  echo -e "    ${CYAN}[4]${NC} Java           SDKMan + JDK 21 + Maven + Gradle"
  echo -e "    ${CYAN}[5]${NC} Rust           rustup + stable + cargo 工具链"
  echo -e "    ${CYAN}[6]${NC} Node.js        nvm + LTS（如尚未安装）"
  echo -e ""
  echo -e "  ${BOLD}AI 工具${NC}"
  echo -e "    ${CYAN}[7]${NC} Claude Code    Agent CLI 安装与配置"
  echo -e "    ${CYAN}[8]${NC} Codex CLI      Agent CLI 安装与配置"
  echo -e "    ${CYAN}[9]${NC} Cursor Agent   Agent CLI 安装与配置"
  echo -e ""
  echo -e "  ${BOLD}编辑器${NC}"
  echo -e "    ${CYAN}[v]${NC} VS Code        安装 + AI 扩展（Continue.dev / Copilot）"
  echo -e ""
  echo -e "  ${BOLD}终端 & 版本控制${NC}"
  echo -e "    ${CYAN}[t]${NC} 终端配置       Oh My Zsh / Neovim / tmux"
  echo -e "    ${CYAN}[g]${NC} Git 配置       全局配置 + 快捷别名"
  echo -e ""
  echo -e "  ${CYAN}[a]${NC} 全部安装"
  echo -e "  ${CYAN}[q]${NC} 退出"
  echo -e ""
  printf "  选择: "
}

run_interactive() {
  show_menu
  read -r choices

  if [[ "$choices" == "q" ]]; then
    info "退出"
    exit 0
  fi

  if [[ "$choices" == "a" ]]; then
    choices="1 2 3 4 5 6 7 8 9 v t g"
  fi

  for choice in $choices; do
    case "$choice" in
      1) install_os ;;
      2) install_python ;;
      3) install_go ;;
      4) install_java ;;
      5) install_rust ;;
      6) install_nodejs ;;
      7) install_claude ;;
      8) install_codex ;;
      9) install_cursor_agent ;;
      v|V) install_vscode ;;
      t|T) install_terminal ;;
      g|G) install_git_config ;;
      *) warn "未知选项: $choice，跳过" ;;
    esac
  done
}

run_all() {
  step "全量安装"
  install_os
  install_python
  install_go
  install_java
  install_rust
  install_claude
  install_codex
  install_cursor_agent
  install_vscode
}

run_modules() {
  local modules="$1"
  IFS=',' read -ra module_list <<< "$modules"
  for module in "${module_list[@]}"; do
    module="${module// /}"  # trim spaces
    case "$module" in
      os)          install_os ;;
      python)      install_python ;;
      go)          install_go ;;
      java)        install_java ;;
      rust)        install_rust ;;
      nodejs)      install_nodejs ;;
      claude)      install_claude ;;
      codex)       install_codex ;;
      cursor-agent) install_cursor_agent ;;
      vscode)      install_vscode ;;
      terminal)    install_terminal ;;
      git)         install_git_config ;;
      *)           warn "未知模块: $module（跳过）" ;;
    esac
  done
}

# ─── 主入口 ──────────────────────────────────────────────────────────────────
main() {
  DRY_RUN=false
  local mode="interactive"
  local modules=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)    usage; exit 0 ;;
      --dry-run)    DRY_RUN=true ;;
      --all)        mode="all" ;;
      --modules)
        [[ -z "${2:-}" ]] && { error "--modules 需要值（逗号分隔）"; exit 1; }
        mode="modules"
        modules="$2"
        shift ;;
      *) error "未知参数: $1"; usage; exit 1 ;;
    esac
    shift
  done

  [[ "$DRY_RUN" == true ]] && warn "DRY-RUN 模式，不实际安装"

  case "$mode" in
    interactive) run_interactive ;;
    all)         run_all ;;
    modules)     run_modules "$modules" ;;
  esac

  echo -e "\n${GREEN}${BOLD}✓ 完成！${NC}\n"
  echo -e "  如需查看各组件详细帮助："
  echo -e "    languages/python/setup.sh --help"
  echo -e "    agents/claude/setup.sh --help"
  echo -e "    agents/codex/setup.sh --help"
  echo -e "    agents/cursor-agent/setup.sh --help"
  echo -e ""
}

main "$@"
