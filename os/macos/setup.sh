#!/usr/bin/env bash
# macOS 初始化安装脚本
# 用途：自动安装常用开发工具和软件

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

# ─── 用法说明 ────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF

${BOLD}用法:${NC}
  $(basename "$0") [选项]

${BOLD}说明:${NC}
  macOS 初始化脚本，自动检测系统信息并安装常用开发工具和软件。

${BOLD}选项:${NC}
  -h, --help          显示此帮助信息并退出
  --info-only         仅显示系统信息，不执行安装
  --skip-brew         跳过 Homebrew 安装/更新
  --skip-casks        跳过 GUI 应用安装（iTerm2、Sublime Text、搜狗输入法、Obsidian 等）
  --skip-formulae     跳过 CLI 工具安装
  --skip-node         跳过 Node.js / npm 安装
  --skip-omz          跳过 Oh My Zsh 安装

${BOLD}安装的软件:${NC}
  CLI 工具 (brew formulae):
    git, curl, wget, jq, tree, htop, gh, neovim, cloc
    tmux, fzf, yazi, zoxide, lazygit  - 终端增强工具

  GUI 应用 (brew casks):
    iterm2          - 终端模拟器
    sublime-text    - 代码编辑器
    obsidian        - 知识库 / 笔记应用

  Node.js:
    nvm             - Node 版本管理器
    node (LTS)      - 通过 nvm 安装最新 LTS 版本

  Oh My Zsh:
    oh-my-zsh       - Zsh 配置管理框架（包含插件和主题支持）

${BOLD}示例:${NC}
  $(basename "$0")                 # 完整安装
  $(basename "$0") --info-only     # 仅查看系统信息
  $(basename "$0") --skip-casks    # 仅安装 CLI 工具

EOF
}

# ─── 系统信息检测 ────────────────────────────────────────────────────────────
detect_system_info() {
  step "系统基本信息"

  # macOS 版本
  local macos_version
  macos_version=$(sw_vers -productVersion)
  local macos_name
  macos_name=$(sw_vers -productName)
  local build
  build=$(sw_vers -buildVersion)

  # 芯片类型检测
  local chip_type chip_brand arch
  arch=$(uname -m)
  if [[ "$arch" == "arm64" ]]; then
    chip_brand=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Apple Silicon")
    chip_type="${GREEN}Apple Silicon (M 芯片)${NC}"
  else
    chip_brand=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Intel")
    chip_type="${YELLOW}Intel 芯片${NC}"
  fi

  # 内存
  local mem_bytes mem_gb
  mem_bytes=$(sysctl -n hw.memsize)
  mem_gb=$(( mem_bytes / 1024 / 1024 / 1024 ))

  # CPU 核心数
  local cpu_cores cpu_logical
  cpu_cores=$(sysctl -n hw.physicalcpu)
  cpu_logical=$(sysctl -n hw.logicalcpu)

  # 磁盘空间
  local disk_info
  disk_info=$(df -h / | awk 'NR==2 {printf "总计 %s，已用 %s，可用 %s", $2, $3, $4}')

  # 主机名 & 用户
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

# ─── 检查命令是否存在 ────────────────────────────────────────────────────────
is_installed() {
  command -v "$1" &>/dev/null
}

# ─── 安装 Homebrew ───────────────────────────────────────────────────────────
install_brew() {
  step "Homebrew"

  if is_installed brew; then
    success "Homebrew 已安装：$(brew --version | head -1)"
    info "正在更新 Homebrew..."
    brew update --quiet && success "Homebrew 已更新"
  else
    info "正在安装 Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Apple Silicon 需要配置 PATH
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

# ─── 安装 CLI 工具 ───────────────────────────────────────────────────────────
install_formulae() {
  step "CLI 工具安装"

  local formulae=(
    git
    curl
    wget
    jq
    tree
    htop
    gh
    neovim
    cloc
    tmux
    fzf
    yazi
    zoxide
    lazygit
  )

  for pkg in "${formulae[@]}"; do
    if brew list --formula "$pkg" &>/dev/null; then
      success "${pkg} 已安装，跳过"
    else
      info "正在安装 ${pkg}..."
      brew install "$pkg" && success "${pkg} 安装完成"
    fi
  done
}

# ─── 安装 GUI 应用（Casks）───────────────────────────────────────────────────
# 用 "cask:描述" 格式的普通数组，兼容 bash 3.2（macOS 自带版本不支持 declare -A）
install_casks() {
  step "GUI 应用安装"

  local casks=(
    "iterm2:iTerm2 终端"
    "sublime-text:Sublime Text 编辑器"
    "obsidian:Obsidian 知识库"
  )

  for entry in "${casks[@]}"; do
    local cask="${entry%%:*}"
    local desc="${entry#*:}"
    if brew list --cask "$cask" &>/dev/null; then
      success "${desc} 已安装，跳过"
    else
      info "正在安装 ${desc}..."
      if brew install --cask "$cask"; then
        success "${desc} 安装完成"
      else
        warn "${desc} 安装失败，请手动安装"
      fi
    fi
  done
}

# ─── 安装 Node.js（通过 nvm）────────────────────────────────────────────────
install_node() {
  step "Node.js / npm 安装"

  local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
  export NVM_DIR="$nvm_dir"

  # 安装或更新 nvm
  if [[ -s "$nvm_dir/nvm.sh" ]]; then
    # shellcheck source=/dev/null
    source "$nvm_dir/nvm.sh"
    success "nvm 已安装：$(nvm --version)"
  else
    info "正在安装 nvm..."
    # 用 bash 执行官方安装脚本（脚本本身用 bash 运行）
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/HEAD/install.sh | bash
    # shellcheck source=/dev/null
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
    success "nvm 安装完成：$(nvm --version)"
  fi

  # 确保 zshrc 中包含 nvm 初始化代码（官方安装脚本只写 .bashrc/.bash_profile）
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

  # 安装 Node.js LTS
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

# ─── 安装 Oh My Zsh ─────────────────────────────────────────────────────────
install_omz() {
  step "Oh My Zsh 安装"

  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    success "Oh My Zsh 已安装，跳过"
  else
    info "正在安装 Oh My Zsh..."
    # 使用官方安装脚本，保持静默安装
    if sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended; then
      success "Oh My Zsh 安装完成"
    else
      warn "Oh My Zsh 安装失败，请手动安装"
    fi
  fi
}

# ─── 安装后提示 ──────────────────────────────────────────────────────────────
post_install_notes() {
  step "安装后注意事项"

  echo -e "  ${YELLOW}搜狗输入法${NC}: 安装后请前往"
  echo -e "    系统设置 → 键盘 → 输入法 → 添加 "搜狗输入法""
  echo -e ""
  echo -e "  ${YELLOW}iTerm2${NC}: 建议配置 Shell Integration:"
  echo -e "    打开 iTerm2 → 菜单 Install Shell Integration"
  echo -e ""
  echo -e "  ${YELLOW}fzf${NC}: 快捷键已启用 (Ctrl+T 模糊搜索文件，Ctrl+R 搜索历史)"
  echo -e "    如需重新配置，运行: \$(brew --prefix)/opt/fzf/install"
  echo -e ""
  echo -e "  ${YELLOW}tmux${NC}: 终端复用器"
  echo -e "    常用命令: tmux new -s <name>, tmux attach -t <name>"
  echo -e ""
  echo -e "  ${YELLOW}yazi${NC}: 终端文件管理器"
  echo -e "    启动命令: yazi"
  echo -e ""
  echo -e "  ${YELLOW}zoxide${NC}: 快速目录跳转 (z 命令替代 cd)"
  echo -e "    用法: z <目录名或关键词>"
  echo -e "    添加到 ~/.zshrc: eval \"\$(zoxide init zsh)\""
  echo -e ""
  echo -e "  ${YELLOW}lazygit${NC}: 终端 Git TUI 客户端"
  echo -e "    启动命令: lazygit"
  echo -e ""
  echo -e "  ${YELLOW}gh (GitHub CLI)${NC}: 安装完成后需登录："
  echo -e "    ${BOLD}gh auth login${NC}"
  echo -e ""
  echo -e "  ${YELLOW}nvm / Node.js${NC}: 在当前终端立即生效，运行："
  echo -e "    ${BOLD}source ~/.zshrc${NC}"
  echo -e "  或直接打开新终端窗口。常用命令："
  echo -e "    nvm ls                  # 查看已安装版本"
  echo -e "    nvm install --lts       # 安装最新 LTS"
  echo -e "    nvm use <version>       # 切换版本"
  echo -e "    nvm alias default <ver> # 设置默认版本"
  echo -e ""
  echo -e "  ${YELLOW}Oh My Zsh${NC}: 配置文件位于 ~/.zshrc"
  echo -e "    查看主题: ls ~/.oh-my-zsh/themes/"
  echo -e "    查看插件: ls ~/.oh-my-zsh/plugins/"
  echo -e ""
}

# ─── 主入口 ──────────────────────────────────────────────────────────────────
main() {
  local info_only=false
  local skip_brew=false
  local skip_casks=false
  local skip_formulae=false
  local skip_node=false
  local skip_omz=false

  # 参数解析
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --info-only)
        info_only=true
        ;;
      --skip-brew)
        skip_brew=true
        ;;
      --skip-casks)
        skip_casks=true
        ;;
      --skip-formulae)
        skip_formulae=true
        ;;
      --skip-node)
        skip_node=true
        ;;
      --skip-omz)
        skip_omz=true
        ;;
      *)
        error "未知参数: $1"
        usage
        exit 1
        ;;
    esac
    shift
  done

  echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${CYAN}║   macOS 初始化安装脚本               ║${NC}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════╝${NC}"

  # 检测系统信息（始终执行）
  detect_system_info

  if [[ "$info_only" == true ]]; then
    info "仅显示系统信息模式，退出。"
    exit 0
  fi

  # 确认提示
  echo -e "${YELLOW}即将开始安装，是否继续？[y/N]${NC} \c"
  read -r confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    info "已取消安装。"
    exit 0
  fi

  $skip_brew     || install_brew
  $skip_formulae || install_formulae
  $skip_casks    || install_casks
  $skip_node     || install_node
  $skip_omz      || install_omz

  post_install_notes

  echo -e "\n${GREEN}${BOLD}✓ 所有任务执行完成！${NC}\n"
}

main "$@"
