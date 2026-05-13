#!/usr/bin/env bash
# Rust 环境安装脚本
# 用途：rustup + stable toolchain + cargo 开发工具

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

OS="$(uname -s)"
ARCH="$(uname -m)"

usage() {
  cat <<EOF

${BOLD}用法:${NC}
  $(basename "$0") [选项]

${BOLD}选项:${NC}
  -h, --help          显示此帮助
  --dry-run           预览，不实际安装
  --skip-cargo-tools  跳过额外 cargo 工具安装

${BOLD}安装内容:${NC}
  rustup          Rust 工具链管理器
  stable          stable 工具链（rustc + cargo + clippy + rustfmt）
  cargo-watch     文件变化时自动运行 cargo 命令
  cargo-audit     安全漏洞检查
  cargo-edit      cargo add/rm/upgrade 命令
  cargo-nextest   更快的测试运行器

${BOLD}示例:${NC}
  $(basename "$0")
  $(basename "$0") --skip-cargo-tools

EOF
}

install_rustup() {
  step "Rust / rustup 安装"

  if is_installed rustup; then
    success "rustup 已安装：$(rustup --version 2>/dev/null)"
    info "更新 stable 工具链..."
    if [[ "$DRY_RUN" != true ]]; then
      rustup update stable --no-self-update 2>/dev/null && success "stable 工具链已更新"
    fi
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] 将安装 rustup 和 Rust stable"
    return 0
  fi

  # 安装系统依赖
  case "$OS" in
    Linux)
      if is_installed apt-get; then
        sudo apt-get update -qq
        sudo apt-get install -y curl build-essential pkg-config libssl-dev
      elif is_installed dnf; then
        sudo dnf install -y curl gcc pkg-config openssl-devel
      elif is_installed yum; then
        sudo yum install -y curl gcc pkg-config openssl-devel
      fi
      ;;
    Darwin)
      # macOS 通过 Xcode CLT 已有编译工具
      ;;
  esac

  info "通过 rustup.rs 安装 Rust..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path

  # 加载 cargo 环境
  # shellcheck source=/dev/null
  [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

  if is_installed rustc; then
    success "Rust 安装完成：$(rustc --version)"
  else
    warn "rustc 未在 PATH 中找到，请重启终端后验证"
  fi
}

configure_cargo_env() {
  step "Cargo 环境变量配置"

  local rc_file=""
  if [[ -f "$HOME/.zshrc" ]]; then
    rc_file="$HOME/.zshrc"
  elif [[ -f "$HOME/.bashrc" ]]; then
    rc_file="$HOME/.bashrc"
  else
    rc_file="$HOME/.bashrc"
    touch "$rc_file"
  fi

  local marker='# Rust/Cargo env (added by devtools/lang/rust/setup.sh)'
  if grep -qF "$marker" "$rc_file" 2>/dev/null; then
    info "Cargo 环境变量已在 $rc_file 中，跳过"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] 将配置 Cargo 环境变量到 $rc_file"
    return 0
  fi

  cat >> "$rc_file" <<'RCBLOCK'

# Rust/Cargo env (added by devtools/lang/rust/setup.sh)
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
RCBLOCK

  success "Cargo 环境变量已写入 $rc_file"

  # 当前 shell 立即生效
  # shellcheck source=/dev/null
  [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
}

install_cargo_tools() {
  step "Cargo 开发工具安装"

  # 加载 cargo
  export PATH="$HOME/.cargo/bin:$PATH"

  if ! is_installed cargo; then
    warn "cargo 命令未找到，跳过工具安装"
    return 0
  fi

  # 先安装 sccache 来加速后续编译（可选但很有用）
  local tools=(
    "cargo-watch:cargo-watch（文件监听自动重编）"
    "cargo-audit:cargo-audit（安全漏洞检查）"
    "cargo-edit:cargo-edit（add/rm/upgrade 命令）"
    "cargo-nextest:cargo-nextest（快速测试运行器）"
  )

  for entry in "${tools[@]}"; do
    local pkg="${entry%%:*}"
    local desc="${entry#*:}"

    if is_installed "$pkg"; then
      success "$desc 已安装，跳过"
      continue
    fi

    if [[ "$DRY_RUN" == true ]]; then
      info "[dry-run] 将安装 $desc"
      continue
    fi

    info "安装 $desc..."
    if cargo install "$pkg" 2>/dev/null; then
      success "$desc 安装完成"
    else
      warn "$desc 安装失败，可手动运行: cargo install $pkg"
    fi
  done
}

install_rust_analyzer() {
  step "rust-analyzer 安装（LSP）"

  if is_installed rust-analyzer; then
    success "rust-analyzer 已安装"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] 将安装 rust-analyzer"
    return 0
  fi

  # rustup 可以直接安装 rust-analyzer
  export PATH="$HOME/.cargo/bin:$PATH"
  if is_installed rustup; then
    info "通过 rustup 安装 rust-analyzer..."
    rustup component add rust-analyzer 2>/dev/null && \
      success "rust-analyzer 安装完成" || \
      warn "rust-analyzer 安装失败，VS Code Rust 扩展会自动管理"
  fi
}

post_install_notes() {
  step "安装后说明"
  echo -e "  ${YELLOW}激活 Cargo 环境${NC}："
  echo -e "    source ~/.zshrc    # 或重开终端"
  echo -e "    source \$HOME/.cargo/env"
  echo -e ""
  echo -e "  ${YELLOW}验证安装${NC}："
  echo -e "    rustc --version"
  echo -e "    cargo --version"
  echo -e "    rustup show"
  echo -e ""
  echo -e "  ${YELLOW}常用命令${NC}："
  echo -e "    cargo new myproject        # 新建项目"
  echo -e "    cargo build --release      # 编译发布版"
  echo -e "    cargo test                 # 运行测试"
  echo -e "    cargo nextest run          # 用 nextest 运行测试（更快）"
  echo -e "    cargo watch -x run         # 热重载"
  echo -e "    cargo audit                # 安全审计"
  echo -e ""
  echo -e "  ${YELLOW}工具链管理${NC}："
  echo -e "    rustup toolchain list      # 查看已安装工具链"
  echo -e "    rustup update              # 更新所有工具链"
  echo -e "    rustup target add <target> # 添加交叉编译目标"
  echo -e ""
}

main() {
  DRY_RUN=false
  SKIP_CARGO_TOOLS=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)           usage; exit 0 ;;
      --dry-run)           DRY_RUN=true ;;
      --skip-cargo-tools)  SKIP_CARGO_TOOLS=true ;;
      *) error "未知参数: $1"; usage; exit 1 ;;
    esac
    shift
  done

  echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${CYAN}║   Rust 环境安装                      ║${NC}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════╝${NC}"
  info "OS: $OS  ARCH: $ARCH"
  [[ "$DRY_RUN" == true ]] && warn "DRY-RUN 模式，不实际安装"

  install_rustup
  configure_cargo_env
  install_rust_analyzer
  $SKIP_CARGO_TOOLS || install_cargo_tools

  post_install_notes
  echo -e "\n${GREEN}${BOLD}✓ Rust 环境安装完成！${NC}\n"
}

main "$@"
