#!/usr/bin/env bash
# Claude Code 安装与配置脚本
# 用途：安装、卸载和配置 Claude Code

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── 颜色定义 ────────────────────────────────────────────────────────────────
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

# ─── 工具函数 ────────────────────────────────────────────────────────────────
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()    { echo -e "\n${BOLD}${CYAN}▶ $*${NC}"; }

# ─── 配置路径检测 ────────────────────────────────────────────────────────────
detect_claude_config_dir() {
    case "$(uname -s)" in
        Darwin)      echo "$HOME/Library/Application Support/Claude" ;;
        Linux)       echo "$HOME/.config/claude" ;;
        CYGWIN*|MINGW*|MSYS*) echo "$APPDATA/Claude" ;;
        *)
            error "Unsupported OS: $(uname -s)"
            exit 1
            ;;
    esac
}

# ─── 用法说明 ────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF

${BOLD}用法:${NC}
  $(basename "$0") <command> [options]

${BOLD}命令:${NC}
  install     安装 Claude Code
  uninstall   卸载 Claude Code
  configure   配置 Claude Code 设置 (保存到 env 对象)

${BOLD}配置选项 (仅与 configure 命令一起使用):${NC}
  --api-key <key>         设置 Anthropic API key (ANTHROPIC_AUTH_TOKEN)
  --base-url <url>        设置 API base URL (ANTHROPIC_BASE_URL)
  --model <model>         设置默认模型 (ANTHROPIC_MODEL)
  --fast-model <model>    设置 fast 模式模型 (ANTHROPIC_DEFAULT_HAIKU_MODEL)
  --opus-model <model>    设置 opus 模式模型 (ANTHROPIC_DEFAULT_OPUS_MODEL)

${BOLD}说明:${NC}
  所有配置会保存到 settings.json 的 env 对象中，例如:
  {
    "env": {
      "ANTHROPIC_AUTH_TOKEN": "sk-ant-...",
      "ANTHROPIC_BASE_URL": "https://api.anthropic.com",
      "ANTHROPIC_MODEL": "claude-sonnet-4-6",
      "ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-haiku-4-5-20251001",
      "ANTHROPIC_DEFAULT_OPUS_MODEL": "claude-opus-4-6"
    }
  }

${BOLD}示例:${NC}
  $(basename "$0") install
  $(basename "$0") uninstall
  $(basename "$0") configure                              # 交互式配置
  $(basename "$0") configure --api-key "sk-ant-..."
  $(basename "$0") configure --model "claude-sonnet-4-6" --fast-model "claude-haiku-4-5-20251001"

EOF
}

# ─── 安装 Claude Code ────────────────────────────────────────────────────────
cmd_install() {
    step "安装 Claude Code"

    # 检查是否已安装
    if command -v claude &>/dev/null; then
        warn "Claude Code 已安装: $(claude --version 2>/dev/null || echo 'unknown')"
        read -r -p "是否重新安装? [y/N] " answer
        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            info "跳过安装"
            return 0
        fi
    fi

    # 检查 Node.js
    if ! command -v node &>/dev/null; then
        error "需要 Node.js 16+。请先安装 Node.js"
        exit 1
    fi

    local node_version
    node_version=$(node --version | sed 's/v//')
    info "Node.js 版本: $node_version"

    # 安装 Claude Code
    info "正在安装 Claude Code..."
    npm install -g @anthropic-ai/claude-code

    if command -v claude &>/dev/null; then
        success "Claude Code 安装成功!"
        claude --version 2>/dev/null || true
    else
        error "安装失败，请检查错误信息"
        exit 1
    fi

    info "运行 'claude --help' 查看使用说明"
    info "运行 '$(basename "$0") configure' 进行配置"
}

# ─── 卸载 Claude Code ────────────────────────────────────────────────────────
cmd_uninstall() {
    step "卸载 Claude Code"

    if ! command -v claude &>/dev/null; then
        warn "Claude Code 未安装"
        return 0
    fi

    read -r -p "确定要卸载 Claude Code 吗? [y/N] " answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        info "取消卸载"
        return 0
    fi

    info "正在卸载 Claude Code..."
    npm uninstall -g @anthropic-ai/claude-code

    if ! command -v claude &>/dev/null; then
        success "Claude Code 已卸载"
    else
        error "卸载失败"
        exit 1
    fi
}

# ─── 保存 env 配置到 settings.json ────────────────────────────────────────────
save_env_settings() {
    local config_dir
    config_dir=$(detect_claude_config_dir)
    local settings_file="$config_dir/settings.json"

    mkdir -p "$config_dir"

    # 使用 Node.js 来合并和保存 JSON，将所有配置放到 env 对象中
    node -e "
        const fs = require('fs');
        const path = '$settings_file';
        let settings = {};
        if (fs.existsSync(path)) {
            try {
                settings = JSON.parse(fs.readFileSync(path, 'utf8'));
            } catch(e) {}
        }
        if (!settings.env) {
            settings.env = {};
        }
        const updates = $1;
        Object.assign(settings.env, updates);
        fs.writeFileSync(path, JSON.stringify(settings, null, 2) + '\n');
        console.log('Settings saved to:', path);
    "
}

# ─── 交互式配置 ───────────────────────────────────────────────────────────────
configure_interactive() {
    step "配置 Claude Code"

    local config_dir
    config_dir=$(detect_claude_config_dir)
    info "配置文件路径: $config_dir/settings.json"
    info "配置将保存到 env 对象中"

    echo ""
    echo "${BOLD}请按提示输入配置值 (直接回车跳过):${NC}"
    echo ""

    # API Key
    read -r -s -p "Anthropic API Key (ANTHROPIC_AUTH_TOKEN): " api_key
    echo ""

    # Base URL
    read -r -p "API Base URL (ANTHROPIC_BASE_URL) [默认: https://api.anthropic.com]: " base_url
    base_url=${base_url:-https://api.anthropic.com}

    # Default Model
    echo ""
    echo "${BOLD}可用模型 (ANTHROPIC_MODEL):${NC}"
    echo "  - claude-sonnet-4-6 (Claude Sonnet 4.6)"
    echo "  - claude-opus-4-6 (Claude Opus 4.6)"
    echo "  - claude-haiku-4-5-20251001 (Claude Haiku 4.5)"
    read -r -p "默认模型 [默认: claude-sonnet-4-6]: " model
    model=${model:-claude-sonnet-4-6}

    # Fast Model
    read -r -p "Fast 模式模型 (ANTHROPIC_DEFAULT_HAIKU_MODEL) [默认: claude-haiku-4-5-20251001]: " fast_model
    fast_model=${fast_model:-claude-haiku-4-5-20251001}

    # Opus Model
    read -r -p "Opus 模式模型 (ANTHROPIC_DEFAULT_OPUS_MODEL) [默认: claude-opus-4-6]: " opus_model
    opus_model=${opus_model:-claude-opus-4-6}

    # 构建 env 配置对象
    local env_config='{}'

    [[ -n "$api_key" ]] && env_config=$(node -e "console.log(JSON.stringify({...JSON.parse('$env_config'), ANTHROPIC_AUTH_TOKEN: '$api_key'}))")
    env_config=$(node -e "console.log(JSON.stringify({...JSON.parse('$env_config'), ANTHROPIC_BASE_URL: '$base_url'}))")
    env_config=$(node -e "console.log(JSON.stringify({...JSON.parse('$env_config'), ANTHROPIC_MODEL: '$model'}))")
    env_config=$(node -e "console.log(JSON.stringify({...JSON.parse('$env_config'), ANTHROPIC_DEFAULT_HAIKU_MODEL: '$fast_model'}))")
    env_config=$(node -e "console.log(JSON.stringify({...JSON.parse('$env_config'), ANTHROPIC_DEFAULT_OPUS_MODEL: '$opus_model'}))")

    # 构建完整配置用于预览
    local preview_config="{\"env\": $env_config}"

    echo ""
    step "配置预览"
    echo "$preview_config" | node -e "
        const data = require('fs').readFileSync(0, 'utf8');
        const obj = JSON.parse(data);
        console.log('{');
        console.log('  \"env\": {');
        const entries = Object.entries(obj.env);
        entries.forEach(([k, v], i) => {
            if (k === 'ANTHROPIC_AUTH_TOKEN' && typeof v === 'string' && v.length > 8) {
                v = v.substring(0, 8) + '...';
            }
            const comma = i < entries.length - 1 ? ',' : '';
            console.log('    \"' + k + '\": \"' + v + '\"' + comma);
        });
        console.log('  }');
        console.log('}');
    "

    echo ""
    read -r -p "保存配置? [Y/n] " answer
    if [[ ! "$answer" =~ ^[Nn]$ ]]; then
        save_env_settings "$env_config"
        success "配置已保存"
    else
        info "配置未保存"
    fi
}

# ─── 命令行配置 ───────────────────────────────────────────────────────────────
configure_cli() {
    step "配置 Claude Code"

    local env_config='{}'
    local has_config=false

    # 解析配置参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --api-key)
                [[ -z "${2:-}" ]] && { error "--api-key 需要一个值"; exit 1; }
                env_config=$(node -e "console.log(JSON.stringify({...JSON.parse('$env_config'), ANTHROPIC_AUTH_TOKEN: '$2'}))")
                has_config=true
                shift 2
                ;;
            --base-url)
                [[ -z "${2:-}" ]] && { error "--base-url 需要一个值"; exit 1; }
                env_config=$(node -e "console.log(JSON.stringify({...JSON.parse('$env_config'), ANTHROPIC_BASE_URL: '$2'}))")
                has_config=true
                shift 2
                ;;
            --model)
                [[ -z "${2:-}" ]] && { error "--model 需要一个值"; exit 1; }
                env_config=$(node -e "console.log(JSON.stringify({...JSON.parse('$env_config'), ANTHROPIC_MODEL: '$2'}))")
                has_config=true
                shift 2
                ;;
            --fast-model)
                [[ -z "${2:-}" ]] && { error "--fast-model 需要一个值"; exit 1; }
                env_config=$(node -e "console.log(JSON.stringify({...JSON.parse('$env_config'), ANTHROPIC_DEFAULT_HAIKU_MODEL: '$2'}))")
                has_config=true
                shift 2
                ;;
            --opus-model)
                [[ -z "${2:-}" ]] && { error "--opus-model 需要一个值"; exit 1; }
                env_config=$(node -e "console.log(JSON.stringify({...JSON.parse('$env_config'), ANTHROPIC_DEFAULT_OPUS_MODEL: '$2'}))")
                has_config=true
                shift 2
                ;;
            *)
                error "未知选项: $1"
                usage
                exit 1
                ;;
        esac
    done

    if [[ "$has_config" == false ]]; then
        error "没有提供配置选项"
        usage
        exit 1
    fi

    save_env_settings "$env_config"
    success "配置已保存"
}

# ─── 配置命令 ─────────────────────────────────────────────────────────────────
cmd_configure() {
    if [[ $# -eq 0 ]]; then
        configure_interactive
    else
        configure_cli "$@"
    fi
}

# ─── 主程序 ───────────────────────────────────────────────────────────────────
main() {
    [[ $# -eq 0 ]] && { usage; exit 1; }

    local command="$1"
    shift

    case "$command" in
        install)
            cmd_install "$@"
            ;;
        uninstall)
            cmd_uninstall "$@"
            ;;
        configure)
            cmd_configure "$@"
            ;;
        -h|--help|help)
            usage
            exit 0
            ;;
        *)
            error "未知命令: $command"
            usage
            exit 1
            ;;
    esac
}

main "$@"
