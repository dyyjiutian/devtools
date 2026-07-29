#!/usr/bin/env bash
# Codex CLI 安装与配置脚本
# 用途：安装、卸载、配置和快速切换 OpenAI Codex CLI 渠道

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILES_DIR="$SCRIPT_DIR/config/profiles"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CONFIG_FILE="$CODEX_HOME/config.toml"
RULES_FILE="$CODEX_HOME/rules/default.rules"
KEYS_FILE="$CODEX_HOME/.profile-keys"   # 本地 API key 存储，不进 git
ENV_FILE="$CODEX_HOME/env.sh"           # 导出各渠道 API Key 的脚本

# 托管块标记（config.toml 中标记之间的内容由本脚本生成）
MANAGED_BEGIN="# >>> devtools codex managed BEGIN <<<"
MANAGED_END="# >>> devtools codex managed END <<<"
PERMISSIONS_BEGIN="# >>> devtools codex permissions BEGIN <<<"
PERMISSIONS_END="# >>> devtools codex permissions END <<<"
# shell rc 中自动加载 env.sh 的标记
RC_BEGIN="# >>> devtools codex env BEGIN <<<"
RC_END="# >>> devtools codex env END <<<"

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

# ─── 用法说明 ────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF

${BOLD}用法:${NC}
  $(basename "$0") <command> [options]

${BOLD}命令:${NC}
  install          安装 Codex CLI（npm）+ 推荐插件 + sync
  install-plugins  安装/更新推荐插件（需已安装 Codex CLI）
  uninstall        卸载 Codex CLI
  sync             将 config/ 通用配置合并到本机（config.toml 托管块 + AGENTS.md + features.apps）
  configure        精细配置参数（模型 / 渠道 / Base URL / reasoning 等）
  switch [profile] 快速切换渠道（openai / openrouter / proxy）
  model <name>     仅切换当前渠道的默认模型
  status           查看当前激活的渠道与配置
  login            使用 codex login 登录（ChatGPT 订阅 / API Key）

${BOLD}install-plugins 用法:${NC}
  ./$(basename "$0") install-plugins              安装全部核心 + 推荐插件
  ./$(basename "$0") install-plugins --list       打印可安装列表
  ./$(basename "$0") install-plugins <name>...    只安装指定插件（短名或 name@marketplace）

${BOLD}插件列表 (install/install-plugins):${NC}
  核心: superpowers  github
  推荐: coderabbit  vercel  sentry  figma  build-web-apps

${BOLD}switch 说明:${NC}
  ./$(basename "$0") switch                 交互式选择渠道
  ./$(basename "$0") switch openai          切换到 OpenAI 官方
  ./$(basename "$0") switch openrouter      切换到 OpenRouter
  ./$(basename "$0") switch proxy           切换到自定义代理
  ./$(basename "$0") switch openrouter --model openai/gpt-4o   切换渠道并改模型

  首次切换某渠道会提示输入 API Key 并保存至 ~/.codex/.profile-keys（本地，不进 git）。
  Key 通过 ~/.codex/env.sh 以环境变量形式提供给 Codex（env_key 机制）。

${BOLD}configure 选项 (精细控制):${NC}
  --api-key <key>       设置当前/指定渠道的 API Key
  --base-url <url>      设置 Base URL（自定义渠道）
  --model <model>       设置默认模型
  --reasoning <level>   reasoning effort: minimal|low|medium|high|xhigh
  --provider <id>       目标渠道 (openai / openrouter / proxy)

${BOLD}渠道 (profiles):${NC}
  openai       OpenAI 官方（ChatGPT 登录或 OPENAI_API_KEY）
  openrouter   OpenRouter 多模型聚合          https://openrouter.ai/api/v1
  proxy        自定义代理（LiteLLM / 百炼 / 国内中转）   自定义端点

${BOLD}示例:${NC}
  $(basename "$0") install
  $(basename "$0") switch openrouter
  $(basename "$0") switch openrouter --model openai/gpt-4o
  $(basename "$0") model gpt-5-codex
  $(basename "$0") status
  $(basename "$0") sync

EOF
}

# ─── 依赖检测 ────────────────────────────────────────────────────────────────
require_node() {
    if ! command -v node &>/dev/null; then
        error "需要 Node.js 读取/写入 JSON 配置。请先安装 Node.js"
        exit 1
    fi
}

# ─── Profile JSON 读取 ───────────────────────────────────────────────────────
_profile_file() { echo "$PROFILES_DIR/${1}.json"; }
_profile_exists() { [[ -f "$(_profile_file "$1")" ]]; }

_profile_field() {
    local profile_file="$1" field="$2"
    node -e "
        try {
            const p = JSON.parse(require('fs').readFileSync('$profile_file', 'utf8'));
            const v = p['$field'];
            process.stdout.write(v === undefined || v === null ? '' : String(v));
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
        printf "  %d) %-12s %s\n" "$i" "$name" "$desc"
        ((i++))
    done
}

# ─── 本地 Key / override 存储 ────────────────────────────────────────────────
_keys_get() {
    local key="$1"
    [[ -f "$KEYS_FILE" ]] || { echo ""; return; }
    node -e "
        try {
            const k = JSON.parse(require('fs').readFileSync('$KEYS_FILE','utf8'));
            process.stdout.write(k['$key'] || '');
        } catch(e) { process.stdout.write(''); }
    " 2>/dev/null || echo ""
}

_keys_set() {
    local key="$1" value="$2"
    mkdir -p "$(dirname "$KEYS_FILE")"
    node -e "
        const fs = require('fs');
        let k = {};
        try { k = JSON.parse(fs.readFileSync('$KEYS_FILE','utf8')); } catch(e) {}
        k['$key'] = '$value';
        fs.writeFileSync('$KEYS_FILE', JSON.stringify(k, null, 2) + '\n', { mode: 0o600 });
    "
    chmod 600 "$KEYS_FILE" 2>/dev/null || true
}

# ─── 重新生成 env.sh（导出所有已保存渠道的 Key）──────────────────────────────
_regen_env_file() {
    require_node
    mkdir -p "$CODEX_HOME"
    node -e "
        const fs = require('fs');
        const path = require('path');
        const profilesDir = '$PROFILES_DIR';
        let keys = {};
        try { keys = JSON.parse(fs.readFileSync('$KEYS_FILE','utf8')); } catch(e) {}
        let out = '# Generated by devtools codex setup.sh — do not edit\n';
        for (const f of fs.readdirSync(profilesDir)) {
            if (!f.endsWith('.json')) continue;
            const name = f.replace(/\.json$/, '');
            const key = keys[name];
            if (!key) continue;
            let envVar = 'OPENAI_API_KEY';
            try { envVar = JSON.parse(fs.readFileSync(path.join(profilesDir, f),'utf8')).env_var || envVar; } catch(e) {}
            out += 'export ' + envVar + '=' + JSON.stringify(key) + '\n';
        }
        fs.writeFileSync('$ENV_FILE', out, { mode: 0o600 });
    "
    chmod 600 "$ENV_FILE" 2>/dev/null || true
}

# ─── 确保 shell rc 自动加载 env.sh ───────────────────────────────────────────
_detect_rc_file() {
    case "$(basename "${SHELL:-}")" in
        zsh)  echo "$HOME/.zshrc" ;;
        bash) echo "$HOME/.bashrc" ;;
        *)    [[ -f "$HOME/.zshrc" ]] && echo "$HOME/.zshrc" || echo "$HOME/.bashrc" ;;
    esac
}

_ensure_rc_source() {
    local rc_file
    rc_file=$(_detect_rc_file)
    if [[ -f "$rc_file" ]] && grep -qF "$RC_BEGIN" "$rc_file"; then
        return 0
    fi
    if [[ ! -t 0 ]]; then
        info "如需自动加载 Key，请在 shell rc 中添加: [ -f ~/.codex/env.sh ] && . ~/.codex/env.sh"
        return 0
    fi
    local ans=""
    read -r -p "是否让 shell 启动时自动加载 API Key（写入 ${rc_file}）? [Y/n] " ans
    if [[ "$ans" =~ ^[Nn]$ ]]; then
        info "已跳过。可手动执行: source $ENV_FILE"
        return 0
    fi
    {
        printf '\n%s\n' "$RC_BEGIN"
        printf '%s\n' '[ -f "$HOME/.codex/env.sh" ] && . "$HOME/.codex/env.sh"'
        printf '%s\n' "$RC_END"
    } >> "$rc_file"
    success "已写入 ${rc_file}，新终端将自动加载 Key"
    info "当前终端可执行: source $ENV_FILE"
}

_remove_rc_source() {
    local rc_file
    rc_file=$(_detect_rc_file)
    [[ -f "$rc_file" ]] || return 0
    grep -qF "$RC_BEGIN" "$rc_file" || return 0
    local tmp
    tmp=$(mktemp)
    awk -v b="$RC_BEGIN" -v e="$RC_END" '
        $0==b {skip=1}
        skip { if ($0==e) skip=0; next }
        {print}
    ' "$rc_file" > "$tmp"
    mv "$tmp" "$rc_file"
    success "已从 $rc_file 移除自动加载配置"
}

# ─── 写入/替换 config.toml 托管块 ────────────────────────────────────────────
# 参数：完整托管块正文（不含标记行）通过 stdin 传入
_write_managed_block() {
    mkdir -p "$CODEX_HOME"
    local body
    body="$(cat)"

    local tmp
    tmp=$(mktemp)
    if [[ -f "$CONFIG_FILE" ]]; then
        cp "$CONFIG_FILE" "$CONFIG_FILE.bak.$(date +%Y%m%d-%H%M%S)"
        awk -v b="$MANAGED_BEGIN" -v e="$MANAGED_END" '
            $0==b {skip=1; next}
            skip { if ($0==e) skip=0; next }
            {print}
        ' "$CONFIG_FILE" > "$tmp"
    else
        : > "$tmp"
    fi

    {
        printf '%s\n' "$MANAGED_BEGIN"
        printf '%s\n' "$body"
        printf '%s\n' "$MANAGED_END"
    } >> "$tmp"

    mv "$tmp" "$CONFIG_FILE"
}

# ─── 同步默认权限配置 ────────────────────────────────────────────────────────
_sync_permission_defaults() {
    local template="$SCRIPT_DIR/config/config.toml"
    [[ -f "$template" ]] || { error "权限配置模板不存在: $template"; exit 1; }

    local approval sandbox
    approval=$(sed -nE 's/^[[:space:]]*approval_policy[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$template" | head -n 1)
    sandbox=$(sed -nE 's/^[[:space:]]*sandbox_mode[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$template" | head -n 1)
    [[ -n "$approval" && -n "$sandbox" ]] || { error "权限配置模板缺少 approval_policy 或 sandbox_mode"; exit 1; }

    local body tmp
    body=$(mktemp)
    tmp=$(mktemp)
    awk '
        BEGIN { root = 1; started = 0 }
        root && /^[[:space:]]*\[/ { root = 0 }
        root && /^[[:space:]]*(approval_policy|sandbox_mode)[[:space:]]*=/ { next }
        !started && /^[[:space:]]*$/ { next }
        { started = 1; print }
    ' "$CONFIG_FILE" > "$body"

    {
        printf 'approval_policy = "%s"\n' "$approval"
        printf 'sandbox_mode = "%s"\n\n' "$sandbox"
        awk '{ lines[NR] = $0 } END { n = NR; while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--; for (i = 1; i <= n; i++) print lines[i] }' "$body"
        printf '\n'
    } > "$tmp"

    if ! cmp -s "$tmp" "$CONFIG_FILE"; then
        cp "$CONFIG_FILE" "$CONFIG_FILE.bak.$(date +%Y%m%d-%H%M%S)"
        mv "$tmp" "$CONFIG_FILE"
        success "默认权限已同步（其他操作默认允许）"
    else
        rm -f "$tmp"
        info "默认权限已是最新"
    fi
    rm -f "$body"
}

_sync_permission_rules() {
    local template="$SCRIPT_DIR/config/rules/default.rules"
    [[ -f "$template" ]] || { error "权限规则模板不存在: $template"; exit 1; }

    mkdir -p "$(dirname "$RULES_FILE")"
    local user_rules tmp
    user_rules=$(mktemp)
    tmp=$(mktemp)

    if [[ -f "$RULES_FILE" ]]; then
        awk -v b="$PERMISSIONS_BEGIN" -v e="$PERMISSIONS_END" '
            $0 == b { skip = 1; next }
            skip { if ($0 == e) skip = 0; next }
            { lines[++n] = $0 }
            END {
                while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--
                for (i = 1; i <= n; i++) print lines[i]
            }
        ' "$RULES_FILE" > "$user_rules"
    else
        : > "$user_rules"
    fi

    {
        if [[ -s "$user_rules" ]]; then
            awk '{ print }' "$user_rules"
            printf '\n'
        fi
        printf '%s\n' "$PERMISSIONS_BEGIN"
        awk '{ print }' "$template"
        printf '%s\n' "$PERMISSIONS_END"
    } > "$tmp"

    if [[ ! -f "$RULES_FILE" ]] || ! cmp -s "$tmp" "$RULES_FILE"; then
        [[ -f "$RULES_FILE" ]] && cp "$RULES_FILE" "$RULES_FILE.bak.$(date +%Y%m%d-%H%M%S)"
        mv "$tmp" "$RULES_FILE"
        success "敏感命令确认规则已同步"
    else
        rm -f "$tmp"
        info "敏感命令确认规则已是最新"
    fi
    rm -f "$user_rules"
}

# ─── features.apps = false（CLI/Linux 不需要 Apps 连接器）─────────────────────
_sync_features_apps_disabled() {
    mkdir -p "$CODEX_HOME"

    if command -v codex &>/dev/null; then
        if codex features disable apps >/dev/null 2>&1; then
            success "已关闭 features.apps（codex features disable apps）"
            return 0
        fi
        warn "codex features disable apps 失败，回退到直接改 config.toml"
    fi

    local tmp
    tmp=$(mktemp)
    if [[ -f "$CONFIG_FILE" ]]; then
        cp "$CONFIG_FILE" "$CONFIG_FILE.bak.$(date +%Y%m%d-%H%M%S)"
        awk '
            BEGIN { in_features = 0; apps_set = 0; features_seen = 0 }
            /^[[:space:]]*\[features\][[:space:]]*$/ {
                in_features = 1
                features_seen = 1
                print
                next
            }
            /^[[:space:]]*\[/ {
                if (in_features && !apps_set) {
                    print "apps = false"
                    apps_set = 1
                }
                in_features = 0
                print
                next
            }
            in_features && /^[[:space:]]*apps[[:space:]]*=/ {
                if (!apps_set) {
                    print "apps = false"
                    apps_set = 1
                }
                next
            }
            { print }
            END {
                if (in_features && !apps_set) print "apps = false"
                if (!features_seen) {
                    print ""
                    print "[features]"
                    print "apps = false"
                }
            }
        ' "$CONFIG_FILE" > "$tmp"
    else
        printf '[features]\napps = false\n' > "$tmp"
    fi

    if [[ ! -f "$CONFIG_FILE" ]] || ! cmp -s "$tmp" "$CONFIG_FILE"; then
        mv "$tmp" "$CONFIG_FILE"
        success "已写入 features.apps = false"
    else
        rm -f "$tmp"
        info "features.apps 已是 false"
    fi
}

# ─── 插件管理 ────────────────────────────────────────────────────────────────
CORE_PLUGINS=(
    "superpowers@openai-curated"
    "github@openai-curated"
)

RECOMMENDED_PLUGINS=(
    "coderabbit@openai-curated"
    "vercel@openai-curated"
    "sentry@openai-curated"
    "figma@openai-curated"
    "build-web-apps@openai-curated"
)

_all_plugins() {
    printf '%s\n' "${CORE_PLUGINS[@]}" "${RECOMMENDED_PLUGINS[@]}"
}

_plugin_tier() {
    local plugin="$1" p
    for p in "${CORE_PLUGINS[@]}"; do
        [[ "$p" == "$plugin" ]] && { echo "核心"; return 0; }
    done
    for p in "${RECOMMENDED_PLUGINS[@]}"; do
        [[ "$p" == "$plugin" ]] && { echo "推荐"; return 0; }
    done
    echo "?"
}

_resolve_plugin() {
    local want="$1" plugin short
    if [[ "$want" == *@* ]]; then
        for plugin in $(_all_plugins); do
            [[ "$plugin" == "$want" ]] && { printf '%s\n' "$plugin"; return 0; }
        done
        printf '%s\n' "$want"
        return 0
    fi
    for plugin in $(_all_plugins); do
        short="${plugin%%@*}"
        [[ "$short" == "$want" ]] && { printf '%s\n' "$plugin"; return 0; }
    done
    return 1
}

_list_plugins() {
    local plugin short tier
    echo "${BOLD}可安装插件:${NC}"
    echo ""
    printf "  %-8s %-20s %s\n" "级别" "短名" "完整 ID"
    printf "  %-8s %-20s %s\n" "----" "----" "--------"
    for plugin in $(_all_plugins); do
        short="${plugin%%@*}"
        tier="$(_plugin_tier "$plugin")"
        printf "  %-8s %-20s %s\n" "$tier" "$short" "$plugin"
    done
}

_plugin_installed() {
    local plugin="$1"
    local plugin_id="$plugin"
    local json
    json="$(codex plugin list --json 2>/dev/null || true)"
    [[ -n "$json" ]] || return 1
    node -e "
        let d;
        try { d = JSON.parse(process.argv[1]); } catch (e) { process.exit(1); }
        const installed = d.installed || [];
        const id = process.argv[2];
        const short = id.split('@')[0];
        const hit = installed.some((p) =>
            p.pluginId === id || p.name === short ||
            (p.name === short && p.marketplaceName && id.endsWith('@' + p.marketplaceName))
        );
        process.exit(hit ? 0 : 1);
    " "$json" "$plugin_id" 2>/dev/null
}

_install_plugin() {
    local plugin="$1"
    if _plugin_installed "$plugin"; then
        info "已安装，跳过: $plugin"
        return 0
    fi
    info "安装插件: $plugin"
    if codex plugin add "$plugin" >/dev/null 2>&1; then
        success "已安装: $plugin"
    else
        warn "安装失败（可能需登录、授权或网络问题）: $plugin"
    fi
}

cmd_install_plugins() {
    local list_only=0
    local -a wants=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --list|-l) list_only=1; shift ;;
            -h|--help) usage; exit 0 ;;
            -*) error "未知选项: $1"; usage; exit 1 ;;
            *) wants+=("$1"); shift ;;
        esac
    done

    if [[ "$list_only" -eq 1 ]]; then
        _list_plugins
        return 0
    fi

    step "安装 Codex CLI 插件"

    if ! command -v codex &>/dev/null; then
        error "Codex CLI 未安装，请先运行: $(basename "$0") install"
        exit 1
    fi
    require_node

    local -a to_install=()
    if [[ ${#wants[@]} -eq 0 ]]; then
        to_install=("${CORE_PLUGINS[@]}" "${RECOMMENDED_PLUGINS[@]}")
    else
        local want resolved
        for want in "${wants[@]}"; do
            if ! resolved="$(_resolve_plugin "$want")"; then
                error "未知插件: $want（可用: $(basename "$0") install-plugins --list）"
                exit 1
            fi
            to_install+=("$resolved")
        done
    fi

    echo ""
    local plugin
    for plugin in "${to_install[@]}"; do
        _install_plugin "$plugin"
    done

    echo ""
    success "插件安装完成"
    codex plugin list 2>/dev/null | head -n 40 || true
}

# ─── 应用 Profile ─────────────────────────────────────────────────────────────
_apply_profile() {
    require_node
    local profile="$1"
    local override_model="${2:-}"
    local override_key="${3:-}"
    local override_base_url="${4:-}"
    local override_reasoning="${5:-}"
    local prompt_key="${6:-1}"   # 1=允许交互提示输入 Key（switch/configure），0=静默复用（model）

    local pf
    pf=$(_profile_file "$profile")

    local provider name base_url env_var wire_api model reasoning builtin req_auth
    provider=$(_profile_field "$pf" "provider")
    name=$(_profile_field "$pf" "name")
    base_url=$(_profile_field "$pf" "base_url")
    env_var=$(_profile_field "$pf" "env_var")
    wire_api=$(_profile_field "$pf" "wire_api")
    model=$(_profile_field "$pf" "model")
    reasoning=$(_profile_field "$pf" "reasoning_effort")
    builtin=$(_profile_field "$pf" "builtin")
    req_auth=$(_profile_field "$pf" "requires_openai_auth")

    [[ -z "$provider" ]] && provider="$profile"
    [[ -z "$name" ]] && name="$profile"
    [[ -z "$wire_api" ]] && wire_api="chat"
    [[ -n "$override_reasoning" ]] && reasoning="$override_reasoning"
    [[ -z "$reasoning" ]] && reasoning="medium"

    # 自定义渠道：base_url 从本地 override / 交互补全
    if [[ "$builtin" != "true" ]]; then
        [[ -n "$override_base_url" ]] && base_url="$override_base_url"
        [[ -z "$base_url" ]] && base_url="$(_keys_get "${profile}__base_url")"
        if [[ -z "$base_url" ]]; then
            if [[ -t 0 ]]; then
                read -r -p "Base URL（OpenAI 兼容端点，以 /v1 结尾）: " base_url
            fi
            [[ -z "$base_url" ]] && { error "自定义渠道需要 Base URL（--base-url 或交互输入）"; exit 1; }
        fi
        _keys_set "${profile}__base_url" "$base_url"
    fi

    # 模型
    [[ -n "$override_model" ]] && model="$override_model"
    [[ -z "$model" ]] && model="$(_keys_get "${profile}__model")"
    if [[ -z "$model" ]]; then
        [[ -t 0 ]] && read -r -p "默认模型: " model
        [[ -z "$model" ]] && { error "需要指定模型（--model 或交互输入）"; exit 1; }
    fi
    _keys_set "${profile}__model" "$model"

    # API Key
    local api_key="$override_key"
    [[ -z "$api_key" ]] && api_key="$(_keys_get "$profile")"
    if [[ -z "$api_key" && "$prompt_key" == "1" && -t 0 ]]; then
        local hint
        hint=$(_profile_field "$pf" "key_hint")
        echo ""
        warn "未找到 $profile 的 API Key（格式: ${hint:-your-api-key}）"
        if [[ "$builtin" == "true" ]]; then
            info "OpenAI 官方渠道也可直接使用 codex login 订阅登录，可留空跳过"
        fi
        read -r -s -p "请输入 API Key（直接回车跳过）: " api_key
        echo ""
    fi
    if [[ -n "$api_key" ]]; then
        _keys_set "$profile" "$api_key"
    fi

    # 生成托管块
    local block
    block="model = \"$model\"
model_provider = \"$provider\"
model_reasoning_effort = \"$reasoning\""
    if [[ "$builtin" == "true" ]]; then
        # OpenAI 内置渠道：仅在提供了自定义 base_url 时写 openai_base_url
        if [[ -n "$base_url" ]]; then
            block="$block
openai_base_url = \"$base_url\""
        fi
    else
        block="$block

[model_providers.$provider]
name = \"$name\"
base_url = \"$base_url\"
env_key = \"$env_var\"
wire_api = \"$wire_api\""
    fi

    printf '%s\n' "$block" | _write_managed_block

    # 记录激活渠道 + 刷新 env.sh
    _keys_set "__active__" "$profile"
    _regen_env_file
    [[ -n "$api_key" ]] && _ensure_rc_source

    echo ""
    success "已切换到 ${BOLD}${profile}${NC}: $(_profile_field "$pf" description)"
    info "模型     : $model"
    info "渠道 ID  : $provider"
    info "reasoning: $reasoning"
    [[ "$builtin" != "true" ]] && info "Base URL : $base_url"
    [[ "$builtin" != "true" ]] && info "env_key  : $env_var"
    [[ -n "$api_key" ]] && info "API Key  : ${api_key:0:12}..."
    [[ "$builtin" == "true" && -z "$api_key" ]] && info "认证方式 : codex login（订阅）"
    return 0
}

# ─── switch 命令 ─────────────────────────────────────────────────────────────
cmd_switch() {
    step "切换渠道"

    local profile="" override_model="" override_key="" override_base_url="" override_reasoning=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --model)     override_model="${2:-}"; shift 2 ;;
            --api-key)   override_key="${2:-}"; shift 2 ;;
            --base-url)  override_base_url="${2:-}"; shift 2 ;;
            --reasoning) override_reasoning="${2:-}"; shift 2 ;;
            -*)          error "未知选项: $1"; usage; exit 1 ;;
            *)           profile="$1"; shift ;;
        esac
    done

    if [[ -z "$profile" ]]; then
        echo ""
        echo "${BOLD}可用渠道:${NC}"
        _list_profiles
        echo ""
        read -r -p "选择渠道 (输入名称或序号): " profile
        if [[ "$profile" =~ ^[0-9]+$ ]]; then
            local idx=0
            for f in "$PROFILES_DIR"/*.json; do
                [[ -f "$f" ]] || continue
                ((idx++))
                [[ "$idx" == "$profile" ]] && { profile=$(basename "$f" .json); break; }
            done
        fi
    fi

    if ! _profile_exists "$profile"; then
        error "未知渠道: $profile"
        echo ""; echo "可用渠道:"; _list_profiles
        exit 1
    fi

    _apply_profile "$profile" "$override_model" "$override_key" "$override_base_url" "$override_reasoning"
}

# ─── model 命令（仅改模型）──────────────────────────────────────────────────
cmd_model() {
    [[ $# -eq 0 ]] && { error "用法: $(basename "$0") model <model-name>"; exit 1; }
    local new_model="$1"

    local active
    active=$(_keys_get "__active__")
    [[ -z "$active" ]] && active="openai"
    if ! _profile_exists "$active"; then
        error "当前激活渠道无效，请先运行: $(basename "$0") switch"
        exit 1
    fi

    step "切换模型 -> ${new_model}（渠道: ${active}）"
    _apply_profile "$active" "$new_model" "" "" "" "0"
}

# ─── configure 命令 ──────────────────────────────────────────────────────────
_configure_interactive() {
    step "配置 Codex CLI"
    info "配置文件: $CONFIG_FILE"
    echo ""
    echo "${BOLD}选择配置方式:${NC}"
    echo "  1) 快速切换渠道（推荐：openai / openrouter / proxy）"
    echo "  2) 仅修改当前渠道模型"
    read -r -p "选择 [1/2, 默认 1]: " choice
    choice=${choice:-1}
    if [[ "$choice" == "2" ]]; then
        read -r -p "模型名称: " m
        [[ -z "$m" ]] && { error "模型不能为空"; exit 1; }
        cmd_model "$m"
    else
        cmd_switch
    fi
}

cmd_configure() {
    if [[ $# -eq 0 ]]; then
        _configure_interactive
        return
    fi

    step "配置 Codex CLI"
    local provider="" model="" api_key="" base_url="" reasoning=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --provider)  provider="${2:-}"; shift 2 ;;
            --model)     model="${2:-}"; shift 2 ;;
            --api-key)   api_key="${2:-}"; shift 2 ;;
            --base-url)  base_url="${2:-}"; shift 2 ;;
            --reasoning) reasoning="${2:-}"; shift 2 ;;
            *)           error "未知选项: $1"; usage; exit 1 ;;
        esac
    done

    [[ -z "$provider" ]] && provider="$(_keys_get "__active__")"
    [[ -z "$provider" ]] && provider="openai"
    if ! _profile_exists "$provider"; then
        error "未知渠道: ${provider}（可用: openai / openrouter / proxy）"
        exit 1
    fi
    _apply_profile "$provider" "$model" "$api_key" "$base_url" "$reasoning"
}

# ─── 安装 / 卸载 ─────────────────────────────────────────────────────────────
cmd_install() {
    step "安装 Codex CLI"

    if command -v codex &>/dev/null; then
        warn "Codex CLI 已安装: $(codex --version 2>/dev/null || echo 'unknown')"
        read -r -p "是否重新安装? [y/N] " answer
        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            info "跳过安装"
            echo ""
            cmd_install_plugins
            echo ""
            cmd_sync
            return 0
        fi
    fi

    if ! command -v node &>/dev/null; then
        error "需要 Node.js 18+。请先安装 Node.js"
        exit 1
    fi
    info "Node.js 版本: $(node --version)"
    info "正在安装 @openai/codex..."
    npm install -g @openai/codex

    if command -v codex &>/dev/null; then
        success "Codex CLI 安装成功: $(codex --version 2>/dev/null || true)"
        info "提示: brew 用户也可用 'brew install --cask codex'"
    else
        error "安装失败，请检查错误信息"
        exit 1
    fi

    echo ""
    cmd_install_plugins
    echo ""
    cmd_sync
}

cmd_uninstall() {
    step "卸载 Codex CLI"
    if ! command -v codex &>/dev/null; then
        warn "Codex CLI 未安装"
    else
        read -r -p "确定要卸载 Codex CLI 吗? [y/N] " answer
        [[ ! "$answer" =~ ^[Yy]$ ]] && { info "取消卸载"; return 0; }
        npm uninstall -g @openai/codex || warn "npm 卸载失败（可能通过 brew 安装，试试: brew uninstall --cask codex）"
    fi
    _remove_rc_source
    command -v codex &>/dev/null && warn "codex 仍在 PATH 中（可能由其他方式安装）" || success "Codex CLI 已卸载"
}

# ─── login 命令 ──────────────────────────────────────────────────────────────
cmd_login() {
    if ! command -v codex &>/dev/null; then
        error "Codex CLI 未安装，请先运行: $(basename "$0") install"
        exit 1
    fi
    step "Codex 登录"
    info "将调用 codex login（浏览器 ChatGPT 登录，或按提示使用 API Key）"
    codex login "$@"
}

# ─── sync 命令 ───────────────────────────────────────────────────────────────
cmd_sync() {
    require_node
    step "同步通用配置到本机 Codex 设置"
    mkdir -p "$CODEX_HOME"

    # 1) config.toml 托管块：若无激活渠道则写入默认 openai
    local active
    active=$(_keys_get "__active__")
    if [[ -z "$active" ]] || ! grep -qF "$MANAGED_BEGIN" "$CONFIG_FILE" 2>/dev/null; then
        info "初始化 config.toml 托管块（默认渠道: openai）"
        local model reasoning
        model=$(_profile_field "$(_profile_file openai)" "model")
        reasoning=$(_profile_field "$(_profile_file openai)" "reasoning_effort")
        printf 'model = "%s"\nmodel_provider = "openai"\nmodel_reasoning_effort = "%s"\n' "$model" "$reasoning" \
            | _write_managed_block
        _keys_set "__active__" "openai"
        success "config.toml 已初始化"
    else
        info "config.toml 已存在托管块（当前渠道: ${active}），跳过。切换请用 switch"
    fi

    # 2) 默认权限与敏感命令规则
    _sync_permission_defaults
    _sync_permission_rules

    # 3) 关闭 features.apps（CLI/Linux 不需要）
    _sync_features_apps_disabled

    # 4) AGENTS.md 语言规则
    local agents_file="$CODEX_HOME/AGENTS.md"
    local template="$SCRIPT_DIR/config/AGENTS.md"
    if [[ -f "$agents_file" ]]; then
        if grep -qF "Always respond in the same language" "$agents_file"; then
            warn "AGENTS.md 语言规则已存在，跳过"
        else
            cp "$agents_file" "${agents_file}.bak.$(date +%Y%m%d-%H%M%S)"
            printf '\n%s\n' "$(cat "$template")" >> "$agents_file"
            success "AGENTS.md 已追加语言规则"
        fi
    else
        cp "$template" "$agents_file"
        success "AGENTS.md 已创建"
    fi

    info "权限规则将在重启 Codex 后生效"
}

# ─── status 命令 ─────────────────────────────────────────────────────────────
cmd_status() {
    step "当前 Codex CLI 配置"

    local active
    active=$(_keys_get "__active__")
    [[ -n "$active" ]] && info "当前渠道: ${BOLD}$active${NC}" || info "当前渠道: 未知（未通过本脚本切换）"

    if [[ -f "$CONFIG_FILE" ]]; then
        echo ""
        info "config.toml 托管块："
        if grep -qF "$MANAGED_BEGIN" "$CONFIG_FILE"; then
            awk -v b="$MANAGED_BEGIN" -v e="$MANAGED_END" '
                $0==b {show=1; next} $0==e {show=0} show {print "  " $0}
            ' "$CONFIG_FILE"
        else
            warn "  未找到托管块，运行 sync 或 switch 生成"
        fi
    else
        warn "config.toml 不存在: ${CONFIG_FILE}（运行 sync 初始化）"
    fi

    if [[ -f "$KEYS_FILE" ]] && command -v node &>/dev/null; then
        echo ""
        info "已保存 API Key 的渠道:"
        node -e "
            try {
                const k = JSON.parse(require('fs').readFileSync('$KEYS_FILE','utf8'));
                let any = false;
                for (const [name, v] of Object.entries(k)) {
                    if (name.startsWith('__') || name.includes('__')) continue;
                    any = true;
                    const masked = typeof v === 'string' && v.length > 12 ? v.slice(0,12)+'...' : v;
                    console.log('  ' + name + ': ' + masked);
                }
                if (!any) console.log('  （无）');
            } catch(e) {}
        " 2>/dev/null || true
    fi

    echo ""
    info "Codex CLI 版本: $(codex --version 2>/dev/null || echo '未安装')"
    [[ -f "$ENV_FILE" ]] && info "Key 环境脚本: ${ENV_FILE}（当前终端可 source 生效）"
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
        login)           cmd_login "$@" ;;
        -h|--help|help)  usage; exit 0 ;;
        *)               error "未知命令: $command"; usage; exit 1 ;;
    esac
}

main "$@"
