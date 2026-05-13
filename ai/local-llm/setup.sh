#!/usr/bin/env bash
# Ollama 本地 LLM 安装脚本
# 用途：安装 Ollama 运行时并管理本地大模型

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
  -h, --help              显示此帮助
  --dry-run               预览，不实际安装
  --pull-model <model>    安装后拉取指定模型（默认: mistral）
  --skip-model-pull       跳过模型拉取
  --with-webui            同时部署 Open WebUI（需要 Docker）
  --list-models           显示推荐模型列表并退出

${BOLD}安装内容:${NC}
  Ollama         本地 LLM 推理引擎（REST API 在 11434 端口）

${BOLD}推荐模型（供参考）:${NC}
  mistral        7B 通用模型，速度快（4GB RAM）
  codellama      代码专项模型（4GB RAM）
  llama3         Meta Llama 3（5GB RAM）
  qwen2.5-coder  阿里 Qwen 代码模型（4GB RAM）
  deepseek-coder 代码专项，支持中文（4GB RAM）

${BOLD}示例:${NC}
  $(basename "$0")
  $(basename "$0") --pull-model codellama
  $(basename "$0") --skip-model-pull
  $(basename "$0") --with-webui

EOF
}

list_recommended_models() {
  echo -e "\n${BOLD}推荐本地模型（按用途分类）：${NC}"
  echo -e ""
  echo -e "  ${CYAN}AI 编码：${NC}"
  echo -e "    codellama          Meta Code Llama 7B（通用代码）"
  echo -e "    qwen2.5-coder      Qwen 2.5 Coder 7B（支持中文，代码强）"
  echo -e "    deepseek-coder     DeepSeek Coder 7B"
  echo -e ""
  echo -e "  ${CYAN}通用对话：${NC}"
  echo -e "    mistral            Mistral 7B（均衡，推荐入门）"
  echo -e "    llama3             Meta Llama 3 8B"
  echo -e "    qwen2.5            Qwen 2.5 7B（中文友好）"
  echo -e ""
  echo -e "  ${CYAN}小内存机器（< 8GB RAM）：${NC}"
  echo -e "    phi3               Microsoft Phi-3 mini（3.8B）"
  echo -e "    gemma2:2b          Google Gemma 2 2B"
  echo -e ""
  echo -e "  安装命令：ollama pull <model-name>"
  echo -e ""
}

install_ollama() {
  step "Ollama 安装"

  if is_installed ollama; then
    success "Ollama 已安装：$(ollama --version 2>/dev/null || echo 'unknown')"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] 将安装 Ollama"
    return 0
  fi

  case "$OS" in
    Darwin)
      if ! is_installed brew; then
        error "需要 Homebrew，请先运行 os/macos/setup.sh"
        exit 1
      fi
      info "通过 Homebrew 安装 Ollama..."
      brew install ollama
      ;;
    Linux)
      info "通过官方安装脚本安装 Ollama..."
      curl -fsSL https://ollama.ai/install.sh | sh
      ;;
    *)
      error "不支持的操作系统: $OS"
      exit 1
      ;;
  esac

  if is_installed ollama; then
    success "Ollama 安装完成：$(ollama --version 2>/dev/null)"
  else
    error "Ollama 安装失败"
    exit 1
  fi
}

setup_ollama_service() {
  step "Ollama 服务配置"

  case "$OS" in
    Linux)
      if is_installed systemctl && systemctl list-unit-files ollama.service &>/dev/null; then
        if [[ "$DRY_RUN" != true ]]; then
          sudo systemctl enable ollama
          sudo systemctl start ollama
          success "Ollama systemd 服务已启动"
        else
          info "[dry-run] 将启动 Ollama systemd 服务"
        fi
      else
        warn "未检测到 systemd，请手动启动：ollama serve"
      fi
      ;;
    Darwin)
      info "macOS 上 Ollama 通过菜单栏应用运行，或手动执行 ollama serve"
      ;;
  esac
}

pull_model() {
  local model_name="$1"
  step "拉取模型：$model_name"

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] 将拉取模型 $model_name"
    return 0
  fi

  # 确保 ollama 服务运行
  if ! ollama list &>/dev/null; then
    info "启动 Ollama 服务..."
    ollama serve &>/dev/null &
    sleep 3
  fi

  # 检查是否已拉取
  if ollama list 2>/dev/null | grep -q "^${model_name}"; then
    success "模型 $model_name 已存在"
    return 0
  fi

  info "拉取模型 $model_name（首次下载需要时间，取决于网速和模型大小）..."
  if ollama pull "$model_name"; then
    success "模型 $model_name 拉取完成"
  else
    warn "模型 $model_name 拉取失败，可稍后手动运行: ollama pull $model_name"
  fi
}

deploy_open_webui() {
  step "Open WebUI 部署（Ollama Web 界面）"

  if ! is_installed docker; then
    error "需要 Docker，请先安装 Docker"
    return 1
  fi

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] 将部署 Open WebUI"
    return 0
  fi

  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^open-webui$'; then
    success "Open WebUI 已在运行"
    info "访问: http://localhost:3000"
    return 0
  fi

  info "启动 Open WebUI 容器..."
  docker run -d \
    -p 3000:8080 \
    --add-host=host.docker.internal:host-gateway \
    -v open-webui:/app/backend/data \
    --name open-webui \
    --restart always \
    ghcr.io/open-webui/open-webui:main

  success "Open WebUI 已启动"
  info "访问: http://localhost:3000"
  info "首次访问需要创建管理员账号"
}

post_install_notes() {
  step "安装后说明"
  echo -e "  ${YELLOW}启动 Ollama 服务${NC}："
  echo -e "    ollama serve                   # 前台运行"
  echo -e "    # 或在 macOS 上从菜单栏启动 Ollama 应用"
  echo -e ""
  echo -e "  ${YELLOW}模型管理${NC}："
  echo -e "    ollama list                    # 查看已安装模型"
  echo -e "    ollama pull mistral            # 下载模型"
  echo -e "    ollama run mistral             # 交互式对话"
  echo -e "    ollama rm mistral              # 删除模型"
  echo -e ""
  echo -e "  ${YELLOW}API 接口${NC}（兼容 OpenAI 格式）："
  echo -e "    curl http://localhost:11434/api/generate \\"
  echo -e "      -d '{\"model\": \"mistral\", \"prompt\": \"Hello\", \"stream\": false}'"
  echo -e ""
  echo -e "  ${YELLOW}与 Aider 集成${NC}："
  echo -e "    aider --model ollama/mistral"
  echo -e ""
  echo -e "  ${YELLOW}Python 调用示例${NC}："
  echo -e "    import ollama"
  echo -e "    response = ollama.chat(model='mistral', messages=[...])"
  echo -e ""
  echo -e "  ${YELLOW}环境变量${NC}："
  echo -e "    OLLAMA_HOST=0.0.0.0:11434     # 允许远程访问"
  echo -e "    OLLAMA_MODELS=/data/ollama    # 自定义模型存储路径"
  echo -e ""
}

main() {
  DRY_RUN=false
  PULL_MODEL="mistral"
  SKIP_MODEL_PULL=false
  WITH_WEBUI=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)           usage; exit 0 ;;
      --dry-run)           DRY_RUN=true ;;
      --skip-model-pull)   SKIP_MODEL_PULL=true ;;
      --with-webui)        WITH_WEBUI=true ;;
      --list-models)       list_recommended_models; exit 0 ;;
      --pull-model)
        [[ -z "${2:-}" ]] && { error "--pull-model 需要值"; exit 1; }
        PULL_MODEL="$2"; shift ;;
      *) error "未知参数: $1"; usage; exit 1 ;;
    esac
    shift
  done

  echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${CYAN}║   Ollama 本地 LLM 安装               ║${NC}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════╝${NC}"
  info "OS: $OS  ARCH: $ARCH"
  [[ "$DRY_RUN" == true ]] && warn "DRY-RUN 模式，不实际安装"

  install_ollama
  setup_ollama_service
  $SKIP_MODEL_PULL || pull_model "$PULL_MODEL"
  $WITH_WEBUI      && deploy_open_webui

  post_install_notes
  echo -e "\n${GREEN}${BOLD}✓ Ollama 本地 LLM 安装完成！${NC}\n"
}

main "$@"
