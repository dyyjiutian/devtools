#!/usr/bin/env bash
# AI 编码工具安装脚本（编排器）
# 用途：一键安装 Claude Code + Aider

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OS="$(uname -s)"

usage() {
  cat <<EOF

${BOLD}用法:${NC}
  $(basename "$0") [选项]

${BOLD}选项:${NC}
  -h, --help          显示此帮助
  --dry-run           预览，不实际安装
  --skip-claude       跳过 Claude Code 安装
  --skip-aider        跳过 Aider 安装
  --api-key <key>     设置 Anthropic API Key
  --model <model>     Aider 默认模型（默认: claude-opus-4-6）

${BOLD}安装内容:${NC}
  Claude Code    Anthropic 官方 CLI AI 助手（通过 npm）
  Aider          开源 CLI AI 结对编程工具（通过 pip/uv）

${BOLD}示例:${NC}
  $(basename "$0")
  $(basename "$0") --skip-aider
  $(basename "$0") --api-key "sk-ant-..."

EOF
}

run_subscript() {
  local script="$1"
  shift
  if [[ -f "$script" ]]; then
    bash "$script" "$@"
  else
    warn "脚本不存在：$script"
  fi
}

install_claude_code() {
  step "Claude Code 安装"

  if is_installed claude; then
    success "Claude Code 已安装：$(claude --version 2>/dev/null || echo 'unknown')"
    return 0
  fi

  local claude_script="$REPO_ROOT/agent/claude/setup.sh"
  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] 将运行 $claude_script install"
    return 0
  fi

  if [[ -f "$claude_script" ]]; then
    run_subscript "$claude_script" install
  else
    # 内联安装（如果子脚本不存在）
    if ! is_installed node; then
      error "需要 Node.js，请先运行 lang/nodejs/setup.sh 或 os/ 对应脚本"
      return 1
    fi
    info "通过 npm 安装 Claude Code..."
    npm install -g @anthropic-ai/claude-code
    success "Claude Code 安装完成"
  fi

  # 配置 API Key（如果提供）
  if [[ -n "${API_KEY:-}" ]]; then
    if [[ -f "$claude_script" ]]; then
      run_subscript "$claude_script" configure --api-key "$API_KEY"
    fi
  fi
}

install_aider() {
  local aider_script="$SCRIPT_DIR/aider/setup.sh"
  local args=()
  [[ "$DRY_RUN" == true ]] && args+=("--dry-run")
  [[ -n "${AIDER_MODEL:-}" ]] && args+=("--model" "$AIDER_MODEL")
  [[ -n "${API_KEY:-}" ]] && args+=("--api-key" "$API_KEY")

  run_subscript "$aider_script" "${args[@]}"
}

print_summary() {
  step "安装摘要"
  echo -e "  ${BOLD}已安装的 AI 编码工具：${NC}"
  echo -e ""

  if is_installed claude; then
    echo -e "  ${GREEN}✓${NC} Claude Code  $(claude --version 2>/dev/null || echo '')"
    echo -e "      命令: claude"
    echo -e "      文档: https://claude.ai/code"
  else
    echo -e "  ${YELLOW}✗${NC} Claude Code  （未安装或未在 PATH 中）"
  fi
  echo -e ""

  if is_installed aider; then
    echo -e "  ${GREEN}✓${NC} Aider  $(aider --version 2>/dev/null || echo '')"
    echo -e "      命令: aider"
    echo -e "      文档: https://aider.chat"
  else
    echo -e "  ${YELLOW}✗${NC} Aider  （未安装或未在 PATH 中）"
  fi
  echo -e ""
  echo -e "  ${YELLOW}提示${NC}: 如未设置 API Key，请配置 ANTHROPIC_API_KEY 环境变量"
  echo -e "    export ANTHROPIC_API_KEY='sk-ant-...'"
  echo -e ""
}

main() {
  DRY_RUN=false
  SKIP_CLAUDE=false
  SKIP_AIDER=false
  API_KEY=""
  AIDER_MODEL=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)      usage; exit 0 ;;
      --dry-run)      DRY_RUN=true ;;
      --skip-claude)  SKIP_CLAUDE=true ;;
      --skip-aider)   SKIP_AIDER=true ;;
      --api-key)
        [[ -z "${2:-}" ]] && { error "--api-key 需要值"; exit 1; }
        API_KEY="$2"; shift ;;
      --model)
        [[ -z "${2:-}" ]] && { error "--model 需要值"; exit 1; }
        AIDER_MODEL="$2"; shift ;;
      *) error "未知参数: $1"; usage; exit 1 ;;
    esac
    shift
  done

  echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${CYAN}║   AI 编码工具安装                    ║${NC}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════╝${NC}"
  info "OS: $OS"
  [[ "$DRY_RUN" == true ]] && warn "DRY-RUN 模式，不实际安装"

  $SKIP_CLAUDE || install_claude_code
  $SKIP_AIDER  || install_aider

  print_summary
  echo -e "\n${GREEN}${BOLD}✓ AI 编码工具安装完成！${NC}\n"
}

main "$@"
