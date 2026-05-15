#!/usr/bin/env bash
# CentOS 初始化安装脚本
# 用途：自动安装常用开发工具和软件

set -euo pipefail

# ─── bash 版本检查 ───────────────────────────────────────────────────────────────
if [[ "${BASH_VERSINFO[0]}" -lt 3 ]]; then
  echo "ERROR: 此脚本需要 bash 3.2 或更高版本（当前: ${BASH_VERSION}）" >&2
  exit 1
fi

# ─── 颜色定义 ────────────────────────────────────────────────────────────────────
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

# ─── 工具函数 ────────────────────────────────────────────────────────────────────
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()    { echo -e "\n${BOLD}${CYAN}▶ $*${NC}"; }

# ─── 本地缓存配置 ────────────────────────────────────────────────────────────
# 若 cache/ 目录中存在对应文件，优先使用本地缓存，否则从官方 URL 下载。
# 运行 `cache/download.sh linux` 可预先下载所有文件。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${SCRIPT_DIR}/../../cache"

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

# ─── 用法说明 ────────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF

${BOLD}用法:${NC}
  $(basename "$0") [选项]

${BOLD}说明:${NC}
  CentOS 初始化脚本，自动检测系统信息并安装常用开发工具和软件。

${BOLD}选项:${NC}
  -h, --help          显示此帮助信息并退出
  --info-only         仅显示系统信息，不执行安装
  --skip-docker       跳过 Docker CE 安装
  --skip-git          跳过 Git 安装
  --skip-node         跳过 Node.js / npm 安装
  --skip-cloc         跳过 cloc 安装
  --skip-tools        跳过终端工具安装 (tmux, fzf, yazi, zoxide, lazygit)

${BOLD}安装的软件:${NC}
  Docker CE:
    docker-ce        - Docker 社区版
    docker-ce-cli    - Docker 命令行工具
    containerd.io    - 容器运行时

  Git:
    git              - 版本控制工具

  Node.js:
    nodejs (LTS)     - Node.js LTS 版本
    npm              - Node 包管理器

  cloc:
    cloc             - 代码行数统计工具

  终端增强工具:
    tmux             - 终端复用器
    fzf              - 模糊搜索工具
    yazi             - 终端文件管理器
    zoxide           - 快速目录跳转工具
    lazygit          - 终端 Git TUI 客户端

${BOLD}示例:${NC}
  $(basename "$0")                 # 完整安装
  $(basename "$0") --info-only     # 仅查看系统信息
  $(basename "$0") --skip-docker   # 跳过 Docker 安装

EOF
}

# ─── 系统信息检测 ────────────────────────────────────────────────────────────────
detect_system_info() {
  step "系统基本信息"

  # 系统版本
  local os_id os_version os_pretty_name
  if [[ -f /etc/os-release ]]; then
    os_id=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    os_version=$(grep '^VERSION_ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    os_pretty_name=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
  else
    os_id="unknown"
    os_version="unknown"
    os_pretty_name="unknown"
  fi

  # 检查是否为 CentOS/RHEL
  if [[ "$os_id" != "centos" && "$os_id" != "rhel" && "$os_id" != "rocky" && "$os_id" != "almalinux" ]]; then
    warn "此脚本主要针对 CentOS/RHEL 系列，当前系统: ${os_id}"
  fi

  # 架构
  local arch
  arch=$(uname -m)

  # CPU 核心数
  local cpu_cores
  cpu_cores=$(nproc 2>/dev/null || echo "unknown")

  # 内存
  local mem_total mem_gb
  if [[ -f /proc/meminfo ]]; then
    mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    mem_gb=$(( mem_total / 1024 / 1024 ))
  else
    mem_gb="unknown"
  fi

  # 磁盘空间
  local disk_info
  disk_info=$(df -h / | awk 'NR==2 {printf "总计 %s，已用 %s，可用 %s", $2, $3, $4}')

  # 主机名 & 用户
  local hostname username
  hostname=$(hostname 2>/dev/null || echo "unknown")
  username=$(whoami)

  # 内核版本
  local kernel
  kernel=$(uname -r)

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

# ─── 检查命令是否存在 ────────────────────────────────────────────────────────────
is_installed() {
  command -v "$1" &>/dev/null
}

# ─── 检测包管理器 ────────────────────────────────────────────────────────────────
detect_pkg_manager() {
  if command -v dnf &>/dev/null; then
    echo "dnf"
  elif command -v yum &>/dev/null; then
    echo "yum"
  else
    error "未找到 yum 或 dnf 包管理器"
    exit 1
  fi
}

# ─── 检查是否为 root 用户 ────────────────────────────────────────────────────────
check_root() {
  if [[ $EUID -ne 0 ]]; then
    if is_installed sudo; then
      info "需要 sudo 权限执行安装操作"
    else
      error "请使用 root 用户运行此脚本或安装 sudo"
      exit 1
    fi
  fi
}

# ─── 使用 sudo 或直接执行 ────────────────────────────────────────────────────────
run_cmd() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

# ─── 安装 Docker CE ──────────────────────────────────────────────────────────────
install_docker() {
  step "Docker CE 安装"

  if is_installed docker; then
    success "Docker 已安装：$(docker --version)"
    info "正在检查 Docker 服务状态..."
    if run_cmd systemctl is-active docker &>/dev/null; then
      success "Docker 服务正在运行"
    else
      info "正在启动 Docker 服务..."
      run_cmd systemctl start docker
      run_cmd systemctl enable docker
      success "Docker 服务已启动并设置为开机自启"
    fi
    return
  fi

  info "正在安装 Docker CE..."

  local pkg_manager
  pkg_manager=$(detect_pkg_manager)

  # 安装必要的依赖
  info "安装依赖包..."
  run_cmd "$pkg_manager" install -y yum-utils device-mapper-persistent-data lvm2

  # 添加 Docker 官方仓库
  info "添加 Docker 官方仓库..."
  local tmp_repo
  tmp_repo=$(mktemp --suffix=.repo)
  fetch "scripts/docker-ce.repo" "https://download.docker.com/linux/centos/docker-ce.repo" "$tmp_repo"
  run_cmd cp "$tmp_repo" /etc/yum.repos.d/docker-ce.repo
  rm -f "$tmp_repo"

  # 安装 Docker
  info "安装 Docker CE..."
  run_cmd "$pkg_manager" install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # 启动并启用 Docker
  info "启动 Docker 服务..."
  run_cmd systemctl start docker
  run_cmd systemctl enable docker

  # 验证安装
  if is_installed docker; then
    success "Docker 安装完成：$(docker --version)"
  else
    error "Docker 安装失败"
    return 1
  fi

  # 将当前用户加入 docker 组（可选，需要重新登录生效）
  if [[ $EUID -ne 0 ]]; then
    info "将当前用户加入 docker 组..."
    run_cmd usermod -aG docker "$USER"
    warn "请重新登录以使用户组生效，之后可以使用非 root 用户运行 docker"
  fi
}

# ─── 安装 Git ────────────────────────────────────────────────────────────────────
install_git() {
  step "Git 安装"

  if is_installed git; then
    success "Git 已安装：$(git --version)"
    return
  fi

  info "正在安装 Git..."

  local pkg_manager
  pkg_manager=$(detect_pkg_manager)

  run_cmd "$pkg_manager" install -y git

  if is_installed git; then
    success "Git 安装完成：$(git --version)"
  else
    error "Git 安装失败"
    return 1
  fi
}

# ─── 安装 Node.js / npm ──────────────────────────────────────────────────────────
install_node() {
  step "Node.js / npm 安装"

  if is_installed node && is_installed npm; then
    success "Node.js 已安装：$(node --version)"
    success "npm 已安装：$(npm --version)"
    return
  fi

  info "正在安装 Node.js LTS..."

  local pkg_manager
  pkg_manager=$(detect_pkg_manager)

  # 方法一：使用 NodeSource 仓库（推荐）
  info "添加 NodeSource 仓库..."

  # 检测系统版本以确定正确的 NodeSource URL
  local distro_major_version
  if [[ -f /etc/os-release ]]; then
    distro_major_version=$(grep '^VERSION_ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"' | cut -d'.' -f1)
  else
    distro_major_version="7"
  fi

  # 使用 NodeSource 安装脚本
  local node_version="20"  # LTS 版本
  info "安装 Node.js ${node_version}.x LTS..."

  local tmp_node
  tmp_node=$(mktemp)
  fetch "scripts/nodesource-setup-${node_version}.x" "https://rpm.nodesource.com/setup_${node_version}.x" "$tmp_node"
  run_cmd bash "$tmp_node"
  rm -f "$tmp_node"

  # 安装 Node.js
  run_cmd "$pkg_manager" install -y nodejs

  # 验证安装
  if is_installed node && is_installed npm; then
    success "Node.js 安装完成：$(node --version)"
    success "npm 安装完成：$(npm --version)"
  else
    error "Node.js / npm 安装失败"
    return 1
  fi

  # 配置 npm 全局安装目录（可选，避免权限问题）
  local npm_global_dir="$HOME/.npm-global"
  if [[ ! -d "$npm_global_dir" ]]; then
    info "配置 npm 全局安装目录..."
    mkdir -p "$npm_global_dir"
    npm config set prefix "$npm_global_dir"

    # 添加到 PATH
    local profile_file
    if [[ -f "$HOME/.bashrc" ]]; then
      profile_file="$HOME/.bashrc"
    elif [[ -f "$HOME/.bash_profile" ]]; then
      profile_file="$HOME/.bash_profile"
    else
      profile_file="$HOME/.bashrc"
    fi

    if ! grep -q 'NPM_GLOBAL' "$profile_file" 2>/dev/null; then
      echo "" >> "$profile_file"
      echo "# npm global directory" >> "$profile_file"
      echo "export PATH=\"\$HOME/.npm-global/bin:\$PATH\"" >> "$profile_file"
      success "已将 npm 全局目录添加到 ${profile_file}"
      info "运行 'source ${profile_file}' 使 PATH 生效"
    fi
  fi
}

# ─── 安装 cloc ────────────────────────────────────────────────────────────────
install_cloc() {
  step "cloc 安装"

  if is_installed cloc; then
    success "cloc 已安装：$(cloc --version | head -1)"
    return
  fi

  info "正在安装 cloc..."

  local pkg_manager
  pkg_manager=$(detect_pkg_manager)

  run_cmd "$pkg_manager" install -y cloc

  if is_installed cloc; then
    success "cloc 安装完成：$(cloc --version | head -1)"
  else
    error "cloc 安装失败"
    return 1
  fi
}

# ─── 安装终端增强工具 (tmux, fzf, yazi, zoxide, lazygit) ─────────────────────────
install_tools() {
  step "终端增强工具安装 (tmux, fzf, yazi, zoxide, lazygit)"

  local pkg_manager
  pkg_manager=$(detect_pkg_manager)

  # tmux
  if is_installed tmux; then
    success "tmux 已安装：$(tmux -V)"
  else
    info "正在安装 tmux..."
    run_cmd "$pkg_manager" install -y tmux
    if is_installed tmux; then
      success "tmux 安装完成：$(tmux -V)"
    else
      warn "tmux 安装失败"
    fi
  fi

  # fzf
  if is_installed fzf; then
    success "fzf 已安装"
  else
    info "正在安装 fzf..."
    if run_cmd "$pkg_manager" install -y fzf 2>/dev/null; then
      success "fzf 安装完成"
    else
      local fzf_version="0.72.0"
      local fzf_arch
      case "$(uname -m)" in
        aarch64) fzf_arch="linux_arm64" ;;
        *)       fzf_arch="linux_amd64" ;;
      esac
      local fzf_filename="fzf-${fzf_version}-${fzf_arch}.tar.gz"
      local tmpdir; tmpdir=$(mktemp -d)
      if fetch "binaries/${fzf_filename}" \
           "https://github.com/junegunn/fzf/releases/download/v${fzf_version}/${fzf_filename}" \
           "$tmpdir/fzf.tar.gz" && \
         tar -xzf "$tmpdir/fzf.tar.gz" -C "$tmpdir" fzf 2>/dev/null; then
        run_cmd mv "$tmpdir/fzf" /usr/local/bin/fzf
        run_cmd chmod +x /usr/local/bin/fzf
        success "fzf 安装完成"
      else
        warn "fzf 安装失败，请手动安装"
      fi
      rm -rf "$tmpdir"
    fi
  fi

  # yazi
  if is_installed yazi; then
    success "yazi 已安装"
  else
    info "正在安装 yazi..."
    # 检查是否有预编译版本
    local arch
    arch=$(uname -m)
    local yazi_arch="$arch"
    [[ "$arch" == "x86_64" ]] && yazi_arch="x86_64"

    # 尝试下载最新版本
    local yazi_version="0.3.3"
    # 使用 musl 静态编译版本，不依赖系统 glibc，兼容 CentOS/RHEL 8（glibc 2.28）
    local yazi_filename="yazi-${yazi_arch}-unknown-linux-musl.zip"

    info "下载 yazi v${yazi_version}..."
    local tmpdir
    tmpdir=$(mktemp -d)
    fetch "binaries/${yazi_filename}" \
      "https://github.com/sxyazi/yazi/releases/download/v${yazi_version}/${yazi_filename}" \
      "$tmpdir/yazi.zip" 2>/dev/null
    if [[ -f "$tmpdir/yazi.zip" ]]; then
      if ! command -v unzip &>/dev/null; then
        run_cmd "$pkg_manager" install -y unzip
      fi
      unzip -q "$tmpdir/yazi.zip" -d "$tmpdir"
      local yazi_bin="$tmpdir/yazi-${yazi_arch}-unknown-linux-musl/yazi"
      if [[ -f "$yazi_bin" ]]; then
        run_cmd mv "$yazi_bin" /usr/local/bin/yazi
        run_cmd chmod +x /usr/local/bin/yazi
        success "yazi 安装完成"
      else
        warn "yazi 解压失败"
      fi
      rm -rf "$tmpdir"
    else
      warn "yazi 下载失败，请手动安装"
    fi
  fi

  # zoxide
  if is_installed zoxide; then
    success "zoxide 已安装"
  else
    info "正在安装 zoxide..."
    local zoxide_version="0.9.4"
    local zoxide_arch
    case "$(uname -m)" in
      aarch64) zoxide_arch="aarch64-unknown-linux-musl" ;;
      *)       zoxide_arch="x86_64-unknown-linux-musl" ;;
    esac
    local zoxide_filename="zoxide-${zoxide_version}-${zoxide_arch}.tar.gz"
    local tmpdir; tmpdir=$(mktemp -d)
    if fetch "binaries/${zoxide_filename}" \
         "https://github.com/ajeetdsouza/zoxide/releases/download/v${zoxide_version}/${zoxide_filename}" \
         "$tmpdir/zoxide.tar.gz" && \
       tar -xzf "$tmpdir/zoxide.tar.gz" -C "$tmpdir" zoxide 2>/dev/null; then
      run_cmd mv "$tmpdir/zoxide" /usr/local/bin/zoxide
      run_cmd chmod +x /usr/local/bin/zoxide
      success "zoxide 安装完成"
    else
      warn "zoxide 安装失败，请手动安装"
    fi
    rm -rf "$tmpdir"
  fi

  # lazygit
  if is_installed lazygit; then
    success "lazygit 已安装：$(lazygit --version | head -1)"
  else
    info "正在安装 lazygit..."
    # 下载预编译版本
    local lazygit_version="0.44.1"
    local arch
    arch=$(uname -m)
    local lazygit_arch="$arch"
    [[ "$arch" == "x86_64" ]] && lazygit_arch="x86_64"
    [[ "$arch" == "aarch64" ]] && lazygit_arch="arm64"

    local lazygit_filename="lazygit_${lazygit_version}_Linux_${lazygit_arch}.tar.gz"

    local tmpdir
    tmpdir=$(mktemp -d)
    fetch "binaries/${lazygit_filename}" \
      "https://github.com/jesseduffield/lazygit/releases/download/v${lazygit_version}/${lazygit_filename}" \
      "$tmpdir/lazygit.tar.gz" 2>/dev/null
    if [[ -f "$tmpdir/lazygit.tar.gz" ]]; then
      if tar -xzf "$tmpdir/lazygit.tar.gz" -C "$tmpdir" lazygit 2>/dev/null; then
        run_cmd mv "$tmpdir/lazygit" /usr/local/bin/lazygit
        run_cmd chmod +x /usr/local/bin/lazygit
        success "lazygit 安装完成：$(lazygit --version | head -1)"
      else
        warn "lazygit 解压失败"
      fi
    else
      warn "lazygit 下载失败，请手动安装"
    fi
    rm -rf "$tmpdir"
  fi
}

# ─── 安装后提示 ──────────────────────────────────────────────────────────────────
post_install_notes() {
  step "安装后注意事项"

  echo -e "  ${YELLOW}Docker${NC}: 如需非 root 用户运行 docker，请执行："
  echo -e "    sudo usermod -aG docker \$USER"
  echo -e "    然后重新登录系统。"
  echo -e ""
  echo -e "  ${YELLOW}Node.js${NC}: 全局安装的包位于 ~/.npm-global"
  echo -e "    运行 ${BOLD}source ~/.bashrc${NC} 或重新登录以使 PATH 生效。"
  echo -e ""
  echo -e "  ${YELLOW}npm 常用命令${NC}:"
  echo -e "    npm -g install <package>    # 全局安装包"
  echo -e "    npm -g list                 # 查看全局已安装包"
  echo -e "    npm config list             # 查看 npm 配置"
  echo -e ""
  echo -e "  ${YELLOW}Docker 常用命令${NC}:"
  echo -e "    docker ps                   # 查看运行中的容器"
  echo -e "    docker images               # 查看镜像列表"
  echo -e "    docker compose up -d        # 使用 compose 启动服务"
  echo -e ""
  echo -e "  ${YELLOW}cloc 代码统计${NC}:"
  echo -e "    cloc <path>                 # 统计目录代码行数"
  echo -e "    cloc --by-file <path>       # 按文件统计"
  echo -e "    cloc --include-lang=Python,Go <path>  # 仅统计指定语言"
  echo -e ""
  echo -e "  ${YELLOW}终端增强工具${NC}:"
  echo -e "    tmux new -s <name>          # 创建新会话"
  echo -e "    tmux attach -t <name>       # 附加到会话"
  echo -e "    fzf                         # 模糊搜索文件"
  echo -e "    yazi                        # 终端文件管理器"
  echo -e "    z <目录名>                   # 快速目录跳转"
  echo -e "    lazygit                     # 终端 Git TUI 客户端"
  echo -e "    注意: zoxide 需要添加到 shell 配置: eval \"\$(zoxide init bash)\""
  echo -e ""
}

# ─── 主入口 ──────────────────────────────────────────────────────────────────────
main() {
  local info_only=false
  local skip_docker=false
  local skip_git=false
  local skip_node=false
  local skip_cloc=false
  local skip_tools=false

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
      --skip-docker)
        skip_docker=true
        ;;
      --skip-git)
        skip_git=true
        ;;
      --skip-node)
        skip_node=true
        ;;
      --skip-cloc)
        skip_cloc=true
        ;;
      --skip-tools)
        skip_tools=true
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
  echo -e "${BOLD}${CYAN}║   CentOS 初始化安装脚本              ║${NC}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════╝${NC}"

  # 检测系统信息（始终执行）
  detect_system_info

  if [[ "$info_only" == true ]]; then
    info "仅显示系统信息模式，退出。"
    exit 0
  fi

  # 检查权限
  check_root

  # 确认提示
  echo -e "${YELLOW}即将开始安装，是否继续？[y/N]${NC} \c"
  read -r confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    info "已取消安装。"
    exit 0
  fi

  $skip_docker || install_docker
  $skip_git    || install_git
  $skip_node   || install_node
  $skip_cloc   || install_cloc
  $skip_tools  || install_tools

  post_install_notes

  echo -e "\n${GREEN}${BOLD}✓ 所有任务执行完成！${NC}\n"
}

main "$@"