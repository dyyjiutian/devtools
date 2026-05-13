#!/usr/bin/env bash
# VS Code 安装脚本
# 用途：安装 VS Code + AI 扩展 + 多语言开发扩展

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
  -h, --help                  显示此帮助
  --dry-run                   预览，不实际安装
  --skip-vscode               跳过 VS Code 安装（只安装扩展）
  --skip-ai-extensions        跳过 AI 扩展
  --skip-lang-extensions      跳过语言扩展
  --backup                    备份当前扩展列表到 extensions.txt

${BOLD}安装内容:${NC}
  VS Code        Microsoft Visual Studio Code

  AI 扩展:
    Continue.dev               开源 AI 编码助手（支持 Claude/Ollama）
    GitHub Copilot             GitHub AI 补全（需订阅）
    GitHub Copilot Chat        Copilot 对话功能

  语言扩展:
    Python（ms-python.python）
    Pylance（ms-python.vscode-pylance）
    Go（golang.Go）
    Extension Pack for Java    Java 开发完整包
    rust-analyzer              Rust LSP
    ESLint + Prettier          JS/TS 质量工具

  通用工具:
    GitLens                   Git 增强
    Docker                    容器化支持
    Remote - SSH              远程开发

${BOLD}示例:${NC}
  $(basename "$0")
  $(basename "$0") --skip-lang-extensions
  $(basename "$0") --backup

EOF
}

install_vscode() {
  step "VS Code 安装"

  if is_installed code; then
    success "VS Code 已安装：$(code --version | head -1)"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] 将安装 VS Code"
    return 0
  fi

  case "$OS" in
    Darwin)
      if ! is_installed brew; then
        error "需要 Homebrew，请先运行 os/macos/setup.sh"
        exit 1
      fi
      info "通过 Homebrew 安装 VS Code..."
      brew install --cask visual-studio-code
      ;;
    Linux)
      if is_installed snap; then
        info "通过 snap 安装 VS Code..."
        sudo snap install code --classic
      elif is_installed apt-get; then
        info "通过 apt 安装 VS Code..."
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/microsoft.gpg
        sudo install -o root -g root -m 644 /tmp/microsoft.gpg /etc/apt/keyrings/microsoft.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | \
          sudo tee /etc/apt/sources.list.d/vscode.list
        sudo apt-get update -qq
        sudo apt-get install -y code
        rm -f /tmp/microsoft.gpg
      elif is_installed dnf || is_installed yum; then
        info "通过 rpm 安装 VS Code..."
        sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
        sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
        if is_installed dnf; then
          sudo dnf install -y code
        else
          sudo yum install -y code
        fi
      else
        error "无法自动安装 VS Code，请从 https://code.visualstudio.com 手动下载"
        exit 1
      fi
      ;;
    *)
      error "不支持的操作系统: $OS"
      exit 1
      ;;
  esac

  if is_installed code; then
    success "VS Code 安装完成：$(code --version | head -1)"
  else
    warn "VS Code 安装后未找到 code 命令，请重启终端或手动将 code 加入 PATH"
  fi
}

install_extension() {
  local ext_id="$1"
  local desc="${2:-$ext_id}"

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] 将安装扩展 $desc"
    return 0
  fi

  if ! is_installed code; then
    warn "code 命令未找到，跳过扩展安装"
    return 0
  fi

  if code --list-extensions 2>/dev/null | grep -qi "^${ext_id}$"; then
    success "$desc 已安装"
    return 0
  fi

  info "安装 $desc..."
  if code --install-extension "$ext_id" --force 2>/dev/null; then
    success "$desc 安装完成"
  else
    warn "$desc 安装失败，可在 VS Code 扩展市场搜索安装：$ext_id"
  fi
}

install_ai_extensions() {
  step "AI 扩展安装"

  install_extension "Continue.continue"           "Continue.dev（AI 编码助手，支持 Claude/Ollama）"
  install_extension "GitHub.copilot"              "GitHub Copilot（AI 补全）"
  install_extension "GitHub.copilot-chat"         "GitHub Copilot Chat"
}

install_lang_extensions() {
  step "语言扩展安装"

  # Python
  install_extension "ms-python.python"            "Python"
  install_extension "ms-python.vscode-pylance"    "Pylance（Python 类型检查）"
  install_extension "ms-python.black-formatter"   "Black（Python 格式化）"

  # Go
  install_extension "golang.Go"                   "Go"

  # Java
  install_extension "vscjava.vscode-java-pack"    "Extension Pack for Java"

  # Rust
  install_extension "rust-lang.rust-analyzer"     "rust-analyzer"

  # JavaScript / TypeScript
  install_extension "dbaeumer.vscode-eslint"      "ESLint"
  install_extension "esbenp.prettier-vscode"      "Prettier"
}

install_utility_extensions() {
  step "通用工具扩展安装"

  install_extension "eamodio.gitlens"             "GitLens"
  install_extension "ms-azuretools.vscode-docker" "Docker"
  install_extension "ms-vscode-remote.remote-ssh" "Remote - SSH"
  install_extension "EditorConfig.EditorConfig"   "EditorConfig"
}

backup_extensions() {
  step "备份扩展列表"

  if ! is_installed code; then
    warn "code 命令未找到，无法备份"
    return 0
  fi

  local backup_dir
  backup_dir="$(dirname "${BASH_SOURCE[0]}")/config"
  mkdir -p "$backup_dir"

  local backup_file="$backup_dir/extensions.txt"
  code --list-extensions > "$backup_file"
  success "扩展列表已保存到 $backup_file（$(wc -l < "$backup_file") 个扩展）"
}

post_install_notes() {
  step "安装后说明"
  echo -e "  ${YELLOW}Continue.dev 配置${NC}（连接本地 Ollama）："
  echo -e "    1. 打开 VS Code，点击左侧 Continue 图标"
  echo -e "    2. 选择 Add Model → Ollama → 选择已安装的模型"
  echo -e "    3. 或编辑 ~/.continue/config.json 手动配置"
  echo -e ""
  echo -e "  ${YELLOW}Continue.dev 配置 Claude${NC}："
  echo -e "    在 config.json 中添加："
  echo -e "    {"
  echo -e "      \"models\": [{"
  echo -e "        \"title\": \"Claude Sonnet\","
  echo -e "        \"provider\": \"anthropic\","
  echo -e "        \"model\": \"claude-sonnet-4-6\","
  echo -e "        \"apiKey\": \"sk-ant-...\""
  echo -e "      }]"
  echo -e "    }"
  echo -e ""
  echo -e "  ${YELLOW}GitHub Copilot${NC}："
  echo -e "    登录：VS Code → Accounts → Sign in with GitHub"
  echo -e "    需要 GitHub Copilot 订阅（\$10/月 或学生免费）"
  echo -e ""
}

main() {
  DRY_RUN=false
  SKIP_VSCODE=false
  SKIP_AI_EXTENSIONS=false
  SKIP_LANG_EXTENSIONS=false
  DO_BACKUP=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)                  usage; exit 0 ;;
      --dry-run)                  DRY_RUN=true ;;
      --skip-vscode)              SKIP_VSCODE=true ;;
      --skip-ai-extensions)       SKIP_AI_EXTENSIONS=true ;;
      --skip-lang-extensions)     SKIP_LANG_EXTENSIONS=true ;;
      --backup)                   DO_BACKUP=true ;;
      *) error "未知参数: $1"; usage; exit 1 ;;
    esac
    shift
  done

  echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${CYAN}║   VS Code 安装                       ║${NC}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════╝${NC}"
  info "OS: $OS  ARCH: $ARCH"
  [[ "$DRY_RUN" == true ]] && warn "DRY-RUN 模式，不实际安装"

  if [[ "$DO_BACKUP" == true ]]; then
    backup_extensions
    exit 0
  fi

  $SKIP_VSCODE            || install_vscode
  $SKIP_AI_EXTENSIONS     || install_ai_extensions
  $SKIP_LANG_EXTENSIONS   || install_lang_extensions
  install_utility_extensions

  post_install_notes
  echo -e "\n${GREEN}${BOLD}✓ VS Code 安装完成！${NC}\n"
}

main "$@"
