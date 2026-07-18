#!/usr/bin/env bash
# Ubuntu / Debian 初始化安装脚本
# 用途：自动安装常用开发工具和软件

set -euo pipefail

if [[ "${BASH_VERSINFO[0]}" -lt 3 ]]; then
  echo "ERROR: 此脚本需要 bash 3.2 或更高版本（当前: ${BASH_VERSION}）" >&2
  exit 1
fi

# ─── 颜色定义 ────────────────────────────────────────────────────────────────
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'; CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()    { echo -e "\n${BOLD}${CYAN}▶ $*${NC}"; }

is_installed() { command -v "$1" &>/dev/null; }

# ─── 用法说明 ────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF

${BOLD}用法:${NC}
  $(basename "$0") [选项]

${BOLD}说明:${NC}
  Ubuntu / Debian 初始化脚本，自动安装常用开发工具和软件。

${BOLD}选项:${NC}
  -h, --help          显示此帮助信息并退出
  --info-only         仅显示系统信息，不执行安装
  --skip-docker       跳过 Docker CE 安装
  --skip-git          跳过 Git 安装
  --skip-node         跳过 Node.js / npm 安装
  --skip-cloc         跳过 cloc 安装
  --skip-tools        跳过终端工具安装 (tmux, fzf, yazi, zoxide, lazygit)

${BOLD}安装的软件:${NC}
  基础工具:
    curl, wget, jq, tree, unzip, build-essential

  Docker CE:
    docker-ce, docker-ce-cli, containerd.io, docker-compose-plugin

  Git:
    git, git-lfs

  Node.js:
    Node.js LTS（通过 NodeSource）

  cloc:
    cloc（代码行数统计）

  终端增强工具:
    tmux 3.7b（源码安装）, fzf, yazi, zoxide, lazygit, gh（GitHub CLI）

${BOLD}示例:${NC}
  $(basename "$0")                 # 完整安装
  $(basename "$0") --info-only     # 仅查看系统信息
  $(basename "$0") --skip-docker   # 跳过 Docker 安装

EOF
}

# ─── 系统信息检测 ────────────────────────────────────────────────────────────
detect_system_info() {
  step "系统基本信息"

  local os_id os_version os_pretty_name
  if [[ -f /etc/os-release ]]; then
    os_id=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    os_version=$(grep '^VERSION_ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    os_pretty_name=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
  else
    os_id="unknown"; os_version="unknown"; os_pretty_name="unknown"
  fi

  if [[ "$os_id" != "ubuntu" && "$os_id" != "debian" && "$os_id" != "linuxmint" && "$os_id" != "pop" ]]; then
    warn "此脚本主要针对 Ubuntu/Debian 系列，当前系统: ${os_id}"
  fi

  local arch; arch=$(uname -m)
  local cpu_cores; cpu_cores=$(nproc 2>/dev/null || echo "unknown")
  local mem_gb="unknown"
  if [[ -f /proc/meminfo ]]; then
    mem_gb=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024 ))
  fi
  local disk_info; disk_info=$(df -h / | awk 'NR==2 {printf "总计 %s，已用 %s，可用 %s", $2, $3, $4}')
  local hostname; hostname=$(hostname 2>/dev/null || echo "unknown")
  local username; username=$(whoami)
  local kernel; kernel=$(uname -r)

  echo -e ""
  echo -e "  ${BOLD}操作系统${NC}   : ${os_pretty_name}"
  echo -e "  ${BOLD}系统 ID${NC}     : ${os_id} ${os_version}"
  echo -e "  ${BOLD}内核版本${NC}   : ${kernel}"
  echo -e "  ${BOLD}架构${NC}       : ${arch}"
  echo -e "  ${BOLD}CPU 核心数${NC} : ${cpu_cores} 核"
  echo -e "  ${BOLD}内存${NC}       : ${mem_gb} GB"
  echo -e "  ${BOLD}磁盘 (/)${NC}   : ${disk_info}"
  echo -e "  ${BOLD}主机名${NC}     : ${hostname}"
  echo -e "  ${BOLD}当前用户${NC}   : ${username}"
  echo -e ""
}

# ─── sudo 封装 ───────────────────────────────────────────────────────────────
run_cmd() {
  if [[ $EUID -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

check_root() {
  if [[ $EUID -ne 0 ]] && ! is_installed sudo; then
    error "请使用 root 用户运行或安装 sudo"
    exit 1
  fi
}

# ─── 基础依赖 ────────────────────────────────────────────────────────────────
install_base_deps() {
  step "基础工具安装"
  run_cmd apt-get update -qq
  run_cmd apt-get install -y \
    curl wget git git-lfs jq tree unzip zip \
    build-essential pkg-config libssl-dev \
    ca-certificates gnupg lsb-release \
    software-properties-common apt-transport-https
  success "基础工具安装完成"
}

# ─── Docker CE ───────────────────────────────────────────────────────────────
install_docker() {
  step "Docker CE 安装"

  if is_installed docker; then
    success "Docker 已安装：$(docker --version)"
    run_cmd systemctl is-active docker &>/dev/null || {
      run_cmd systemctl start docker
      run_cmd systemctl enable docker
    }
    return 0
  fi

  info "添加 Docker 官方 GPG 密钥..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    run_cmd gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  run_cmd chmod a+r /etc/apt/keyrings/docker.gpg

  info "添加 Docker 软件源..."
  local arch; arch=$(dpkg --print-architecture)
  local codename; codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
  echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable" | \
    run_cmd tee /etc/apt/sources.list.d/docker.list > /dev/null

  run_cmd apt-get update -qq
  run_cmd apt-get install -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

  run_cmd systemctl start docker
  run_cmd systemctl enable docker

  if is_installed docker; then
    success "Docker 安装完成：$(docker --version)"
  else
    error "Docker 安装失败"; return 1
  fi

  if [[ $EUID -ne 0 ]]; then
    run_cmd usermod -aG docker "$USER"
    warn "请重新登录以使 docker 组生效（之后可无 sudo 运行 docker）"
  fi
}

# ─── Git ─────────────────────────────────────────────────────────────────────
install_git() {
  step "Git 安装"

  if is_installed git; then
    success "Git 已安装：$(git --version)"
    return 0
  fi

  run_cmd apt-get install -y git git-lfs
  is_installed git && success "Git 安装完成：$(git --version)" || \
    { error "Git 安装失败"; return 1; }
}

# ─── Node.js ─────────────────────────────────────────────────────────────────
install_node() {
  step "Node.js / npm 安装"

  if is_installed node && is_installed npm; then
    success "Node.js 已安装：$(node --version)"
    return 0
  fi

  local node_version="20"
  info "添加 NodeSource 仓库（Node.js ${node_version}.x LTS）..."
  curl -fsSL "https://deb.nodesource.com/setup_${node_version}.x" | run_cmd bash -
  run_cmd apt-get install -y nodejs

  if is_installed node && is_installed npm; then
    success "Node.js 安装完成：$(node --version)，npm：$(npm --version)"
  else
    error "Node.js 安装失败"; return 1
  fi

  # 配置 npm 全局目录（避免权限问题）
  local npm_global_dir="$HOME/.npm-global"
  if [[ ! -d "$npm_global_dir" ]]; then
    mkdir -p "$npm_global_dir"
    npm config set prefix "$npm_global_dir"

    local rc_file="${HOME}/.bashrc"
    [[ -f "${HOME}/.zshrc" ]] && rc_file="${HOME}/.zshrc"

    if ! grep -q 'npm-global' "$rc_file" 2>/dev/null; then
      cat >> "$rc_file" <<'RCBLOCK'

# npm global directory
export PATH="$HOME/.npm-global/bin:$PATH"
RCBLOCK
      success "npm 全局目录已配置：$npm_global_dir"
    fi
  fi
}

# ─── cloc ────────────────────────────────────────────────────────────────────
install_cloc() {
  step "cloc 安装"

  if is_installed cloc; then
    success "cloc 已安装：$(cloc --version | head -1)"
    return 0
  fi

  run_cmd apt-get install -y cloc
  is_installed cloc && success "cloc 安装完成" || warn "cloc 安装失败"
}

# ─── 终端增强工具 ─────────────────────────────────────────────────────────────
install_tools() {
  step "终端增强工具安装"

  # tmux 3.7b（统一源码安装，保证 extended-keys / Codex Shift+Enter）
  local tmux_setup cache_dir
  tmux_setup="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../terminal/tmux/setup.sh"
  cache_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../cache"
  if [[ -f "$tmux_setup" ]]; then
    info "通过 terminal/tmux/setup.sh 安装 tmux 3.7b..."
    if TMUX_PREFIX=/usr/local DEVTOOLS_CACHE_DIR="$cache_dir" \
        bash "$tmux_setup" --install-bin-only; then
      hash -r 2>/dev/null || true
      success "tmux 安装完成：$(/usr/local/bin/tmux -V 2>/dev/null || tmux -V 2>/dev/null || true)"
    else
      warn "tmux 安装失败"
    fi
  else
    warn "找不到 $tmux_setup，跳过 tmux"
  fi

  # fzf
  if is_installed fzf; then
    success "fzf 已安装"
  else
    run_cmd apt-get install -y fzf 2>/dev/null || {
      info "通过 Git 安装 fzf..."
      git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
      "$HOME/.fzf/install" --all --no-bash --no-fish
    }
    is_installed fzf && success "fzf 安装完成" || warn "fzf 安装失败"
  fi

  # GitHub CLI (gh)
  if is_installed gh; then
    success "GitHub CLI 已安装：$(gh --version | head -1)"
  else
    info "安装 GitHub CLI..."
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
      run_cmd dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    run_cmd chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
      run_cmd tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    run_cmd apt-get update -qq
    run_cmd apt-get install -y gh
    is_installed gh && success "GitHub CLI 安装完成" || warn "GitHub CLI 安装失败"
  fi

  # zoxide
  if is_installed zoxide; then
    success "zoxide 已安装"
  else
    info "安装 zoxide..."
    if curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | \
       run_cmd bash -s -- --bin-dir /usr/local/bin 2>/dev/null; then
      success "zoxide 安装完成"
    else
      warn "zoxide 安装失败"
    fi
  fi

  # yazi（终端文件管理器）
  if is_installed yazi; then
    success "yazi 已安装"
  else
    info "安装 yazi..."
    local arch; arch=$(uname -m)
    local yazi_arch="x86_64"
    [[ "$arch" == "aarch64" ]] && yazi_arch="aarch64"
    local yazi_version="0.3.3"
    local tmpdir; tmpdir=$(mktemp -d)
    local url="https://github.com/sxyazi/yazi/releases/download/v${yazi_version}/yazi-${yazi_arch}-unknown-linux-gnu.zip"
    if curl -fsSL "$url" -o "$tmpdir/yazi.zip" 2>/dev/null && \
       unzip -q "$tmpdir/yazi.zip" -d "$tmpdir" 2>/dev/null; then
      local yazi_bin
      yazi_bin=$(find "$tmpdir" -name "yazi" -type f | head -1)
      [[ -n "$yazi_bin" ]] && run_cmd install -m 755 "$yazi_bin" /usr/local/bin/yazi && \
        success "yazi 安装完成" || warn "yazi 安装失败"
    else
      warn "yazi 下载失败，请手动安装"
    fi
    rm -rf "$tmpdir"
  fi

  # lazygit
  if is_installed lazygit; then
    success "lazygit 已安装：$(lazygit --version | head -1)"
  else
    info "安装 lazygit..."
    local arch; arch=$(uname -m)
    local lg_arch="x86_64"
    [[ "$arch" == "aarch64" ]] && lg_arch="arm64"
    local lg_ver="0.44.1"
    local tmpdir; tmpdir=$(mktemp -d)
    local url="https://github.com/jesseduffield/lazygit/releases/download/v${lg_ver}/lazygit_${lg_ver}_Linux_${lg_arch}.tar.gz"
    if curl -fsSL "$url" -o "$tmpdir/lazygit.tar.gz" 2>/dev/null && \
       tar -xzf "$tmpdir/lazygit.tar.gz" -C "$tmpdir" lazygit 2>/dev/null; then
      run_cmd install -m 755 "$tmpdir/lazygit" /usr/local/bin/lazygit
      success "lazygit 安装完成：$(lazygit --version | head -1)"
    else
      warn "lazygit 安装失败"
    fi
    rm -rf "$tmpdir"
  fi
}

# ─── 安装后提示 ──────────────────────────────────────────────────────────────
post_install_notes() {
  step "安装后注意事项"
  echo -e "  ${YELLOW}Docker${NC}: 如需非 root 运行 docker："
  echo -e "    sudo usermod -aG docker \$USER && 重新登录"
  echo -e ""
  echo -e "  ${YELLOW}Node.js${NC}: 全局包目录 ~/.npm-global"
  echo -e "    运行 ${BOLD}source ~/.bashrc${NC} 或重新登录使 PATH 生效"
  echo -e ""
  echo -e "  ${YELLOW}GitHub CLI${NC}: 登录："
  echo -e "    ${BOLD}gh auth login${NC}"
  echo -e ""
  echo -e "  ${YELLOW}zoxide${NC}: 快速目录跳转，添加到 ~/.bashrc："
  echo -e "    eval \"\$(zoxide init bash)\""
  echo -e ""
  echo -e "  ${YELLOW}终端工具${NC}："
  echo -e "    tmux new -s dev          # 新建 tmux 会话"
  echo -e "    yazi                     # 终端文件管理器"
  echo -e "    z <目录关键词>            # 快速跳转（zoxide）"
  echo -e "    lazygit                  # 终端 Git TUI"
  echo -e ""
  echo -e "  ${YELLOW}下一步（AI 研发环境）${NC}："
  echo -e "    lang/python/setup.sh    # Python + AI 包"
  echo -e "    lang/go/setup.sh        # Go 环境"
  echo -e "    lang/java/setup.sh      # Java + SDKMan"
  echo -e "    lang/rust/setup.sh      # Rust 环境"
  echo -e "    ai/coding/setup.sh      # Claude Code + Aider"
  echo -e "    ai/local-llm/setup.sh   # Ollama 本地大模型"
  echo -e ""
}

# ─── 主入口 ──────────────────────────────────────────────────────────────────
main() {
  local info_only=false
  local skip_docker=false
  local skip_git=false
  local skip_node=false
  local skip_cloc=false
  local skip_tools=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)      usage; exit 0 ;;
      --info-only)    info_only=true ;;
      --skip-docker)  skip_docker=true ;;
      --skip-git)     skip_git=true ;;
      --skip-node)    skip_node=true ;;
      --skip-cloc)    skip_cloc=true ;;
      --skip-tools)   skip_tools=true ;;
      *) error "未知参数: $1"; usage; exit 1 ;;
    esac
    shift
  done

  echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${CYAN}║   Ubuntu / Debian 初始化安装脚本     ║${NC}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════╝${NC}"

  detect_system_info

  if [[ "$info_only" == true ]]; then
    info "仅显示系统信息模式，退出。"
    exit 0
  fi

  check_root

  echo -e "${YELLOW}即将开始安装，是否继续？[y/N]${NC} \c"
  read -r confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    info "已取消安装。"
    exit 0
  fi

  install_base_deps
  $skip_docker || install_docker
  $skip_git    || install_git
  $skip_node   || install_node
  $skip_cloc   || install_cloc
  $skip_tools  || install_tools

  post_install_notes
  echo -e "\n${GREEN}${BOLD}✓ 所有任务执行完成！${NC}\n"
}

main "$@"
