#!/usr/bin/env bash
# CentOS 初始化安装脚本
# Part 1: OS 基础配置（系统信息、包管理器、基础依赖）
# Part 2: 按 packages.centos.list 安装常见软件

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

# ─── 路径与缓存 ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${DEVTOOLS_CACHE_DIR:-${SCRIPT_DIR}/../../cache}"
OS_RELEASE_FILE="${OS_RELEASE_FILE:-/etc/os-release}"
PACKAGES_LIST="${SCRIPT_DIR}/packages.centos.list"
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

# ─── Alibaba Cloud Linux / Docker repo helpers ───────────────────────────────────
is_alibaba_linux_4() {
  local ID="" VERSION_ID=""
  if [[ -r "$OS_RELEASE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$OS_RELEASE_FILE"
  fi
  [[ "$ID" == "alinux" && "${VERSION_ID%%.*}" == "4" ]]
}

docker_repo_base_url() {
  if is_alibaba_linux_4; then
    echo "${DOCKER_MIRROR_BASE_URL:-http://mirrors.cloud.aliyuncs.com}/docker-ce/linux/centos"
  else
    echo "https://download.docker.com/linux/centos"
  fi
}

docker_repo_version() {
  if ! is_alibaba_linux_4; then
    return 0
  fi

  local version="${DOCKER_CENTOS_REPO_VERSION:-9}"
  case "$version" in
    9|10) echo "$version" ;;
    *)
      error "DOCKER_CENTOS_REPO_VERSION 必须是 9 或 10，当前: ${version}"
      return 1
      ;;
  esac
}

render_docker_repo() {
  local template="$1" output="$2" base_url version
  local -a sed_args

  base_url="$(docker_repo_base_url)"
  sed_args=(-e "s|https://download.docker.com/linux/centos|${base_url}|g")
  if is_alibaba_linux_4; then
    version="$(docker_repo_version)" || return 1
    sed_args+=(-e "s|\$releasever|${version}|g")
  fi

  sed "${sed_args[@]}" "$template" > "$output"
  [[ -s "$output" ]] || {
    error "Docker repo 配置为空: ${output}"
    return 1
  }
}

# ─── 用法说明 ────────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF

${BOLD}用法:${NC}
  $(basename "$0") [选项]

${BOLD}说明:${NC}
  CentOS 初始化脚本，分两段执行：
    1. OS 基础配置（系统信息、包管理器、基础依赖）
    2. 按 packages.centos.list 安装常见软件

${BOLD}选项:${NC}
  -h, --help          显示此帮助信息并退出
  --info-only         仅显示系统信息，不执行安装
  --check             检查 packages.centos.list 中各软件是否已安装
  --install <name>    仅安装清单中的指定软件（如 bat、rg、jq）
  --kind <cli|tui|gui>
                      按界面类型筛选（可与 --check / 安装联用）
  --tag <tag>         按用途筛选：productivity|diagnostic|dev|ops|shell
  --dry-run           预览将执行的步骤，不实际安装
  --base-only         仅执行 OS 基础配置
  --packages-only     跳过基础配置，仅按清单安装
  --skip-docker       跳过 Docker CE
  --skip-git          跳过 Git
  --skip-node         跳过 Node.js / npm
  --skip-cloc         跳过 cloc
  --skip-tools        跳过终端工具 (tmux, fzf, yazi, zoxide, lazygit)
  --skip-fonts        跳过 Nerd Fonts

${BOLD}清单文件:${NC}
  ${PACKAGES_LIST}

${BOLD}示例:${NC}
  $(basename "$0")                 # 完整安装
  $(basename "$0") --info-only     # 仅查看系统信息
  $(basename "$0") --check         # 检查清单安装状态
  $(basename "$0") --check --kind tui
  $(basename "$0") --check --tag diagnostic
  $(basename "$0") --install bat   # 只安装 bat
  $(basename "$0") --tag productivity --packages-only
  $(basename "$0") --dry-run       # 预览
  $(basename "$0") --skip-docker   # 跳过 Docker

EOF
}

# ─── 系统信息检测 ────────────────────────────────────────────────────────────────
detect_system_info() {
  step "系统基本信息"

  local os_id os_version os_pretty_name
  if [[ -f "$OS_RELEASE_FILE" ]]; then
    os_id=$(grep '^ID=' "$OS_RELEASE_FILE" | cut -d'=' -f2 | tr -d '"')
    os_version=$(grep '^VERSION_ID=' "$OS_RELEASE_FILE" | cut -d'=' -f2 | tr -d '"')
    os_pretty_name=$(grep '^PRETTY_NAME=' "$OS_RELEASE_FILE" | cut -d'=' -f2 | tr -d '"')
  else
    os_id="unknown"
    os_version="unknown"
    os_pretty_name="unknown"
  fi

  if [[ "$os_id" != "centos" && "$os_id" != "rhel" && "$os_id" != "rocky" && "$os_id" != "almalinux" && "$os_id" != "alinux" && "$os_id" != "anolis" ]]; then
    warn "此脚本主要针对 CentOS/RHEL 系列，当前系统: ${os_id}"
  fi

  local arch
  arch=$(uname -m)

  local cpu_cores
  cpu_cores=$(nproc 2>/dev/null || echo "unknown")

  local mem_total mem_gb
  if [[ -f /proc/meminfo ]]; then
    mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    mem_gb=$(( mem_total / 1024 / 1024 ))
  else
    mem_gb="unknown"
  fi

  local disk_info
  disk_info=$(df -h / | awk 'NR==2 {printf "总计 %s，已用 %s，可用 %s", $2, $3, $4}')

  local hostname username
  hostname=$(hostname 2>/dev/null || echo "unknown")
  username=$(whoami)

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

is_installed() {
  command -v "$1" &>/dev/null
}

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

run_cmd() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

# ─── Part 1: OS 基础配置 ─────────────────────────────────────────────────────────
install_base_deps() {
  step "基础依赖安装（OS 基础）"
  if [[ "${DRY_RUN:-false}" == true ]]; then
    info "[dry-run] 安装 curl wget ca-certificates yum-utils ..."
    return 0
  fi

  local pkg_manager
  pkg_manager=$(detect_pkg_manager)
  info "包管理器: ${pkg_manager}"
  run_cmd "$pkg_manager" install -y curl wget ca-certificates yum-utils \
    device-mapper-persistent-data lvm2 2>/dev/null || \
    run_cmd "$pkg_manager" install -y curl wget ca-certificates yum-utils
  success "基础依赖安装完成"
}

configure_os_base() {
  step "Part 1: OS 基础配置"
  check_root
  install_base_deps
}

# ─── Part 2: packages.list 适配器 ────────────────────────────────────────────────
should_skip_package() {
  local name="$1"
  case "$name" in
    docker) [[ "${SKIP_DOCKER:-false}" == true ]] && return 0 ;;
    git) [[ "${SKIP_GIT:-false}" == true ]] && return 0 ;;
    node) [[ "${SKIP_NODE:-false}" == true ]] && return 0 ;;
    cloc) [[ "${SKIP_CLOC:-false}" == true ]] && return 0 ;;
    tmux|fzf|yazi|zoxide|lazygit)
      [[ "${SKIP_TOOLS:-false}" == true ]] && return 0
      ;;
    nerd-fonts) [[ "${SKIP_FONTS:-false}" == true ]] && return 0 ;;
  esac
  return 1
}

install_docker() {
  step "Docker CE"

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

  info "添加 Docker 官方仓库..."
  local tmp_repo
  tmp_repo=$(mktemp --suffix=.repo)
  fetch "scripts/docker-ce.repo" "https://download.docker.com/linux/centos/docker-ce.repo" "$tmp_repo"
  local rendered_repo
  rendered_repo=$(mktemp --suffix=.repo)
  render_docker_repo "$tmp_repo" "$rendered_repo"
  run_cmd cp "$rendered_repo" /etc/yum.repos.d/docker-ce.repo
  rm -f "$tmp_repo"
  rm -f "$rendered_repo"

  info "安装 Docker CE..."
  if is_alibaba_linux_4; then
    run_cmd "$pkg_manager" install -y --nobest docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  else
    run_cmd "$pkg_manager" install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi

  info "启动 Docker 服务..."
  run_cmd systemctl start docker
  run_cmd systemctl enable docker

  if is_installed docker; then
    success "Docker 安装完成：$(docker --version)"
  else
    error "Docker 安装失败"
    return 1
  fi

  if [[ $EUID -ne 0 ]]; then
    info "将当前用户加入 docker 组..."
    run_cmd usermod -aG docker "$USER"
    warn "请重新登录以使用户组生效，之后可以使用非 root 用户运行 docker"
  fi
}

package_is_installed() {
  packages_list_default_is_installed "$1"
}

install_dnf_pkg() {
  local name="$1"
  local pkg
  pkg="$(packages_list_sys_pkg "$name")"
  if packages_list_default_is_installed "$name"; then
    success "${name} 已安装"
    return 0
  fi
  local pkg_manager
  pkg_manager=$(detect_pkg_manager)
  info "正在安装 ${name}（${pkg_manager} ${pkg}）..."
  run_cmd "$pkg_manager" install -y "$pkg"
  if packages_list_default_is_installed "$name"; then
    success "${name} 安装完成"
  else
    error "${name} 安装失败"
    return 1
  fi
}

install_node() {
  local node_version="$1"
  step "Node.js / npm（NodeSource ${node_version}.x）"

  if is_installed node && is_installed npm; then
    success "Node.js 已安装：$(node --version)"
    success "npm 已安装：$(npm --version)"
    return
  fi

  info "正在安装 Node.js ${node_version}.x LTS..."

  local pkg_manager
  pkg_manager=$(detect_pkg_manager)

  local tmp_node
  tmp_node=$(mktemp)
  fetch "scripts/nodesource-setup-${node_version}.x" "https://rpm.nodesource.com/setup_${node_version}.x" "$tmp_node"
  run_cmd bash "$tmp_node"
  rm -f "$tmp_node"

  run_cmd "$pkg_manager" install -y nodejs

  if is_installed node && is_installed npm; then
    success "Node.js 安装完成：$(node --version)"
    success "npm 安装完成：$(npm --version)"
  else
    error "Node.js / npm 安装失败"
    return 1
  fi

  local npm_global_dir="$HOME/.npm-global"
  if [[ ! -d "$npm_global_dir" ]]; then
    info "配置 npm 全局安装目录..."
    mkdir -p "$npm_global_dir"
    npm config set prefix "$npm_global_dir"

    local profile_file
    if [[ -f "$HOME/.bashrc" ]]; then
      profile_file="$HOME/.bashrc"
    elif [[ -f "$HOME/.bash_profile" ]]; then
      profile_file="$HOME/.bash_profile"
    else
      profile_file="$HOME/.bashrc"
    fi

    if ! grep -q 'NPM_GLOBAL\|npm-global' "$profile_file" 2>/dev/null; then
      echo "" >> "$profile_file"
      echo "# npm global directory" >> "$profile_file"
      echo "export PATH=\"\$HOME/.npm-global/bin:\$PATH\"" >> "$profile_file"
      success "已将 npm 全局目录添加到 ${profile_file}"
      info "运行 'source ${profile_file}' 使 PATH 生效"
    fi
  fi
}

install_tmux_module() {
  local tmux_setup="${SCRIPT_DIR}/../../terminal/tmux/setup.sh"
  if [[ -f "$tmux_setup" ]]; then
    info "通过 terminal/tmux/setup.sh 安装 tmux..."
    if TMUX_PREFIX=/usr/local DEVTOOLS_CACHE_DIR="$CACHE_DIR" \
        bash "$tmux_setup" --install-bin-only; then
      hash -r 2>/dev/null || true
      success "tmux 安装完成：$(command -v tmux 2>/dev/null || echo /usr/local/bin/tmux) $(/usr/local/bin/tmux -V 2>/dev/null || tmux -V 2>/dev/null || true)"
    else
      warn "tmux 安装失败"
    fi
  else
    warn "找不到 $tmux_setup，跳过 tmux"
  fi
}

install_fzf_github() {
  local fzf_version="$1"
  if is_installed fzf; then
    success "fzf 已安装"
    return 0
  fi

  local pkg_manager
  pkg_manager=$(detect_pkg_manager)
  info "正在安装 fzf..."
  if run_cmd "$pkg_manager" install -y fzf 2>/dev/null; then
    success "fzf 安装完成"
    return 0
  fi

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
}

install_yazi_github() {
  local yazi_version="$1"
  if is_installed yazi; then
    success "yazi 已安装"
    return 0
  fi

  info "正在安装 yazi v${yazi_version}..."
  local arch
  arch=$(uname -m)
  local yazi_arch="$arch"
  [[ "$arch" == "x86_64" ]] && yazi_arch="x86_64"
  local yazi_filename="yazi-${yazi_arch}-unknown-linux-musl.zip"

  local tmpdir
  tmpdir=$(mktemp -d)
  fetch "binaries/${yazi_filename}" \
    "https://github.com/sxyazi/yazi/releases/download/v${yazi_version}/${yazi_filename}" \
    "$tmpdir/yazi.zip" 2>/dev/null
  if [[ -f "$tmpdir/yazi.zip" ]]; then
    local pkg_manager
    pkg_manager=$(detect_pkg_manager)
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
  else
    warn "yazi 下载失败，请手动安装"
  fi
  rm -rf "$tmpdir"
}

install_zoxide_github() {
  local zoxide_version="$1"
  if is_installed zoxide; then
    success "zoxide 已安装"
    return 0
  fi

  info "正在安装 zoxide v${zoxide_version}..."
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
}

install_lazygit_github() {
  local lazygit_version="$1"
  if is_installed lazygit; then
    success "lazygit 已安装：$(lazygit --version | head -1)"
    return 0
  fi

  info "正在安装 lazygit v${lazygit_version}..."
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
}

install_bat_github() {
  local bat_version="$1"
  if packages_list_default_is_installed bat; then
    success "bat 已安装"
    return 0
  fi

  local pkg_manager
  pkg_manager=$(detect_pkg_manager)
  info "正在安装 bat v${bat_version}..."
  if run_cmd "$pkg_manager" install -y bat 2>/dev/null && packages_list_default_is_installed bat; then
    success "bat 安装完成（包管理器）"
    return 0
  fi

  local arch target
  case "$(uname -m)" in
    aarch64) target="aarch64-unknown-linux-musl" ;;
    *)       target="x86_64-unknown-linux-musl" ;;
  esac
  local filename="bat-v${bat_version}-${target}.tar.gz"
  local tmpdir; tmpdir=$(mktemp -d)
  if fetch "binaries/${filename}" \
       "https://github.com/sharkdp/bat/releases/download/v${bat_version}/${filename}" \
       "$tmpdir/bat.tar.gz" && \
     tar -xzf "$tmpdir/bat.tar.gz" -C "$tmpdir" 2>/dev/null; then
    local bat_bin
    bat_bin="$(find "$tmpdir" -type f -name bat | head -1)"
    if [[ -n "$bat_bin" ]]; then
      run_cmd install -m 755 "$bat_bin" /usr/local/bin/bat
      success "bat 安装完成"
    else
      warn "bat 解压失败"
    fi
  else
    warn "bat 下载失败，请手动安装"
  fi
  rm -rf "$tmpdir"
}

install_rg_github() {
  local rg_version="$1"
  if packages_list_default_is_installed rg; then
    success "rg 已安装"
    return 0
  fi

  local pkg_manager
  pkg_manager=$(detect_pkg_manager)
  info "正在安装 ripgrep (rg) v${rg_version}..."
  if run_cmd "$pkg_manager" install -y ripgrep 2>/dev/null && packages_list_default_is_installed rg; then
    success "rg 安装完成（包管理器）"
    return 0
  fi

  local target
  case "$(uname -m)" in
    aarch64) target="aarch64-unknown-linux-musl" ;;
    *)       target="x86_64-unknown-linux-musl" ;;
  esac
  local filename="ripgrep-${rg_version}-${target}.tar.gz"
  local tmpdir; tmpdir=$(mktemp -d)
  if fetch "binaries/${filename}" \
       "https://github.com/BurntSushi/ripgrep/releases/download/${rg_version}/${filename}" \
       "$tmpdir/rg.tar.gz" && \
     tar -xzf "$tmpdir/rg.tar.gz" -C "$tmpdir" 2>/dev/null; then
    local rg_bin
    rg_bin="$(find "$tmpdir" -type f -name rg | head -1)"
    if [[ -n "$rg_bin" ]]; then
      run_cmd install -m 755 "$rg_bin" /usr/local/bin/rg
      success "rg 安装完成"
    else
      warn "rg 解压失败"
    fi
  else
    warn "rg 下载失败，请手动安装"
  fi
  rm -rf "$tmpdir"
}

install_nerd_fonts() {
  local nerd_version="$1"
  step "Nerd Fonts（yazi 图标字体）"

  local font_dir="/usr/share/fonts/nerd-fonts"
  local marker="${font_dir}/.nerd-fonts-installed"

  if [[ -f "$marker" ]]; then
    success "Nerd Fonts 已安装"
    return
  fi

  info "正在安装 NerdFontsSymbolsOnly v${nerd_version}..."
  local nerd_filename="NerdFontsSymbolsOnly.tar.xz"
  local tmpdir
  tmpdir=$(mktemp -d)

  fetch "fonts/${nerd_filename}" \
    "https://github.com/ryanoasis/nerd-fonts/releases/download/v${nerd_version}/${nerd_filename}" \
    "$tmpdir/${nerd_filename}" 2>/dev/null

  if [[ -f "$tmpdir/${nerd_filename}" ]]; then
    run_cmd mkdir -p "$font_dir"
    run_cmd tar -xf "$tmpdir/${nerd_filename}" -C "$font_dir" --wildcards '*.ttf' '*.otf' 2>/dev/null || true
    run_cmd touch "$marker"
    if is_installed fc-cache; then
      run_cmd fc-cache -f "$font_dir"
    fi
    success "Nerd Fonts 安装完成 → ${font_dir}"
  else
    warn "Nerd Fonts 下载失败，请手动安装: https://www.nerdfonts.com/font-downloads"
  fi
  rm -rf "$tmpdir"
}

install_package_entry() {
  local name="$1" version="$2" source="$3" kind="${4:-}" tags="${5:-}"

  if [[ "${PACKAGES_IGNORE_FILTERS:-false}" != true ]] && \
     ! packages_list_match_filters "$kind" "$tags"; then
    return 0
  fi

  if should_skip_package "$name"; then
    info "跳过 ${name}"
    return 0
  fi

  if [[ "${DRY_RUN:-false}" == true ]]; then
    info "[dry-run] ${name} ${version} (${source}) [${kind}] ${tags}"
    return 0
  fi

  case "$source" in
    dnf)
      install_dnf_pkg "$name"
      ;;
    docker-ce)
      install_docker
      ;;
    nodesource)
      install_node "$version"
      ;;
    module)
      case "$name" in
        tmux) install_tmux_module ;;
        *) warn "未知 module 条目: $name" ;;
      esac
      ;;
    github)
      case "$name" in
        fzf) install_fzf_github "$version" ;;
        yazi) install_yazi_github "$version" ;;
        zoxide) install_zoxide_github "$version" ;;
        lazygit) install_lazygit_github "$version" ;;
        bat) install_bat_github "$version" ;;
        rg) install_rg_github "$version" ;;
        *) warn "未知 github 条目: $name" ;;
      esac
      ;;
    font)
      case "$name" in
        nerd-fonts) install_nerd_fonts "$version" ;;
        *) warn "未知 font 条目: $name" ;;
      esac
      ;;
    *)
      warn "不支持的 source: ${source}（${name}）"
      ;;
  esac
}

install_packages_from_list() {
  step "Part 2: 按 packages.centos.list 安装常见软件"
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
  step "检查 packages.centos.list 安装状态"
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
  check_root

  SKIP_DOCKER=false
  SKIP_GIT=false
  SKIP_NODE=false
  SKIP_CLOC=false
  SKIP_TOOLS=false
  SKIP_FONTS=false
  PACKAGES_IGNORE_FILTERS=true
  install_package_entry "$name" "$version" "$source" "$kind" "$tags"
  PACKAGES_IGNORE_FILTERS=false
}

post_install_notes() {
  step "安装后注意事项"

  echo -e "  ${YELLOW}Docker${NC}: 如需非 root 用户运行 docker，请执行："
  echo -e "    sudo usermod -aG docker \$USER"
  echo -e "    然后重新登录系统。"
  echo -e ""
  echo -e "  ${YELLOW}Node.js${NC}: 全局安装的包位于 ~/.npm-global"
  echo -e "    运行 ${BOLD}source ~/.bashrc${NC} 或重新登录以使 PATH 生效。"
  echo -e ""
  echo -e "  ${YELLOW}终端增强工具${NC}:"
  echo -e "    tmux / fzf / yazi / zoxide / lazygit"
  echo -e "    zoxide: eval \"\$(zoxide init bash)\""
  echo -e ""
  echo -e "  ${YELLOW}Nerd Fonts${NC}: /usr/share/fonts/nerd-fonts/"
  echo -e "    终端字体改为 SymbolsNerdFontMono 后 yazi 图标方可正常显示。"
  echo -e ""
}

main() {
  local info_only=false
  local check_only=false
  local install_name=""
  local base_only=false
  local packages_only=false
  DRY_RUN=false
  SKIP_DOCKER=false
  SKIP_GIT=false
  SKIP_NODE=false
  SKIP_CLOC=false
  SKIP_TOOLS=false
  SKIP_FONTS=false
  PACKAGES_FILTER_KIND=""
  PACKAGES_FILTER_TAG=""
  PACKAGES_IGNORE_FILTERS=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)       usage; exit 0 ;;
      --info-only)     info_only=true ;;
      --check)         check_only=true ;;
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
      --dry-run)       DRY_RUN=true ;;
      --base-only)     base_only=true ;;
      --packages-only) packages_only=true ;;
      --skip-docker)   SKIP_DOCKER=true ;;
      --skip-git)      SKIP_GIT=true ;;
      --skip-node)     SKIP_NODE=true ;;
      --skip-cloc)     SKIP_CLOC=true ;;
      --skip-tools)    SKIP_TOOLS=true ;;
      --skip-fonts)    SKIP_FONTS=true ;;
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
  echo -e "${BOLD}${CYAN}║   CentOS 初始化安装脚本              ║${NC}"
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
  else
    check_root
  fi

  if [[ "$base_only" != true ]]; then
    install_packages_from_list
  fi

  if [[ "$DRY_RUN" != true ]]; then
    post_install_notes
  fi

  echo -e "\n${GREEN}${BOLD}✓ 所有任务执行完成！${NC}\n"
}

if [[ "${SETUP_CENTOS_NO_MAIN:-false}" != "true" && "${SETUP_CENTOS_NO_MAIN:-false}" != "1" ]]; then
  main "$@"
fi
