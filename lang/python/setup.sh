#!/usr/bin/env bash
# Python 环境安装脚本
# 用途：pyenv 版本管理 + uv 包管理 + AI 开发包

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

PYTHON_VERSION="${PYTHON_VERSION:-3.12.3}"
OS="$(uname -s)"
ARCH="$(uname -m)"

usage() {
  cat <<EOF

${BOLD}用法:${NC}
  $(basename "$0") [选项]

${BOLD}选项:${NC}
  -h, --help                   显示此帮助
  --dry-run                    预览，不实际安装
  --skip-pyenv                 跳过 pyenv 安装
  --skip-uv                    跳过 uv 安装
  --skip-ai-packages           跳过 AI 开发包安装
  --python-version <version>   指定 Python 版本（默认: ${PYTHON_VERSION}）

${BOLD}安装内容:${NC}
  pyenv          Python 版本管理器
  Python ${PYTHON_VERSION}   通过 pyenv 安装
  uv             现代 Python 包管理器（pip 替代品）
  AI 开发包:
    anthropic openai langchain langchain-core
    transformers torch
    jupyterlab jupyter-ai
    pytest pytest-asyncio pytest-cov

${BOLD}示例:${NC}
  $(basename "$0")
  $(basename "$0") --skip-ai-packages
  $(basename "$0") --python-version 3.11.9

EOF
}

install_pyenv() {
  step "pyenv 安装"

  if is_installed pyenv; then
    success "pyenv 已安装：$(pyenv --version)"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] 将安装 pyenv"
    return 0
  fi

  case "$OS" in
    Darwin)
      if ! is_installed brew; then
        error "需要 Homebrew，请先运行 os/macos/setup.sh"
        exit 1
      fi
      info "通过 Homebrew 安装 pyenv..."
      brew install pyenv
      ;;
    Linux)
      info "安装 pyenv 依赖..."
      if is_installed apt-get; then
        sudo apt-get update -qq
        sudo apt-get install -y make build-essential libssl-dev zlib1g-dev \
          libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm \
          libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev \
          libffi-dev liblzma-dev git
      elif is_installed dnf; then
        sudo dnf install -y make gcc zlib-devel bzip2 bzip2-devel \
          readline-devel sqlite sqlite-devel openssl-devel tk-devel \
          libffi-devel xz-devel git
      elif is_installed yum; then
        sudo yum install -y make gcc zlib-devel bzip2 bzip2-devel \
          readline-devel sqlite sqlite-devel openssl-devel tk-devel \
          libffi-devel xz-devel git
      fi
      info "通过官方脚本安装 pyenv..."
      curl https://pyenv.run | bash
      ;;
    *)
      error "不支持的操作系统: $OS"
      exit 1
      ;;
  esac

  success "pyenv 安装完成"
}

configure_pyenv_shell() {
  local rc_file=""

  if [[ -n "${ZSH_VERSION:-}" ]] || [[ -f "$HOME/.zshrc" ]]; then
    rc_file="$HOME/.zshrc"
  elif [[ -f "$HOME/.bashrc" ]]; then
    rc_file="$HOME/.bashrc"
  elif [[ -f "$HOME/.bash_profile" ]]; then
    rc_file="$HOME/.bash_profile"
  else
    rc_file="$HOME/.bashrc"
  fi

  local marker='# pyenv init (added by devtools/lang/python/setup.sh)'
  if grep -qF "$marker" "$rc_file" 2>/dev/null; then
    info "pyenv 初始化已在 $rc_file 中，跳过"
    return 0
  fi

  info "将 pyenv 初始化写入 $rc_file..."
  cat >> "$rc_file" <<'RCBLOCK'

# pyenv init (added by devtools/lang/python/setup.sh)
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
if command -v pyenv &>/dev/null; then
  eval "$(pyenv init -)"
fi
RCBLOCK

  success "pyenv 初始化已写入 $rc_file"
}

install_python() {
  step "Python ${PYTHON_VERSION} 安装"

  # 加载 pyenv（当前 shell）
  export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
  export PATH="$PYENV_ROOT/bin:$PATH"
  if is_installed pyenv; then
    eval "$(pyenv init -)" 2>/dev/null || true
  fi

  if ! is_installed pyenv; then
    warn "pyenv 未找到，跳过 Python 安装"
    return 0
  fi

  if pyenv versions --bare 2>/dev/null | grep -q "^${PYTHON_VERSION}$"; then
    success "Python ${PYTHON_VERSION} 已安装"
  else
    if [[ "$DRY_RUN" == true ]]; then
      info "[dry-run] 将安装 Python ${PYTHON_VERSION}"
    else
      info "正在安装 Python ${PYTHON_VERSION}（首次安装需要编译，约 5-15 分钟）..."
      pyenv install "$PYTHON_VERSION"
      success "Python ${PYTHON_VERSION} 安装完成"
    fi
  fi

  local current
  current=$(pyenv global 2>/dev/null || echo "system")
  if [[ "$current" == "system" ]] || [[ "$current" == "" ]]; then
    if [[ "$DRY_RUN" != true ]]; then
      pyenv global "$PYTHON_VERSION"
      success "已设置全局 Python 版本为 ${PYTHON_VERSION}"
    fi
  else
    info "当前全局 Python：$current（保持不变）"
  fi
}

install_uv() {
  step "uv 包管理器安装"

  if is_installed uv; then
    success "uv 已安装：$(uv --version)"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] 将安装 uv"
    return 0
  fi

  case "$OS" in
    Darwin)
      if is_installed brew; then
        brew install uv
      else
        curl -LsSf https://astral.sh/uv/install.sh | sh
      fi
      ;;
    Linux)
      curl -LsSf https://astral.sh/uv/install.sh | sh
      ;;
  esac

  # 刷新 PATH
  export PATH="$HOME/.local/bin:$PATH"
  export PATH="$HOME/.cargo/bin:$PATH"

  if is_installed uv; then
    success "uv 安装完成：$(uv --version)"
  else
    warn "uv 安装后未找到，请重启终端或 source ~/.zshrc"
  fi
}

install_ai_packages() {
  step "AI 开发包安装"

  # 优先用 uv，其次 pip
  local installer=""
  if is_installed uv; then
    installer="uv pip install --system"
  elif is_installed pip3; then
    installer="pip3 install"
  elif is_installed pip; then
    installer="pip install"
  else
    warn "未找到 pip 或 uv，跳过 AI 包安装"
    return 0
  fi

  local packages=(
    "anthropic"
    "openai"
    "langchain"
    "langchain-core"
    "langchain-community"
    "transformers"
    "jupyterlab"
    "jupyter-ai"
    "pytest"
    "pytest-asyncio"
    "pytest-cov"
  )

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] 将安装以下 AI 包："
    for pkg in "${packages[@]}"; do info "  - $pkg"; done
    return 0
  fi

  info "正在安装 AI 开发包..."
  for pkg in "${packages[@]}"; do
    info "  安装 $pkg..."
    if $installer "$pkg" --quiet 2>/dev/null; then
      success "  $pkg 安装完成"
    else
      warn "  $pkg 安装失败，可手动运行: pip install $pkg"
    fi
  done

  success "AI 开发包安装完成"
}

post_install_notes() {
  step "安装后说明"
  echo -e "  ${YELLOW}激活 pyenv${NC}："
  echo -e "    source ~/.zshrc    # 或重开终端"
  echo -e ""
  echo -e "  ${YELLOW}常用 pyenv 命令${NC}："
  echo -e "    pyenv versions               # 查看已安装版本"
  echo -e "    pyenv install 3.12.3         # 安装指定版本"
  echo -e "    pyenv local 3.11.9           # 项目级版本（生成 .python-version）"
  echo -e "    pyenv global 3.12.3          # 全局版本"
  echo -e ""
  echo -e "  ${YELLOW}常用 uv 命令${NC}："
  echo -e "    uv venv                      # 创建虚拟环境"
  echo -e "    uv pip install <package>     # 安装包"
  echo -e "    uv pip install -r requirements.txt"
  echo -e ""
  echo -e "  ${YELLOW}启动 JupyterLab${NC}："
  echo -e "    jupyter lab"
  echo -e ""
  echo -e "  ${YELLOW}AI 包使用示例${NC}："
  echo -e "    python3 -c \"import anthropic; print('Anthropic SDK ready')\""
  echo -e "    python3 -c \"import langchain; print('LangChain ready')\""
  echo -e ""
}

main() {
  DRY_RUN=false
  SKIP_PYENV=false
  SKIP_UV=false
  SKIP_AI_PACKAGES=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)        usage; exit 0 ;;
      --dry-run)        DRY_RUN=true ;;
      --skip-pyenv)     SKIP_PYENV=true ;;
      --skip-uv)        SKIP_UV=true ;;
      --skip-ai-packages) SKIP_AI_PACKAGES=true ;;
      --python-version)
        [[ -z "${2:-}" ]] && { error "--python-version 需要值"; exit 1; }
        PYTHON_VERSION="$2"; shift ;;
      *) error "未知参数: $1"; usage; exit 1 ;;
    esac
    shift
  done

  echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${CYAN}║   Python 环境安装                    ║${NC}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════╝${NC}"
  info "OS: $OS  ARCH: $ARCH  Python 目标版本: $PYTHON_VERSION"
  [[ "$DRY_RUN" == true ]] && warn "DRY-RUN 模式，不实际安装"

  $SKIP_PYENV || install_pyenv
  $SKIP_PYENV || configure_pyenv_shell
  $SKIP_PYENV || install_python
  $SKIP_UV    || install_uv
  $SKIP_AI_PACKAGES || install_ai_packages

  post_install_notes
  echo -e "\n${GREEN}${BOLD}✓ Python 环境安装完成！${NC}\n"
}

main "$@"
