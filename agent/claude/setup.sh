#!/usr/bin/env bash
# Claude Code 安装与配置脚本
# 用途：安装、卸载、配置和快速切换 Claude Code 渠道

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILES_DIR="$SCRIPT_DIR/config/profiles"
KEYS_FILE="$HOME/.claude/.profile-keys"   # 本地 API key 存储，不进 git

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
# Claude Code CLI 在所有平台均使用 ~/.claude/settings.json
detect_claude_config_dir() {
    echo "$HOME/.claude"
}

# ─── 用法说明 ────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF

${BOLD}用法:${NC}
  $(basename "$0") <command> [options]

${BOLD}命令:${NC}
  install          安装 Claude Code（含插件）
  install-plugins  仅安装/更新插件（需已安装 Claude Code）
  uninstall        卸载 Claude Code
  sync             将 config/ 通用配置合并到本机 Claude 设置
  configure        精细配置 env 参数（API Key / Base URL / 模型）
  switch [profile] 快速切换渠道（anthropic / openrouter / proxy）
  model <name>     仅切换当前渠道的默认模型
  status           查看当前激活的渠道与配置

${BOLD}switch 说明:${NC}
  ./$(basename "$0") switch                  交互式选择渠道
  ./$(basename "$0") switch anthropic        切换到 Anthropic 官方
  ./$(basename "$0") switch openrouter       切换到 OpenRouter
  ./$(basename "$0") switch proxy            切换到自定义代理
  ./$(basename "$0") switch openrouter --model openai/gpt-4o   切换渠道并改模型

  首次切换某渠道会提示输入 API Key 并保存至 ~/.claude/.profile-keys（本地，不进 git）。
  之后切换相同渠道可直接复用已存 Key，无需重复输入。

${BOLD}configure 选项 (精细控制):${NC}
  --api-key <key>         设置 API Key (ANTHROPIC_AUTH_TOKEN)
  --base-url <url>        设置 Base URL (ANTHROPIC_BASE_URL)
  --model <model>         设置默认模型 (ANTHROPIC_MODEL)
  --fast-model <model>    设置 fast 模式模型 (ANTHROPIC_DEFAULT_HAIKU_MODEL)
  --opus-model <model>    设置 opus 模式模型 (ANTHROPIC_DEFAULT_OPUS_MODEL)

${BOLD}渠道 (profiles):${NC}
  anthropic    Anthropic 官方 API                  https://api.anthropic.com
  openrouter   OpenRouter 多模型聚合               https://openrouter.ai/api/v1
  proxy        自定义代理（LiteLLM / GLM / 百炼）  自定义端点

${BOLD}插件列表 (install/install-plugins):${NC}
  核心: superpowers  context7  claude-hud
  推荐: github  code-review  remember  commit-commands  exa

${BOLD}示例:${NC}
  $(basename "$0") install
  $(basename "$0") switch openrouter
  $(basename "$0") switch openrouter --model openai/gpt-4o
  $(basename "$0") model anthropic/claude-opus-4-8
  $(basename "$0") status
  $(basename "$0") sync

EOF
}

# ─── 安装 Claude Code ────────────────────────────────────────────────────────
cmd_install() {
    step "安装 Claude Code"

    if command -v claude &>/dev/null; then
        warn "Claude Code 已安装: $(claude --version 2>/dev/null || echo 'unknown')"
        read -r -p "是否重新安装? [y/N] " answer
        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            info "跳过安装"
            echo ""
            cmd_install_plugins
            return 0
        fi
    fi

    if ! command -v node &>/dev/null; then
        error "需要 Node.js 16+。请先安装 Node.js"
        exit 1
    fi

    info "Node.js 版本: $(node --version)"
    info "正在安装 Claude Code..."
    npm install -g @anthropic-ai/claude-code

    if command -v claude &>/dev/null; then
        success "Claude Code 安装成功: $(claude --version 2>/dev/null || true)"
    else
        error "安装失败，请检查错误信息"
        exit 1
    fi

    echo ""
    cmd_install_plugins
}

# ─── 插件管理 ────────────────────────────────────────────────────────────────
CORE_PLUGINS=(
    "superpowers@claude-plugins-official"
    "context7@claude-plugins-official"
    "claude-hud@claude-hud"
)

RECOMMENDED_PLUGINS=(
    "github@claude-plugins-official"
    "code-review@claude-plugins-official"
    "remember@claude-plugins-official"
    "commit-commands@claude-plugins-official"
    "exa@claude-plugins-official"
)

EXTRA_MARKETPLACES=(
    "claude-hud:github:jarrodwatts/claude-hud"
)

_ensure_marketplace() {
    local name="${1%%:*}"
    local rest="${1#*:}"
    local source_type="${rest%%:*}"
    local source_value="${rest#*:}"

    if claude plugins marketplace list 2>/dev/null | grep -q "^  ❯ ${name}$"; then
        return 0
    fi

    info "添加 marketplace: $name ($source_value)"
    if [[ "$source_type" == "github" ]]; then
        claude plugins marketplace add "github:${source_value}" "$name" 2>/dev/null \
            && success "Marketplace $name 已添加" \
            || warn "Marketplace $name 添加失败（可能网络问题），跳过"
    fi
}

_install_plugin() {
    local plugin="$1"
    local plugin_name="${plugin%%@*}"

    if claude plugins list 2>/dev/null | grep -qE "❯ ${plugin_name}@"; then
        info "已安装，跳过: $plugin"
        return 0
    fi

    info "安装插件: $plugin"
    if claude plugins install "$plugin" 2>/dev/null; then
        success "已安装: $plugin"
    else
        warn "安装失败（可能需手动授权或网络问题）: $plugin"
    fi
}

cmd_install_plugins() {
    step "安装 Claude Code 插件"

    if ! command -v claude &>/dev/null; then
        error "Claude Code 未安装，请先运行: $(basename "$0") install"
        exit 1
    fi

    for mp in "${EXTRA_MARKETPLACES[@]}"; do
        _ensure_marketplace "$mp"
    done

    echo ""
    info "安装核心插件..."
    for plugin in "${CORE_PLUGINS[@]}"; do
        _install_plugin "$plugin"
    done

    echo ""
    info "安装推荐插件..."
    for plugin in "${RECOMMENDED_PLUGINS[@]}"; do
        _install_plugin "$plugin"
    done

    echo ""
    success "插件安装完成"
    claude plugins list 2>/dev/null | grep -E "❯|Version:|Status:" || true
}

# ─── 卸载 Claude Code ────────────────────────────────────────────────────────
cmd_uninstall() {
    step "卸载 Claude Code"

    if ! command -v claude &>/dev/null; then
        warn "Claude Code 未安装"
        return 0
    fi

    read -r -p "确定要卸载 Claude Code 吗? [y/N] " answer
    [[ ! "$answer" =~ ^[Yy]$ ]] && { info "取消卸载"; return 0; }

    npm uninstall -g @anthropic-ai/claude-code
    command -v claude &>/dev/null && { error "卸载失败"; exit 1; } || success "Claude Code 已卸载"
}

# ─── 同步通用配置到本机 ────────────────────────────────────────────────────────
cmd_sync() {
    step "同步通用配置到本机 Claude 设置"

    local config_dir
    config_dir=$(detect_claude_config_dir)
    local settings_file="$config_dir/settings.json"
    local template_settings="$SCRIPT_DIR/config/settings.json"
    local template_claude_md="$SCRIPT_DIR/config/CLAUDE.md"
    local claude_md_file="$HOME/.claude/CLAUDE.md"

    [[ ! -f "$template_settings" ]] && { error "模板文件不存在: $template_settings"; exit 1; }

    mkdir -p "$config_dir" "$HOME/.claude"

    info "合并 settings.json -> $settings_file"
    node -e "
        const fs = require('fs');
        const template = JSON.parse(fs.readFileSync('$template_settings', 'utf8'));
        let existing = {};
        if (fs.existsSync('$settings_file')) {
            try { existing = JSON.parse(fs.readFileSync('$settings_file', 'utf8')); } catch(e) {}
        }

        const mergePermissions = (tpl, ex) => {
            if (!tpl && !ex) return undefined;
            const t = tpl || {}, e = ex || {};
            const dedup = (a, b) => [...new Set([...(a||[]), ...(b||[])])];
            return { ...t, ...e, allow: dedup(t.allow, e.allow), deny: dedup(t.deny, e.deny) };
        };

        const merged = {
            ...template,
            ...existing,
            permissions: mergePermissions(template.permissions, existing.permissions),
        };

        if (fs.existsSync('$settings_file')) {
            const ts = new Date().toISOString().replace(/[:.]/g,'-').slice(0,19);
            fs.copyFileSync('$settings_file', '$settings_file.bak.' + ts);
        }
        fs.writeFileSync('$settings_file', JSON.stringify(merged, null, 2) + '\n');
        console.log('settings.json 已更新');
    "
    success "settings.json 同步完成"

    info "合并 CLAUDE.md -> $claude_md_file"
    if [[ -f "$claude_md_file" ]]; then
        if grep -qF "Always respond in the same language" "$claude_md_file"; then
            warn "CLAUDE.md 语言规则已存在，跳过"
        else
            cp "$claude_md_file" "${claude_md_file}.bak.$(date +%Y%m%d-%H%M%S)"
            printf '\n%s\n' "$(cat "$template_claude_md")" >> "$claude_md_file"
            success "CLAUDE.md 已追加语言规则"
        fi
    else
        cp "$template_claude_md" "$claude_md_file"
        success "CLAUDE.md 已创建"
    fi
}

# ─── 保存 env 配置到 settings.json ────────────────────────────────────────────
save_env_settings() {
    local config_dir
    config_dir=$(detect_claude_config_dir)
    local settings_file="$config_dir/settings.json"
    mkdir -p "$config_dir"

    node -e "
        const fs = require('fs');
        let settings = {};
        if (fs.existsSync('$settings_file')) {
            try { settings = JSON.parse(fs.readFileSync('$settings_file', 'utf8')); } catch(e) {}
        }
        if (!settings.env) settings.env = {};
        Object.assign(settings.env, $1);
        fs.writeFileSync('$settings_file', JSON.stringify(settings, null, 2) + '\n');
        console.log('已保存至:', '$settings_file');
    "
}

# ─── Profile Key 管理 ─────────────────────────────────────────────────────────
_load_stored_key() {
    local profile="$1"
    if [[ ! -f "$KEYS_FILE" ]]; then echo ""; return; fi
    node -e "
        try {
            const keys = JSON.parse(require('fs').readFileSync('$KEYS_FILE', 'utf8'));
            process.stdout.write(keys['$profile'] || '');
        } catch(e) { process.stdout.write(''); }
    " 2>/dev/null || echo ""
}

_save_stored_key() {
    local profile="$1"
    local key="$2"
    mkdir -p "$(dirname "$KEYS_FILE")"
    node -e "
        const fs = require('fs');
        let keys = {};
        try { keys = JSON.parse(fs.readFileSync('$KEYS_FILE', 'utf8')); } catch(e) {}
        keys['$profile'] = '$key';
        fs.writeFileSync('$KEYS_FILE', JSON.stringify(keys, null, 2) + '\n', { mode: 0o600 });
    "
    chmod 600 "$KEYS_FILE"
}

# ─── 加载 Profile JSON ───────────────────────────────────────────────────────
_profile_field() {
    local profile_file="$1"
    local field="$2"
    node -e "
        try {
            const p = JSON.parse(require('fs').readFileSync('$profile_file', 'utf8'));
            process.stdout.write(p['$field'] || '');
        } catch(e) { process.stdout.write(''); }
    " 2>/dev/null || echo ""
}

_list_profiles() {
    local i=1
    for f in "$PROFILES_DIR"/*.json; do
        [[ -f "$f" ]] || continue
        local name desc
        name=$(basename "$f" .json)
        desc=$(_profile_field "$f" "description")
        printf "  %d) %-14s %s\n" "$i" "$name" "$desc"
        ((i++))
    done
}

_profile_file() {
    echo "$PROFILES_DIR/${1}.json"
}

_profile_exists() {
    [[ -f "$(_profile_file "$1")" ]]
}

# ─── 应用 Profile ─────────────────────────────────────────────────────────────
_apply_profile() {
    local profile="$1"
    local override_model="${2:-}"
    local override_key="${3:-}"

    local profile_file
    profile_file=$(_profile_file "$profile")

    local base_url model fast_model opus_model description
    base_url=$(_profile_field "$profile_file" "base_url")
    model=$(_profile_field "$profile_file" "model")
    fast_model=$(_profile_field "$profile_file" "fast_model")
    opus_model=$(_profile_field "$profile_file" "opus_model")
    description=$(_profile_field "$profile_file" "description")

    # proxy profile 可能 base_url 为空，提示用户填写
    if [[ -z "$base_url" ]]; then
        warn "该 profile 需要手动填写 Base URL"
        read -r -p "Base URL: " base_url
        [[ -z "$base_url" ]] && { error "Base URL 不能为空"; exit 1; }
    fi
    if [[ -z "$model" ]]; then
        read -r -p "默认模型 (ANTHROPIC_MODEL): " model
        [[ -z "$model" ]] && { error "模型不能为空"; exit 1; }
    fi
    [[ -n "$override_model" ]] && model="$override_model"

    # 获取 API Key
    local api_key="$override_key"
    if [[ -z "$api_key" ]]; then
        api_key=$(_load_stored_key "$profile")
    fi
    if [[ -z "$api_key" ]]; then
        local key_hint
        key_hint=$(_profile_field "$profile_file" "key_hint")
        echo ""
        warn "未找到 $profile 的 API Key（格式: ${key_hint:-your-api-key}）"
        read -r -s -p "请输入 API Key（直接回车跳过）: " api_key
        echo ""
        if [[ -n "$api_key" ]]; then
            read -r -p "是否保存 Key 到 ~/.claude/.profile-keys? [Y/n] " save_ans
            if [[ ! "$save_ans" =~ ^[Nn]$ ]]; then
                _save_stored_key "$profile" "$api_key"
                success "Key 已保存到 $KEYS_FILE"
            fi
        fi
    fi

    # 构建 env 并保存
    local env_json
    env_json=$(node -e "
        const env = {
            ANTHROPIC_BASE_URL: '$base_url',
            ANTHROPIC_MODEL: '$model',
        };
        if ('$fast_model') env.ANTHROPIC_DEFAULT_HAIKU_MODEL = '$fast_model';
        if ('$opus_model') env.ANTHROPIC_DEFAULT_OPUS_MODEL = '$opus_model';
        if ('$api_key') env.ANTHROPIC_AUTH_TOKEN = '$api_key';
        console.log(JSON.stringify(env));
    ")

    save_env_settings "$env_json"

    # 记录当前激活的 profile
    node -e "
        const fs = require('fs');
        let keys = {};
        try { keys = JSON.parse(fs.readFileSync('$KEYS_FILE', 'utf8')); } catch(e) {}
        keys['__active__'] = '$profile';
        fs.writeFileSync('$KEYS_FILE', JSON.stringify(keys, null, 2) + '\n', { mode: 0o600 });
    " 2>/dev/null || true

    echo ""
    success "已切换到 ${BOLD}${profile}${NC}: $description"
    info "Base URL : $base_url"
    info "模型     : $model"
    [[ -n "$fast_model" ]] && info "Fast 模型 : $fast_model"
    [[ -n "$opus_model" ]] && info "Opus 模型 : $opus_model"
    [[ -n "$api_key" ]] && info "API Key   : ${api_key:0:12}..."
}

# ─── switch 命令 ─────────────────────────────────────────────────────────────
cmd_switch() {
    step "切换渠道"

    local profile=""
    local override_model=""
    local override_key=""

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --model)    override_model="${2:-}"; shift 2 ;;
            --api-key)  override_key="${2:-}"; shift 2 ;;
            -*)         error "未知选项: $1"; usage; exit 1 ;;
            *)          profile="$1"; shift ;;
        esac
    done

    # 交互式选择
    if [[ -z "$profile" ]]; then
        echo ""
        echo "${BOLD}可用渠道:${NC}"
        _list_profiles
        echo ""
        read -r -p "选择渠道 (输入名称或序号): " profile
        # 支持序号输入
        if [[ "$profile" =~ ^[0-9]+$ ]]; then
            local idx=0
            for f in "$PROFILES_DIR"/*.json; do
                [[ -f "$f" ]] || continue
                ((idx++))
                if [[ "$idx" == "$profile" ]]; then
                    profile=$(basename "$f" .json)
                    break
                fi
            done
        fi
    fi

    if ! _profile_exists "$profile"; then
        error "未知渠道: $profile"
        echo ""
        echo "可用渠道:"
        _list_profiles
        exit 1
    fi

    _apply_profile "$profile" "$override_model" "$override_key"
}

# ─── model 命令（仅改模型）──────────────────────────────────────────────────
cmd_model() {
    [[ $# -eq 0 ]] && { error "用法: $(basename "$0") model <model-name>"; exit 1; }
    local new_model="$1"

    step "切换模型 -> $new_model"
    save_env_settings "{\"ANTHROPIC_MODEL\": \"$new_model\"}"
    success "模型已更新: $new_model"
    info "提示: 此修改不影响当前渠道的 Base URL 和 API Key"
}

# ─── status 命令 ─────────────────────────────────────────────────────────────
cmd_status() {
    step "当前 Claude Code 配置"

    local config_dir
    config_dir=$(detect_claude_config_dir)
    local settings_file="$config_dir/settings.json"

    # 当前激活的 profile
    local active_profile=""
    if [[ -f "$KEYS_FILE" ]]; then
        active_profile=$(node -e "
            try {
                const k = JSON.parse(require('fs').readFileSync('$KEYS_FILE', 'utf8'));
                process.stdout.write(k['__active__'] || '');
            } catch(e) {}
        " 2>/dev/null || echo "")
    fi
    [[ -n "$active_profile" ]] && info "当前渠道: ${BOLD}$active_profile${NC}" || info "当前渠道: 未知（手动配置）"

    if [[ ! -f "$settings_file" ]]; then
        warn "settings.json 不存在: $settings_file"
        return
    fi

    echo ""
    node -e "
        const fs = require('fs');
        let s = {};
        try { s = JSON.parse(fs.readFileSync('$settings_file', 'utf8')); } catch(e) {}
        const env = s.env || {};
        const mask = (v) => typeof v === 'string' && v.length > 12 ? v.slice(0,12)+'...' : v;
        const fields = [
            ['ANTHROPIC_BASE_URL',              'Base URL '],
            ['ANTHROPIC_MODEL',                 '模型     '],
            ['ANTHROPIC_DEFAULT_HAIKU_MODEL',   'Fast 模型'],
            ['ANTHROPIC_DEFAULT_OPUS_MODEL',    'Opus 模型'],
            ['ANTHROPIC_AUTH_TOKEN',            'API Key  '],
        ];
        fields.forEach(([k, label]) => {
            if (env[k]) {
                const val = k === 'ANTHROPIC_AUTH_TOKEN' ? mask(env[k]) : env[k];
                console.log('  ' + label + ': ' + val);
            }
        });
        if (Object.keys(env).length === 0) console.log('  （env 为空，可能使用 claude login 订阅）');
    "

    echo ""
    # 保存的 profile keys 摘要
    if [[ -f "$KEYS_FILE" ]]; then
        info "已保存 API Key 的渠道:"
        node -e "
            try {
                const keys = JSON.parse(require('fs').readFileSync('$KEYS_FILE', 'utf8'));
                Object.entries(keys).forEach(([k, v]) => {
                    if (k.startsWith('__')) return;
                    const masked = typeof v === 'string' && v.length > 12 ? v.slice(0,12)+'...' : v;
                    console.log('  ' + k + ': ' + masked);
                });
            } catch(e) {}
        " 2>/dev/null || true
    fi

    echo ""
    info "Claude Code 版本: $(claude --version 2>/dev/null || echo '未安装')"
}

# ─── configure 命令（精细控制）──────────────────────────────────────────────
_configure_interactive() {
    step "配置 Claude Code"

    local config_dir
    config_dir=$(detect_claude_config_dir)
    info "配置文件: $config_dir/settings.json"

    echo ""
    echo "${BOLD}选择配置方式:${NC}"
    echo "  1) 快速切换渠道（推荐：anthropic / openrouter / proxy）"
    echo "  2) 手动填写所有参数"
    read -r -p "选择 [1/2, 默认 1]: " choice
    choice=${choice:-1}

    if [[ "$choice" == "1" ]]; then
        cmd_switch
        return
    fi

    echo ""
    read -r -s -p "API Key (ANTHROPIC_AUTH_TOKEN，直接回车跳过): " api_key; echo ""
    read -r -p "Base URL [默认: https://api.anthropic.com]: " base_url
    base_url=${base_url:-https://api.anthropic.com}
    read -r -p "默认模型 [默认: claude-sonnet-4-6]: " model
    model=${model:-claude-sonnet-4-6}
    read -r -p "Fast 模型 [默认: claude-haiku-4-5-20251001]: " fast_model
    fast_model=${fast_model:-claude-haiku-4-5-20251001}
    read -r -p "Opus 模型 [默认: claude-opus-4-8]: " opus_model
    opus_model=${opus_model:-claude-opus-4-8}

    local env_json
    env_json=$(node -e "
        const env = {
            ANTHROPIC_BASE_URL: '$base_url',
            ANTHROPIC_MODEL: '$model',
            ANTHROPIC_DEFAULT_HAIKU_MODEL: '$fast_model',
            ANTHROPIC_DEFAULT_OPUS_MODEL: '$opus_model',
        };
        if ('$api_key') env.ANTHROPIC_AUTH_TOKEN = '$api_key';
        console.log(JSON.stringify(env));
    ")

    echo ""
    step "配置预览"
    echo "$env_json" | node -e "
        const env = JSON.parse(require('fs').readFileSync(0,'utf8'));
        Object.entries(env).forEach(([k,v]) => {
            if (k==='ANTHROPIC_AUTH_TOKEN' && v.length > 12) v = v.slice(0,12)+'...';
            console.log('  ' + k + ': ' + v);
        });
    "

    echo ""
    read -r -p "保存配置? [Y/n] " answer
    if [[ ! "$answer" =~ ^[Nn]$ ]]; then
        save_env_settings "$env_json"
        success "配置已保存"
    else
        info "配置未保存"
    fi
}

_configure_cli() {
    local env_config='{}'
    local has_config=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --api-key)
                [[ -z "${2:-}" ]] && { error "--api-key 需要一个值"; exit 1; }
                env_config=$(node -e "console.log(JSON.stringify({...JSON.parse('$env_config'), ANTHROPIC_AUTH_TOKEN: '$2'}))")
                has_config=true; shift 2 ;;
            --base-url)
                [[ -z "${2:-}" ]] && { error "--base-url 需要一个值"; exit 1; }
                env_config=$(node -e "console.log(JSON.stringify({...JSON.parse('$env_config'), ANTHROPIC_BASE_URL: '$2'}))")
                has_config=true; shift 2 ;;
            --model)
                [[ -z "${2:-}" ]] && { error "--model 需要一个值"; exit 1; }
                env_config=$(node -e "console.log(JSON.stringify({...JSON.parse('$env_config'), ANTHROPIC_MODEL: '$2'}))")
                has_config=true; shift 2 ;;
            --fast-model)
                [[ -z "${2:-}" ]] && { error "--fast-model 需要一个值"; exit 1; }
                env_config=$(node -e "console.log(JSON.stringify({...JSON.parse('$env_config'), ANTHROPIC_DEFAULT_HAIKU_MODEL: '$2'}))")
                has_config=true; shift 2 ;;
            --opus-model)
                [[ -z "${2:-}" ]] && { error "--opus-model 需要一个值"; exit 1; }
                env_config=$(node -e "console.log(JSON.stringify({...JSON.parse('$env_config'), ANTHROPIC_DEFAULT_OPUS_MODEL: '$2'}))")
                has_config=true; shift 2 ;;
            *) error "未知选项: $1"; usage; exit 1 ;;
        esac
    done

    [[ "$has_config" == false ]] && { error "没有提供配置选项"; usage; exit 1; }
    save_env_settings "$env_config"
    success "配置已保存"
}

cmd_configure() {
    if [[ $# -eq 0 ]]; then
        _configure_interactive
    else
        step "配置 Claude Code"
        _configure_cli "$@"
    fi
}

# ─── 主程序 ───────────────────────────────────────────────────────────────────
main() {
    [[ $# -eq 0 ]] && { usage; exit 1; }

    local command="$1"; shift

    case "$command" in
        install)         cmd_install "$@" ;;
        install-plugins) cmd_install_plugins "$@" ;;
        uninstall)       cmd_uninstall "$@" ;;
        sync)            cmd_sync "$@" ;;
        switch)          cmd_switch "$@" ;;
        model)           cmd_model "$@" ;;
        status)          cmd_status "$@" ;;
        configure)       cmd_configure "$@" ;;
        -h|--help|help)  usage; exit 0 ;;
        *)               error "未知命令: $command"; usage; exit 1 ;;
    esac
}

main "$@"
