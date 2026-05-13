#!/usr/bin/env bash
# Aider 安装脚本
# 用途：安装 Aider AI coding 助手并生成配置模板

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
  -h, --help            显示此帮助
  --dry-run             预览，不实际安装
  --model <model>       默认模型（默认: claude-opus-4-6）
  --api-key <key>       Anthropic API Key（也可设置环境变量）
  --skip-config         跳过生成 ~/.aider.conf.yml 模板

${BOLD}说明:${NC}
  Aider 是基于 CLI 的 AI 结对编程工具，支持 Git 原生工作流。
  安装后在任意 Git 仓库中运行 'aider' 即可开始 AI 编码。

${BOLD}支持的模型:${NC}
  claude-opus-4-6       Anthropic Claude Opus（最强）
  claude-sonnet-4-6     Anthropic Claude Sonnet（平衡）
  gpt-4o                OpenAI GPT-4o
  ollama/mistral        本地 Ollama 模型

${BOLD}示例:${NC}
  $(basename "$0")
  $(basename "$0") --model claude-sonnet-4-6
  $(basename "$0") --api-key "sk-ant-..."

EOF
}

install_aider() {
  step "Aider 安装"

  if is_installed aider; then
    success "Aider 已安装：$(aider --version 2>/dev/null || echo 'unknown')"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] 将安装 aider-chat"
    return 0
  fi

  # 优先用 uv，其次 pipx，最后 pip
  if is_installed uv; then
    info "通过 uv 安装 aider-chat..."
    uv tool install aider-chat
  elif is_installed pipx; then
    info "通过 pipx 安装 aider-chat（隔离环境）..."
    pipx install aider-chat
  elif is_installed pip3; then
    info "通过 pip3 安装 aider-chat..."
    pip3 install aider-chat
  elif is_installed pip; then
    info "通过 pip 安装 aider-chat..."
    pip install aider-chat
  else
    error "未找到 pip、pipx 或 uv，请先运行 lang/python/setup.sh"
    exit 1
  fi

  # 刷新 PATH（uv tool 安装到 ~/.local/bin）
  export PATH="$HOME/.local/bin:$PATH"

  if is_installed aider; then
    success "Aider 安装完成：$(aider --version 2>/dev/null)"
  else
    warn "aider 安装后未在 PATH 中找到，请重启终端"
    warn "如使用 uv tool install，确保 ~/.local/bin 在 PATH 中"
  fi
}

generate_aider_config() {
  step "生成 Aider 配置模板"

  local config_file="$HOME/.aider.conf.yml"

  if [[ -f "$config_file" ]]; then
    local backup="${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
    warn "~/.aider.conf.yml 已存在，备份为 $backup"
    cp "$config_file" "$backup"
  fi

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] 将生成 $config_file"
    return 0
  fi

  cat > "$config_file" <<CONF
# Aider 配置文件
# 文档: https://aider.chat/docs/config/aider_conf.html

## 模型配置
model: ${AIDER_MODEL}

## 自动提交（推荐开启，每次 AI 修改自动 git commit）
auto-commits: true

## 提交信息前缀
commit-prompt: |
  写一个简洁的 git commit message，格式: <type>: <description>
  type 可以是: feat, fix, refactor, docs, test, chore

## 编辑器（aider 打开文件时使用）
# editor: vim

## 显示差异时使用的风格
# dark-mode: true

## API Keys（推荐用环境变量，不要写在配置文件中）
# api-key: sk-ant-...（不推荐写入文件，用 ANTHROPIC_API_KEY 环境变量）

## 支持的替代 API（如自建代理）
# api-base: https://your-proxy.com

## 本地 Ollama 模型示例（需先启动 ollama serve）
# model: ollama/mistral
# api-base: http://localhost:11434

## 使用 claude-sonnet-4-6 作为弱模型（用于简单任务，节省费用）
# weak-model: claude-sonnet-4-6
CONF

  success "配置模板已生成：$config_file"
  info "请设置 API Key 环境变量："
  info "  export ANTHROPIC_API_KEY='sk-ant-...'"
  info "  # 或添加到 ~/.zshrc / ~/.bashrc"
}

setup_api_key_hint() {
  step "API Key 配置"

  local rc_file=""
  if [[ -f "$HOME/.zshrc" ]]; then
    rc_file="$HOME/.zshrc"
  elif [[ -f "$HOME/.bashrc" ]]; then
    rc_file="$HOME/.bashrc"
  fi

  if [[ -n "${AIDER_API_KEY:-}" ]]; then
    if [[ "$DRY_RUN" != true ]] && [[ -n "$rc_file" ]]; then
      local marker='# ANTHROPIC_API_KEY (added by devtools/ai/coding/aider/setup.sh)'
      if ! grep -qF "ANTHROPIC_API_KEY" "$rc_file" 2>/dev/null; then
        cat >> "$rc_file" <<RCBLOCK

$marker
export ANTHROPIC_API_KEY="${AIDER_API_KEY}"
RCBLOCK
        success "API Key 已写入 $rc_file"
      else
        info "ANTHROPIC_API_KEY 已在 $rc_file 中，跳过"
      fi
    fi
  else
    warn "未提供 API Key，请手动设置："
    warn "  export ANTHROPIC_API_KEY='sk-ant-...'"
  fi
}

post_install_notes() {
  step "安装后说明"
  echo -e "  ${YELLOW}快速开始${NC}："
  echo -e "    cd your-project          # 进入 Git 仓库"
  echo -e "    export ANTHROPIC_API_KEY='sk-ant-...'  # 设置 Key"
  echo -e "    aider                    # 启动（自动选择文件模式）"
  echo -e "    aider src/main.py        # 指定文件"
  echo -e ""
  echo -e "  ${YELLOW}常用命令${NC}："
  echo -e "    aider --model claude-sonnet-4-6   # 指定模型"
  echo -e "    aider --model ollama/mistral       # 使用本地 Ollama"
  echo -e "    aider --no-auto-commits            # 不自动提交"
  echo -e "    aider --show-model-warnings        # 显示模型兼容性"
  echo -e ""
  echo -e "  ${YELLOW}配置文件${NC}: ~/.aider.conf.yml"
  echo -e "  ${YELLOW}文档${NC}: https://aider.chat"
  echo -e ""
}

main() {
  DRY_RUN=false
  SKIP_CONFIG=false
  AIDER_MODEL="claude-opus-4-6"
  AIDER_API_KEY=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)       usage; exit 0 ;;
      --dry-run)       DRY_RUN=true ;;
      --skip-config)   SKIP_CONFIG=true ;;
      --model)
        [[ -z "${2:-}" ]] && { error "--model 需要值"; exit 1; }
        AIDER_MODEL="$2"; shift ;;
      --api-key)
        [[ -z "${2:-}" ]] && { error "--api-key 需要值"; exit 1; }
        AIDER_API_KEY="$2"; shift ;;
      *) error "未知参数: $1"; usage; exit 1 ;;
    esac
    shift
  done

  echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${CYAN}║   Aider AI 编码助手安装              ║${NC}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════╝${NC}"
  info "OS: $OS  模型: $AIDER_MODEL"
  [[ "$DRY_RUN" == true ]] && warn "DRY-RUN 模式，不实际安装"

  install_aider
  $SKIP_CONFIG || generate_aider_config
  setup_api_key_hint

  post_install_notes
  echo -e "\n${GREEN}${BOLD}✓ Aider 安装完成！${NC}\n"
}

main "$@"
