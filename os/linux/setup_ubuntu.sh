#!/usr/bin/env bash
# Ubuntu / Debian 初始化安装脚本
# Part 1: OS 基础配置（系统信息、apt 基础依赖）
# Part 2: 按 packages.ubuntu.list 安装常见软件

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${DEVTOOLS_CACHE_DIR:-${SCRIPT_DIR}/../../cache}"
PACKAGES_LIST="${SCRIPT_DIR}/packages.ubuntu.list"
OS_RELEASE_FILE="${OS_RELEASE_FILE:-/etc/os-release}"
# shellcheck source=../lib/packages_list.sh
source "${SCRIPT_DIR}/../lib/packages_list.sh"

# ─── 用法说明 ────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF

${BOLD}用法:${NC}
  $(basename "$0") [选项]

${BOLD}说明:${NC}
  Ubuntu / Debian 初始化脚本，分两段执行：
    1. OS 基础配置（系统信息、apt 基础依赖）
    2. 按 packages.ubuntu.list 安装常见软件

${BOLD}选项:${NC}
  -h, --help          显示此帮助信息并退出
  --info-only         仅显示系统信息，不执行安装
  --check             检查 packages.ubuntu.list 中各软件是否已安装
  --install <name>    仅安装清单中的指定软件（如 bat、rg、jq）
  --kind <cli|tui|gui>
                      按界面类型筛选（可与 --check / 安装联用）
  --tag <tag>         按用途筛选：productivity|diagnostic|dev|ops|shell
  --dry-run           预览将执行的步骤，不实际安装
  --base-only         仅执行 OS 基础配置
  --packages-only     跳过基础配置，仅按清单安装
  --skip-docker       跳过 Docker CE
  --skip-git          跳过 Git / git-lfs
  --skip-node         跳过 Node.js
  --skip-cloc         跳过 cloc
  --skip-tools        跳过终端工具 (tmux, fzf, yazi, zoxide, lazygit, gh)

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

# ─── 系统信息检测 ────────────────────────────────────────────────────────────
detect_system_info() {
  step "系统基本信息"

  local os_id os_version os_pretty_name
  if [[ -f "$OS_RELEASE_FILE" ]]; then
    os_id=$(grep '^ID=' "$OS_RELEASE_FILE" | cut -d'=' -f2 | tr -d '"')
    os_version=$(grep '^VERSION_ID=' "$OS_RELEASE_FILE" | cut -d'=' -f2 | tr -d '"')
    os_pretty_name=$(grep '^PRETTY_NAME=' "$OS_RELEASE_FILE" | cut -d'=' -f2 | tr -d '"')
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

run_cmd() {
  if [[ $EUID -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

check_root() {
  if [[ $EUID -ne 0 ]] && ! is_installed sudo; then
    error "请使用 root 用户运行或安装 sudo"
    exit 1
  fi
}

# ─── Part 1: OS 基础配置 ─────────────────────────────────────────────────────
install_base_deps() {
  step "基础工具安装（OS 基础）"
  if [[ "${DRY_RUN:-false}" == true ]]; then
    info "[dry-run] apt-get update && install curl wget jq tree unzip zip build-essential ..."
    return 0
  fi
  run_cmd apt-get update -qq
  run_cmd apt-get install -y \
    curl wget tree unzip zip \
    build-essential pkg-config libssl-dev \
    ca-certificates gnupg lsb-release \
    software-properties-common apt-transport-https
  success "基础工具安装完成"
}

configure_os_base() {
  step "Part 1: OS 基础配置"
  check_root
  install_base_deps
}

# ─── Part 2: packages.list 适配器 ────────────────────────────────────────────
should_skip_package() {
  local name="$1"
  case "$name" in
    docker) [[ "${SKIP_DOCKER:-false}" == true ]] && return 0 ;;
    git|git-lfs) [[ "${SKIP_GIT:-false}" == true ]] && return 0 ;;
    node) [[ "${SKIP_NODE:-false}" == true ]] && return 0 ;;
    cloc) [[ "${SKIP_CLOC:-false}" == true ]] && return 0 ;;
    tmux|fzf|yazi|zoxide|lazygit|gh)
      [[ "${SKIP_TOOLS:-false}" == true ]] && return 0
      ;;
  esac
  return 1
}

install_docker() {
  step "Docker CE"

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
  local codename; codename=$(. "$OS_RELEASE_FILE" && echo "$VERSION_CODENAME")
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

package_is_installed() {
  packages_list_default_is_installed "$1"
}

install_apt_pkg() {
  local name="$1"
  local pkg
  pkg="$(packages_list_sys_pkg "$name")"

  if packages_list_default_is_installed "$name" || dpkg -s "$pkg" &>/dev/null; then
    success "${name} 已安装，跳过"
    # Ubuntu 的 bat 包提供 batcat，补一个 bat 别名
    if [[ "$name" == "bat" ]] && ! is_installed bat && is_installed batcat; then
      run_cmd ln -sfn "$(command -v batcat)" /usr/local/bin/bat
      success "已创建 bat → batcat 链接"
    fi
    return 0
  fi
  info "正在安装 ${name}（apt ${pkg}）..."
  run_cmd apt-get install -y "$pkg"
  if [[ "$name" == "bat" ]] && ! is_installed bat && is_installed batcat; then
    run_cmd ln -sfn "$(command -v batcat)" /usr/local/bin/bat
  fi
  if packages_list_default_is_installed "$name"; then
    success "${name} 安装完成"
  else
    warn "${name} 安装后未检测到命令，请检查 PATH"
  fi
}

install_node() {
  local node_version="$1"
  step "Node.js / npm（NodeSource ${node_version}.x）"

  if is_installed node && is_installed npm; then
    success "Node.js 已安装：$(node --version)"
    return 0
  fi

  info "添加 NodeSource 仓库（Node.js ${node_version}.x LTS）..."
  curl -fsSL "https://deb.nodesource.com/setup_${node_version}.x" | run_cmd bash -
  run_cmd apt-get install -y nodejs

  if is_installed node && is_installed npm; then
    success "Node.js 安装完成：$(node --version)，npm：$(npm --version)"
  else
    error "Node.js 安装失败"; return 1
  fi

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

install_tmux_module() {
  local tmux_setup="${SCRIPT_DIR}/../../terminal/tmux/setup.sh"
  if [[ -f "$tmux_setup" ]]; then
    info "通过 terminal/tmux/setup.sh 安装 tmux..."
    if TMUX_PREFIX=/usr/local DEVTOOLS_CACHE_DIR="$CACHE_DIR" \
        bash "$tmux_setup" --install-bin-only; then
      hash -r 2>/dev/null || true
      success "tmux 安装完成：$(/usr/local/bin/tmux -V 2>/dev/null || tmux -V 2>/dev/null || true)"
    else
      warn "tmux 安装失败"
    fi
  else
    warn "找不到 $tmux_setup，跳过 tmux"
  fi
}

install_gh_apt_repo() {
  if is_installed gh; then
    success "GitHub CLI 已安装：$(gh --version | head -1)"
    return 0
  fi
  info "安装 GitHub CLI..."
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
    run_cmd dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
  run_cmd chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
    run_cmd tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  run_cmd apt-get update -qq
  run_cmd apt-get install -y gh
  is_installed gh && success "GitHub CLI 安装完成" || warn "GitHub CLI 安装失败"
}

install_zoxide_script() {
  if is_installed zoxide; then
    success "zoxide 已安装"
    return 0
  fi
  info "安装 zoxide..."
  if curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | \
     run_cmd bash -s -- --bin-dir /usr/local/bin 2>/dev/null; then
    success "zoxide 安装完成"
  else
    warn "zoxide 安装失败"
  fi
}

install_yazi_github() {
  local version="$1"
  if is_installed yazi; then
    success "yazi 已安装"
    return 0
  fi
  info "安装 yazi v${version}..."
  local arch; arch=$(uname -m)
  local yazi_arch="x86_64"
  [[ "$arch" == "aarch64" ]] && yazi_arch="aarch64"
  local tmpdir; tmpdir=$(mktemp -d)
  local url="https://github.com/sxyazi/yazi/releases/download/v${version}/yazi-${yazi_arch}-unknown-linux-gnu.zip"
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
}

install_lazygit_github() {
  local version="$1"
  if is_installed lazygit; then
    success "lazygit 已安装：$(lazygit --version | head -1)"
    return 0
  fi
  info "安装 lazygit v${version}..."
  local arch; arch=$(uname -m)
  local lg_arch="x86_64"
  [[ "$arch" == "aarch64" ]] && lg_arch="arm64"
  local tmpdir; tmpdir=$(mktemp -d)
  local url="https://github.com/jesseduffield/lazygit/releases/download/v${version}/lazygit_${version}_Linux_${lg_arch}.tar.gz"
  if curl -fsSL "$url" -o "$tmpdir/lazygit.tar.gz" 2>/dev/null && \
     tar -xzf "$tmpdir/lazygit.tar.gz" -C "$tmpdir" lazygit 2>/dev/null; then
    run_cmd install -m 755 "$tmpdir/lazygit" /usr/local/bin/lazygit
    success "lazygit 安装完成：$(lazygit --version | head -1)"
  else
    warn "lazygit 安装失败"
  fi
  rm -rf "$tmpdir"
}

install_fzf_apt_or_git() {
  if is_installed fzf; then
    success "fzf 已安装"
    return 0
  fi
  run_cmd apt-get install -y fzf 2>/dev/null || {
    info "通过 Git 安装 fzf..."
    git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
    "$HOME/.fzf/install" --all --no-bash --no-fish
  }
  is_installed fzf && success "fzf 安装完成" || warn "fzf 安装失败"
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
    apt)
      case "$name" in
        fzf) install_fzf_apt_or_git ;;
        *) install_apt_pkg "$name" ;;
      esac
      ;;
    apt-repo)
      case "$name" in
        gh) install_gh_apt_repo ;;
        *) warn "未知 apt-repo 条目: $name" ;;
      esac
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
    script)
      case "$name" in
        zoxide) install_zoxide_script ;;
        *) warn "未知 script 条目: $name" ;;
      esac
      ;;
    github)
      case "$name" in
        yazi) install_yazi_github "$version" ;;
        lazygit) install_lazygit_github "$version" ;;
        *) warn "未知 github 条目: $name" ;;
      esac
      ;;
    *)
      warn "不支持的 source: ${source}（${name}）"
      ;;
  esac
}

install_packages_from_list() {
  step "Part 2: 按 packages.ubuntu.list 安装常见软件"
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
  step "检查 packages.ubuntu.list 安装状态"
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
  PACKAGES_IGNORE_FILTERS=true
  install_package_entry "$name" "$version" "$source" "$kind" "$tags"
  PACKAGES_IGNORE_FILTERS=false
}

post_install_notes() {
  step "安装后注意事项"
  echo -e "  ${YELLOW}Docker${NC}: 如需非 root 运行 docker："
  echo -e "    sudo usermod -aG docker \$USER && 重新登录"
  echo -e ""
  echo -e "  ${YELLOW}Node.js${NC}: 全局包目录 ~/.npm-global"
  echo -e "    运行 ${BOLD}source ~/.bashrc${NC} 或重新登录使 PATH 生效"
  echo -e ""
  echo -e "  ${YELLOW}GitHub CLI${NC}: 登录：${BOLD}gh auth login${NC}"
  echo -e ""
  echo -e "  ${YELLOW}zoxide${NC}: 添加到 ~/.bashrc：eval \"\$(zoxide init bash)\""
  echo -e ""
  echo -e "  ${YELLOW}下一步${NC}："
  echo -e "    languages/python/setup.sh    # Python + AI 包"
  echo -e "    agents/claude/setup.sh       # Claude Code"
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
  PACKAGES_FILTER_KIND=""
  PACKAGES_FILTER_TAG=""
  PACKAGES_IGNORE_FILTERS=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)      usage; exit 0 ;;
      --info-only)    info_only=true ;;
      --check)        check_only=true ;;
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
      --dry-run)      DRY_RUN=true ;;
      --base-only)    base_only=true ;;
      --packages-only) packages_only=true ;;
      --skip-docker)  SKIP_DOCKER=true ;;
      --skip-git)     SKIP_GIT=true ;;
      --skip-node)    SKIP_NODE=true ;;
      --skip-cloc)    SKIP_CLOC=true ;;
      --skip-tools)   SKIP_TOOLS=true ;;
      *) error "未知参数: $1"; usage; exit 1 ;;
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
  echo -e "${BOLD}${CYAN}║   Ubuntu / Debian 初始化安装脚本     ║${NC}"
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

main "$@"
