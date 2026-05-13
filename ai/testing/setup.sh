#!/usr/bin/env bash
# AI 测试工具安装脚本
# 用途：安装各语言的 AI 辅助测试工具和测试框架

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

usage() {
  cat <<EOF

${BOLD}用法:${NC}
  $(basename "$0") [选项]

${BOLD}选项:${NC}
  -h, --help             显示此帮助
  --dry-run              预览，不实际安装
  --python-only          只安装 Python 测试工具
  --skip-coverage        跳过测试覆盖率工具
  --skip-go-tools        跳过 Go 测试工具
  --skip-rust-tools      跳过 Rust 测试工具

${BOLD}安装内容:${NC}
  Python:
    pytest               测试框架（行业标准）
    pytest-cov           代码覆盖率
    pytest-asyncio       异步测试支持
    pytest-mock          Mock 支持
    hypothesis           基于属性的测试（自动生成测试用例）

  Go:
    gotestsum            更好的 go test 输出格式
    gocover-cobertura    Go 覆盖率 Cobertura 格式转换

  Rust:
    cargo-nextest        更快的 cargo test 替代品

${BOLD}示例:${NC}
  $(basename "$0")
  $(basename "$0") --python-only
  $(basename "$0") --skip-coverage

EOF
}

install_python_test_tools() {
  step "Python 测试工具安装"

  local pip_cmd=""
  if is_installed uv; then
    pip_cmd="uv pip install --system"
  elif is_installed pip3; then
    pip_cmd="pip3 install"
  elif is_installed pip; then
    pip_cmd="pip install"
  else
    warn "未找到 pip/uv，跳过 Python 测试工具安装"
    warn "请先运行 lang/python/setup.sh"
    return 0
  fi

  local packages=(
    "pytest"
    "pytest-asyncio"
    "pytest-mock"
  )
  [[ "$SKIP_COVERAGE" != true ]] && packages+=("pytest-cov" "coverage")
  packages+=("hypothesis")

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] 将安装 Python 测试包："
    for pkg in "${packages[@]}"; do info "  - $pkg"; done
    return 0
  fi

  for pkg in "${packages[@]}"; do
    if $pip_cmd "$pkg" --quiet 2>/dev/null; then
      success "  $pkg 已安装"
    else
      warn "  $pkg 安装失败，可手动运行: pip install $pkg"
    fi
  done

  success "Python 测试工具安装完成"
  info "验证：python3 -m pytest --version"
}

install_go_test_tools() {
  step "Go 测试工具安装"

  export PATH="/usr/local/go/bin:${GOPATH:-$HOME/go}/bin:$PATH"

  if ! is_installed go; then
    warn "Go 未安装，跳过 Go 测试工具"
    info "请先运行 lang/go/setup.sh"
    return 0
  fi

  local tools=(
    "gotest.tools/gotestsum@latest:gotestsum（格式化测试输出）"
    "github.com/axw/gocov/gocov@latest:gocov（覆盖率分析）"
  )

  for entry in "${tools[@]}"; do
    local pkg="${entry%%:*}"
    local desc="${entry#*:}"
    local bin_name
    bin_name=$(basename "${pkg%%@*}")

    if [[ "$DRY_RUN" == true ]]; then
      info "[dry-run] 将安装 $desc"
      continue
    fi

    if is_installed "$bin_name"; then
      success "$desc 已安装"
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

install_rust_test_tools() {
  step "Rust 测试工具安装"

  export PATH="$HOME/.cargo/bin:$PATH"

  if ! is_installed cargo; then
    warn "Rust/Cargo 未安装，跳过 Rust 测试工具"
    info "请先运行 lang/rust/setup.sh"
    return 0
  fi

  if is_installed cargo-nextest; then
    success "cargo-nextest 已安装"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] 将安装 cargo-nextest"
    return 0
  fi

  info "安装 cargo-nextest（更快的 Rust 测试运行器）..."
  if cargo install cargo-nextest 2>/dev/null; then
    success "cargo-nextest 安装完成"
  else
    warn "cargo-nextest 安装失败，可手动运行: cargo install cargo-nextest"
  fi
}

print_testing_guide() {
  step "AI 辅助测试使用指南"
  echo -e ""
  echo -e "  ${BOLD}Python 测试${NC}："
  echo -e "    pytest                          # 运行所有测试"
  echo -e "    pytest -v                       # 详细输出"
  echo -e "    pytest --cov=src tests/         # 带覆盖率"
  echo -e "    pytest --cov=src --cov-report=html  # HTML 覆盖率报告"
  echo -e ""
  echo -e "    ${CYAN}# Hypothesis 示例（自动生成测试用例）${NC}"
  echo -e "    from hypothesis import given, strategies as st"
  echo -e "    @given(st.integers(), st.integers())"
  echo -e "    def test_add(a, b):"
  echo -e "        assert add(a, b) == a + b"
  echo -e ""
  echo -e "  ${BOLD}Go 测试${NC}："
  echo -e "    go test ./...                   # 运行所有测试"
  echo -e "    go test -v ./...                # 详细输出"
  echo -e "    go test -cover ./...            # 覆盖率"
  echo -e "    gotestsum                       # 格式化输出"
  echo -e ""
  echo -e "  ${BOLD}Rust 测试${NC}："
  echo -e "    cargo test                      # 运行测试"
  echo -e "    cargo nextest run               # 更快的测试（并行）"
  echo -e "    cargo nextest run --no-fail-fast  # 不在第一次失败时停止"
  echo -e ""
  echo -e "  ${BOLD}使用 Claude Code 生成测试${NC}："
  echo -e "    claude  # 然后说：\"为 src/utils.py 中的所有函数生成 pytest 测试\""
  echo -e ""
  echo -e "  ${BOLD}使用 Aider 生成测试${NC}："
  echo -e "    aider src/utils.py tests/test_utils.py"
  echo -e "    # 在 Aider 中输入：'为 utils.py 中每个函数生成全面的测试用例'"
  echo -e ""
}

main() {
  DRY_RUN=false
  PYTHON_ONLY=false
  SKIP_COVERAGE=false
  SKIP_GO_TOOLS=false
  SKIP_RUST_TOOLS=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)          usage; exit 0 ;;
      --dry-run)          DRY_RUN=true ;;
      --python-only)      PYTHON_ONLY=true ;;
      --skip-coverage)    SKIP_COVERAGE=true ;;
      --skip-go-tools)    SKIP_GO_TOOLS=true ;;
      --skip-rust-tools)  SKIP_RUST_TOOLS=true ;;
      *) error "未知参数: $1"; usage; exit 1 ;;
    esac
    shift
  done

  echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${CYAN}║   AI 测试工具安装                    ║${NC}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════╝${NC}"
  info "OS: $OS"
  [[ "$DRY_RUN" == true ]] && warn "DRY-RUN 模式，不实际安装"

  install_python_test_tools

  if [[ "$PYTHON_ONLY" != true ]]; then
    $SKIP_GO_TOOLS   || install_go_test_tools
    $SKIP_RUST_TOOLS || install_rust_test_tools
  fi

  print_testing_guide
  echo -e "\n${GREEN}${BOLD}✓ AI 测试工具安装完成！${NC}\n"
}

main "$@"
