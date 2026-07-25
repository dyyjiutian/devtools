#!/usr/bin/env bash
# Go 环境安装脚本
# 用途：安装 Go 运行时 + 开发工具链（gopls, dlv, air, staticcheck）

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

is_installed() { command -v "$1" &>/dev/null; }

GO_VERSION="${GO_VERSION:-1.23.4}"
OS="$(uname -s)"
ARCH="$(uname -m)"

usage() {
  cat <<EOF

${BOLD}用法:${NC}
  $(basename "$0") [选项]

${BOLD}选项:${NC}
  -h, --help              显示此帮助
  --dry-run               预览，不实际安装
  --skip-tools            跳过 Go 开发工具安装
  --go-version <version>  指定 Go 版本（默认: ${GO_VERSION}）

${BOLD}安装内容:${NC}
  Go ${GO_VERSION}          Go 语言运行时
  gopls                  Go 语言服务器（LSP）
  dlv                    Go 调试器（Delve）
  staticcheck            静态分析工具
  air                    热重载开发服务器

${BOLD}示例:${NC}
  $(basename "$0")
  $(basename "$0") --skip-tools
  $(basename "$0") --go-version 1.22.5

EOF
}

get_linux_arch() {
  case "$ARCH" in
    x86_64)  echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l)  echo "armv6l" ;;
    *)       echo "amd64" ;;
  esac
}

install_go() {
  step "Go ${GO_VERSION} 安装"

  if is_installed go; then
    local current_ver
    current_ver=$(go version | awk '{print $3}' | sed 's/go//')
    success "Go 已安装：go${current_ver}"
    info "如需升级，请指定 --go-version 并重新运行"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] 将安装 Go ${GO_VERSION}"
    return 0
  fi

  case "$OS" in
    Darwin)
      if ! is_installed brew; then
        error "需要 Homebrew，请先运行 os/macos/setup.sh"
        exit 1
      fi
      info "通过 Homebrew 安装 Go..."
      brew install go
      ;;
    Linux)
      local go_arch
      go_arch=$(get_linux_arch)
      local tarball="go${GO_VERSION}.linux-${go_arch}.tar.gz"
      local download_url="https://go.dev/dl/${tarball}"
      local tmp_dir
      tmp_dir=$(mktemp -d)

      info "下载 Go ${GO_VERSION} (${go_arch})..."
      curl -fsSL "$download_url" -o "${tmp_dir}/${tarball}"

      info "安装到 /usr/local/go..."
      sudo rm -rf /usr/local/go
      sudo tar -C /usr/local -xzf "${tmp_dir}/${tarball}"
      rm -rf "$tmp_dir"

      success "Go ${GO_VERSION} 安装完成"
      ;;
    *)
      error "不支持的操作系统: $OS"
      exit 1
      ;;
  esac
}

configure_go_env() {
  step "Go 环境变量配置"

  local rc_file=""
  if [[ -f "$HOME/.zshrc" ]]; then
    rc_file="$HOME/.zshrc"
  elif [[ -f "$HOME/.bashrc" ]]; then
    rc_file="$HOME/.bashrc"
  else
    rc_file="$HOME/.bashrc"
    touch "$rc_file"
  fi

  local marker='# Go env (added by devtools/languages/go/setup.sh)'
  if grep -qF "$marker" "$rc_file" 2>/dev/null; then
    info "Go 环境变量已在 $rc_file 中，跳过"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] 将配置 Go 环境变量到 $rc_file"
    return 0
  fi

  cat >> "$rc_file" <<'RCBLOCK'

# Go env (added by devtools/languages/go/setup.sh)
if [[ -d /usr/local/go/bin ]]; then
  export PATH="/usr/local/go/bin:$PATH"
fi
export GOPATH="$HOME/go"
export PATH="$GOPATH/bin:$PATH"
RCBLOCK

  # 立即生效（当前 shell）
  export PATH="/usr/local/go/bin:$PATH"
  export GOPATH="$HOME/go"
  export PATH="$GOPATH/bin:$PATH"

  success "Go 环境变量已写入 $rc_file"
}

install_go_tools() {
  step "Go 开发工具安装"

  # 确保 go 命令可用
  export PATH="/usr/local/go/bin:$PATH"
  export GOPATH="${GOPATH:-$HOME/go}"
  export PATH="$GOPATH/bin:$PATH"

  if ! is_installed go; then
    warn "go 命令未找到，跳过工具安装"
    return 0
  fi

  local tools=(
    "golang.org/x/tools/gopls@latest:gopls（Go LSP 语言服务器）"
    "github.com/go-delve/delve/cmd/dlv@latest:dlv（调试器）"
    "honnef.co/go/tools/cmd/staticcheck@latest:staticcheck（静态分析）"
    "github.com/air-verse/air@latest:air（热重载开发服务器）"
  )

  for entry in "${tools[@]}"; do
    local pkg="${entry%%:*}"
    local desc="${entry#*:}"
    local bin_name
    bin_name=$(basename "${pkg%%@*}")

    if is_installed "$bin_name"; then
      success "$desc 已安装，跳过"
      continue
    fi

    if [[ "$DRY_RUN" == true ]]; then
      info "[dry-run] 将安装 $desc"
      continue
    fi

    info "安装 $desc..."
    if go install "$pkg" 2>/dev/null; then
      success "$desc 安装完成"
    else
      warn "$desc 安装失败，可手动运行: go install $pkg"
    fi
  done
}

post_install_notes() {
  step "安装后说明"
  echo -e "  ${YELLOW}激活 Go 环境${NC}："
  echo -e "    source ~/.zshrc    # 或重开终端"
  echo -e ""
  echo -e "  ${YELLOW}验证安装${NC}："
  echo -e "    go version"
  echo -e "    gopls version"
  echo -e ""
  echo -e "  ${YELLOW}常用命令${NC}："
  echo -e "    go mod init <module>   # 初始化模块"
  echo -e "    go get <package>       # 添加依赖"
  echo -e "    go test ./...          # 运行测试"
  echo -e "    air                    # 热重载启动（需要 .air.toml）"
  echo -e ""
  echo -e "  ${YELLOW}IDE 集成${NC}："
  echo -e "    gopls 支持 VS Code（Go 扩展）、Neovim（Mason LSP）、Cursor"
  echo -e ""
}

main() {
  DRY_RUN=false
  SKIP_TOOLS=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)     usage; exit 0 ;;
      --dry-run)     DRY_RUN=true ;;
      --skip-tools)  SKIP_TOOLS=true ;;
      --go-version)
        [[ -z "${2:-}" ]] && { error "--go-version 需要值"; exit 1; }
        GO_VERSION="$2"; shift ;;
      *) error "未知参数: $1"; usage; exit 1 ;;
    esac
    shift
  done

  echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${CYAN}║   Go 环境安装                        ║${NC}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════╝${NC}"
  info "OS: $OS  ARCH: $ARCH  Go 目标版本: $GO_VERSION"
  [[ "$DRY_RUN" == true ]] && warn "DRY-RUN 模式，不实际安装"

  install_go
  configure_go_env
  $SKIP_TOOLS || install_go_tools

  post_install_notes
  echo -e "\n${GREEN}${BOLD}✓ Go 环境安装完成！${NC}\n"
}

main "$@"
