#!/usr/bin/env bash
# Cursor Agent CLI 安装与配置脚本
# 用途：安装、卸载，同步权限，安装推荐 skills / marketplace
# 不涉及第三方模型渠道；使用 Cursor 自身账号与模型。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_CONFIG="$SCRIPT_DIR/config/cli-config.json"
CURSOR_DIR="${CURSOR_CONFIG_DIR:-$HOME/.cursor}"
CONFIG_FILE="$CURSOR_DIR/cli-config.json"
INSTALL_DIR="$HOME/.local/share/cursor-agent"
BIN_DIR="$HOME/.local/bin"
SKILLS_DIR="${CURSOR_SKILLS_DIR:-$CURSOR_DIR/skills}"
SKILL_CACHE_DIR="${CURSOR_SKILL_CACHE_DIR:-$CURSOR_DIR/.devtools-skill-cache}"
# Prefer sibling path; fall back to REPO_ROOT (set by module tests / monorepo runners).
if [[ -f "$SCRIPT_DIR/../cookbook/setup.sh" ]]; then
    COOKBOOK_SETUP="$(cd "$SCRIPT_DIR/../cookbook" && pwd)/setup.sh"
elif [[ -n "${REPO_ROOT:-}" && -f "$REPO_ROOT/agents/cookbook/setup.sh" ]]; then
    COOKBOOK_SETUP="$REPO_ROOT/agents/cookbook/setup.sh"
else
    COOKBOOK_SETUP="$SCRIPT_DIR/../cookbook/setup.sh"
fi

# 敏感 Shell：强制从 allow 剔除并写入 deny（永久拒绝，对齐 Claude deny 档位）
SENSITIVE_SHELL=(
    "Shell(rm)"
    "Shell(scp)"
    "Shell(sftp)"
    "Shell(rsync)"
    "Shell(curl)"
    "Shell(wget)"
    "Shell(nc)"
    "Shell(ncat)"
    "Shell(socat)"
)

# 核心 marketplace（agent plugin marketplace add）
CORE_MARKETPLACES=(
    "https://github.com/obra/superpowers"
)

# 推荐 skills：name|git_url|subdir（subdir 相对仓库根，含 SKILL.md）
RECOMMENDED_SKILLS=(
    "brainstorming|https://github.com/obra/superpowers|skills/brainstorming"
    "systematic-debugging|https://github.com/obra/superpowers|skills/systematic-debugging"
    "test-driven-development|https://github.com/obra/superpowers|skills/test-driven-development"
    "verification-before-completion|https://github.com/obra/superpowers|skills/verification-before-completion"
    "writing-plans|https://github.com/obra/superpowers|skills/writing-plans"
)

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

require_node() {
    if ! command -v node &>/dev/null; then
        error "需要 Node.js 读写 JSON 配置。请先安装 Node.js"
        exit 1
    fi
}

_agent_bin() {
    if command -v agent &>/dev/null; then
        echo "agent"
    elif command -v cursor-agent &>/dev/null; then
        echo "cursor-agent"
    else
        echo ""
    fi
}

_ensure_path_hint() {
    case ":$PATH:" in
        *":$BIN_DIR:"*) return 0 ;;
    esac
    warn "$BIN_DIR 不在 PATH 中"
    info "可在 shell rc 中添加: export PATH=\"\$HOME/.local/bin:\$PATH\""
}

# ─── 用法说明 ────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF

${BOLD}用法:${NC}
  $(basename "$0") <command> [options]

${BOLD}命令:${NC}
  install          安装 Cursor Agent CLI + 推荐 skills/marketplace + sync
  install-plugins  安装推荐 marketplace 与 skills
  uninstall        卸载 Cursor Agent CLI（保留 ~/.cursor 配置）
  sync             将 config/cli-config.json 的权限策略合并到本机
  status           查看安装状态与当前权限摘要
  login            使用 agent login 登录 Cursor 账号
  update           更新 Cursor Agent CLI 到最新版

${BOLD}install-plugins 用法:${NC}
  ./$(basename "$0") install-plugins              安装全部核心 marketplace + cookbook + 推荐 skills
  ./$(basename "$0") install-plugins --list       打印可安装列表
  ./$(basename "$0") install-plugins <name>...    只安装指定项（marketplace / skill / cookbook）

${BOLD}插件/skills 列表:${NC}
  核心 marketplace: superpowers (obra/superpowers)
  核心 skills:      cookbook git-submit（via agents/cookbook）
  推荐 skills:      brainstorming  systematic-debugging  test-driven-development
                    verification-before-completion  writing-plans

${BOLD}权限策略 (sync):${NC}
  - approvalMode = allowlist；sandbox 默认关闭
  - allow: Shell(*) / Read(**) / Write(**) / WebFetch(*) / Mcp(*) — 大部分操作免审批
  - deny: rm / scp / sftp / rsync / curl / wget / nc / ncat / socat — 永久拒绝
  - 合并时保留本机已有 allow/deny，并强制敏感项从 allow 剔除、写入 deny
  - 不改动 model / auth / privacy 等 Cursor 自身托管字段

${BOLD}示例:${NC}
  $(basename "$0") install
  $(basename "$0") install-plugins --list
  $(basename "$0") install-plugins git-submit brainstorming
  $(basename "$0") sync
  $(basename "$0") status
  $(basename "$0") login

EOF
}

# ─── 安装 / 卸载 / 更新 ───────────────────────────────────────────────────────
cmd_install() {
    step "安装 Cursor Agent CLI"

    local bin
    bin=$(_agent_bin)
    if [[ -n "$bin" ]]; then
        warn "Cursor Agent 已安装: $($bin --version 2>/dev/null || echo 'unknown')"
        if [[ -t 0 ]]; then
            read -r -p "是否重新安装? [y/N] " answer
            if [[ ! "$answer" =~ ^[Yy]$ ]]; then
                info "跳过安装"
                _ensure_path_hint
                echo ""
                cmd_install_plugins
                echo ""
                cmd_sync
                return 0
            fi
        else
            info "非交互环境，跳过重新安装"
            _ensure_path_hint
            echo ""
            cmd_install_plugins
            echo ""
            cmd_sync
            return 0
        fi
    fi

    info "通过官方安装脚本安装..."
    curl -fsS https://cursor.com/install | bash

    bin=$(_agent_bin)
    if [[ -n "$bin" ]]; then
        success "Cursor Agent 安装成功: $($bin --version 2>/dev/null || true)"
        _ensure_path_hint
    else
        error "安装后未找到 agent / cursor-agent，请检查 $BIN_DIR 是否在 PATH 中"
        exit 1
    fi

    echo ""
    cmd_install_plugins
    echo ""
    cmd_sync
}

cmd_uninstall() {
    step "卸载 Cursor Agent CLI"

    local bin
    bin=$(_agent_bin)
    if [[ -z "$bin" && ! -d "$INSTALL_DIR" && ! -e "$BIN_DIR/agent" && ! -e "$BIN_DIR/cursor-agent" ]]; then
        warn "Cursor Agent 未安装"
        return 0
    fi

    if [[ -t 0 ]]; then
        read -r -p "确定卸载 Cursor Agent CLI 吗（保留 ~/.cursor 配置）? [y/N] " answer
        [[ ! "$answer" =~ ^[Yy]$ ]] && { info "取消卸载"; return 0; }
    fi

    rm -f "$BIN_DIR/agent" "$BIN_DIR/cursor-agent"
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
    fi

    if command -v agent &>/dev/null || command -v cursor-agent &>/dev/null; then
        warn "PATH 中仍能找到 agent（可能由其他方式安装）"
    else
        success "Cursor Agent CLI 已卸载"
    fi
    info "配置文件保留在: $CONFIG_FILE"
}

cmd_update() {
    step "更新 Cursor Agent CLI"
    local bin
    bin=$(_agent_bin)
    if [[ -z "$bin" ]]; then
        error "Cursor Agent 未安装，请先运行: $(basename "$0") install"
        exit 1
    fi
    "$bin" update
    success "更新完成: $($bin --version 2>/dev/null || true)"
}

cmd_login() {
    local bin
    bin=$(_agent_bin)
    if [[ -z "$bin" ]]; then
        error "Cursor Agent 未安装，请先运行: $(basename "$0") install"
        exit 1
    fi
    step "Cursor Agent 登录"
    info "将调用 $bin login（浏览器登录 Cursor 账号）"
    "$bin" login "$@"
}

# ─── marketplace / skills ─────────────────────────────────────────────────────
_marketplace_name_from_url() {
    local url="$1"
    local base
    base="${url%/}"
    base="${base%.git}"
    basename "$base"
}

_list_plugins() {
    local entry name url subdir mp
    echo "${BOLD}可安装项:${NC}"
    echo ""
    printf "  %-8s %-36s %s\n" "级别" "短名" "说明"
    printf "  %-8s %-36s %s\n" "----" "----" "----"
    for mp in "${CORE_MARKETPLACES[@]}"; do
        printf "  %-8s %-36s %s\n" "核心" "$(_marketplace_name_from_url "$mp")" "marketplace: $mp"
    done
    printf "  %-8s %-36s %s\n" "核心" "cookbook" "agents/cookbook skills → ~/.cursor/skills"
    printf "  %-8s %-36s %s\n" "核心" "git-submit" "cookbook skill（含在 cookbook sync）"
    for entry in "${RECOMMENDED_SKILLS[@]}"; do
        IFS='|' read -r name url subdir <<<"$entry"
        printf "  %-8s %-36s %s\n" "推荐" "$name" "git: $url ($subdir)"
    done
}

_marketplace_listed() {
    local url="$1"
    local bin name
    bin=$(_agent_bin)
    [[ -n "$bin" ]] || return 1
    name="$(_marketplace_name_from_url "$url")"
    "$bin" plugin marketplace list 2>/dev/null | grep -qiE "(^|[[:space:]])${name}([[:space:]]|$)|${url}"
}

_ensure_marketplace() {
    local url="$1"
    local bin
    bin=$(_agent_bin)
    if [[ -z "$bin" ]]; then
        warn "Cursor Agent 未安装，跳过 marketplace: $url"
        return 0
    fi
    if _marketplace_listed "$url"; then
        info "marketplace 已存在，跳过: $(_marketplace_name_from_url "$url")"
        return 0
    fi
    info "添加 marketplace: $url"
    if "$bin" plugin marketplace add "$url" >/dev/null 2>&1; then
        success "已添加 marketplace: $(_marketplace_name_from_url "$url")"
    else
        warn "marketplace 添加失败（可能需登录或网络）: $url"
    fi
}

_sync_cookbook() {
    if [[ ! -x "$COOKBOOK_SETUP" && ! -f "$COOKBOOK_SETUP" ]]; then
        warn "未找到 cookbook setup: $COOKBOOK_SETUP"
        return 0
    fi
    info "同步 cookbook skills → cursor"
    if bash "$COOKBOOK_SETUP" sync --target cursor; then
        success "cookbook skills 已同步"
    else
        warn "cookbook sync 失败"
    fi
}

_repo_cache_dir() {
    local url="$1"
    local key
    key="$(printf '%s' "$url" | sed 's#[^a-zA-Z0-9._-]#_#g')"
    printf '%s\n' "$SKILL_CACHE_DIR/$key"
}

_ensure_repo_cache() {
    local url="$1"
    local cache
    cache="$(_repo_cache_dir "$url")"
    mkdir -p "$SKILL_CACHE_DIR"
    # Messages go to stderr so callers can capture the cache path from stdout.
    if [[ -d "$cache/.git" ]]; then
        info "更新 skill 缓存: $url" >&2
        if ! git -C "$cache" pull --ff-only >/dev/null 2>&1; then
            warn "git pull 失败，沿用现有缓存: $cache" >&2
        fi
        printf '%s\n' "$cache"
        return 0
    fi
    if [[ -e "$cache" ]]; then
        warn "缓存路径存在但不是 git 仓库，跳过: $cache" >&2
        return 1
    fi
    info "克隆 skill 仓库: $url" >&2
    if git clone --depth 1 "$url" "$cache" >/dev/null 2>&1; then
        printf '%s\n' "$cache"
        return 0
    fi
    warn "克隆失败（网络或权限）: $url" >&2
    return 1
}

_link_skill() {
    local name="$1"
    local src="$2"
    local dest="$SKILLS_DIR/$name"

    if [[ ! -f "$src/SKILL.md" ]]; then
        warn "源目录缺少 SKILL.md，跳过: $src"
        return 0
    fi

    mkdir -p "$SKILLS_DIR"

    if [[ -L "$dest" ]]; then
        local resolved
        resolved="$(readlink "$dest" 2>/dev/null || true)"
        if [[ "$resolved" == "$src" ]]; then
            info "已链接，跳过: $dest"
            return 0
        fi
        warn "替换已有符号链接: $dest"
        rm -f "$dest"
    elif [[ -e "$dest" ]]; then
        warn "目标已存在，跳过（避免覆盖）: $dest"
        return 0
    fi

    ln -s "$src" "$dest"
    success "已链接 skill: $dest -> $src"
}

_install_recommended_skill() {
    local entry="$1"
    local name url subdir cache src
    IFS='|' read -r name url subdir <<<"$entry"
    cache="$(_ensure_repo_cache "$url")" || return 0
    src="$cache/$subdir"
    _link_skill "$name" "$src"
}

_skill_entry_by_name() {
    local want="$1" entry name
    for entry in "${RECOMMENDED_SKILLS[@]}"; do
        IFS='|' read -r name _ _ <<<"$entry"
        [[ "$name" == "$want" ]] && { printf '%s\n' "$entry"; return 0; }
    done
    return 1
}

_marketplace_url_by_name() {
    local want="$1" url
    for url in "${CORE_MARKETPLACES[@]}"; do
        [[ "$(_marketplace_name_from_url "$url")" == "$want" ]] && { printf '%s\n' "$url"; return 0; }
    done
    return 1
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

    step "安装 Cursor Agent skills / marketplace"

    local install_all=0
    local do_cookbook=0
    local -a mps=()
    local -a skills=()

    if [[ ${#wants[@]} -eq 0 ]]; then
        install_all=1
        do_cookbook=1
        mps=("${CORE_MARKETPLACES[@]}")
        skills=("${RECOMMENDED_SKILLS[@]}")
    else
        local want url entry
        for want in "${wants[@]}"; do
            case "$want" in
                cookbook|git-submit)
                    do_cookbook=1
                    ;;
                *)
                    if url="$(_marketplace_url_by_name "$want")"; then
                        mps+=("$url")
                    elif entry="$(_skill_entry_by_name "$want")"; then
                        skills+=("$entry")
                    else
                        error "未知项: $want（可用: $(basename "$0") install-plugins --list）"
                        exit 1
                    fi
                    ;;
            esac
        done
    fi

    local mp
    for mp in "${mps[@]+"${mps[@]}"}"; do
        [[ -n "${mp:-}" ]] || continue
        _ensure_marketplace "$mp"
    done

    if [[ "$do_cookbook" -eq 1 || "$install_all" -eq 1 ]]; then
        echo ""
        _sync_cookbook
    fi

    if [[ ${#skills[@]} -gt 0 ]]; then
        echo ""
        info "安装推荐 skills..."
        local sk
        for sk in "${skills[@]}"; do
            _install_recommended_skill "$sk"
        done
    fi

    echo ""
    success "skills / marketplace 安装完成"
    info "IDE 内的正式 plugin 安装请在 Cursor Customize → Plugins 中完成"
}

# ─── sync：合并权限到本机 cli-config.json ─────────────────────────────────────
cmd_sync() {
    require_node
    step "同步权限配置到本机 Cursor CLI"

    [[ -f "$TEMPLATE_CONFIG" ]] || { error "模板不存在: $TEMPLATE_CONFIG"; exit 1; }
    mkdir -p "$CURSOR_DIR"

    CURSOR_AGENT_TEMPLATE="$TEMPLATE_CONFIG" \
    CURSOR_AGENT_CONFIG="$CONFIG_FILE" \
    CURSOR_AGENT_SENSITIVE="$(printf '%s\n' "${SENSITIVE_SHELL[@]}")" \
    node <<'EOF'
const fs = require('fs');
const template = JSON.parse(fs.readFileSync(process.env.CURSOR_AGENT_TEMPLATE, 'utf8'));
const configPath = process.env.CURSOR_AGENT_CONFIG;
const sensitive = (process.env.CURSOR_AGENT_SENSITIVE || '').split(/\n/).filter(Boolean);

let existing = {};
if (fs.existsSync(configPath)) {
    try { existing = JSON.parse(fs.readFileSync(configPath, 'utf8')); }
    catch (e) {
        console.error('现有配置解析失败，将基于模板重建 permissions 相关字段');
        existing = {};
    }
}

const dedup = (a, b) => [...new Set([...(a || []), ...(b || [])])];
const stripSensitive = (list) => (list || []).filter((p) => !sensitive.includes(p));

const tplPerm = template.permissions || { allow: [], deny: [] };
const exPerm = existing.permissions || { allow: [], deny: [] };

const merged = {
    ...existing,
    version: existing.version || template.version || 1,
    approvalMode: template.approvalMode || existing.approvalMode || 'allowlist',
    sandbox: {
        ...(existing.sandbox || {}),
        ...(template.sandbox || {}),
    },
    permissions: {
        allow: stripSensitive(dedup(tplPerm.allow, exPerm.allow)),
        deny: dedup(dedup(tplPerm.deny, exPerm.deny), sensitive),
    },
};

if (!merged.editor) {
    merged.editor = { vimMode: false };
}

if (fs.existsSync(configPath)) {
    const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
    fs.copyFileSync(configPath, configPath + '.bak.' + ts);
    console.log('已备份: ' + configPath + '.bak.' + ts);
}

fs.writeFileSync(configPath, JSON.stringify(merged, null, 2) + '\n');
console.log('已更新: ' + configPath);
console.log('allow: ' + merged.permissions.allow.length + ' 条');
console.log('deny:  ' + merged.permissions.deny.length + ' 条');
console.log('approvalMode: ' + merged.approvalMode);
console.log('sandbox.mode: ' + (merged.sandbox && merged.sandbox.mode));
EOF

    success "权限配置同步完成"
    info "敏感命令（deny）: ${SENSITIVE_SHELL[*]}"
    info "重启 Cursor Agent CLI 后生效"
}

# ─── status ───────────────────────────────────────────────────────────────────
cmd_status() {
    step "当前 Cursor Agent 配置"

    local bin
    bin=$(_agent_bin)
    if [[ -n "$bin" ]]; then
        info "CLI 版本: $($bin --version 2>/dev/null || echo 'unknown')"
        info "命令路径: $(command -v "$bin")"
    else
        warn "Cursor Agent 未安装（或未在 PATH 中）"
    fi

    if [[ ! -f "$CONFIG_FILE" ]]; then
        warn "配置文件不存在: $CONFIG_FILE（运行 sync 初始化）"
        return 0
    fi

    require_node
    echo ""
    info "配置文件: $CONFIG_FILE"
    CURSOR_AGENT_CONFIG="$CONFIG_FILE" \
    CURSOR_AGENT_SENSITIVE="$(printf '%s\n' "${SENSITIVE_SHELL[@]}")" \
    node <<'EOF'
const fs = require('fs');
const s = JSON.parse(fs.readFileSync(process.env.CURSOR_AGENT_CONFIG, 'utf8'));
const perm = s.permissions || { allow: [], deny: [] };
const sensitive = (process.env.CURSOR_AGENT_SENSITIVE || '').split(/\n/).filter(Boolean);
const allowSensitive = (perm.allow || []).filter((p) => sensitive.includes(p));
const denySensitive = sensitive.filter((p) => (perm.deny || []).includes(p));
console.log('  approvalMode : ' + (s.approvalMode || '(默认)'));
console.log('  sandbox.mode : ' + ((s.sandbox && s.sandbox.mode) || '(默认)'));
console.log('  allow 条目   : ' + (perm.allow || []).length);
console.log('  deny 条目    : ' + (perm.deny || []).length);
console.log('  Shell(*)     : ' + ((perm.allow || []).includes('Shell(*)') ? 'yes' : 'no'));
if (allowSensitive.length) {
    console.log('  [WARN] allow 中仍含敏感命令: ' + allowSensitive.join(', '));
    console.log('         运行 sync 可自动剔除');
} else {
    console.log('  敏感命令 allow: 无');
}
console.log('  敏感命令 deny: ' + denySensitive.length + '/' + sensitive.length);
EOF

    if [[ -n "$bin" ]]; then
        echo ""
        "$bin" status 2>/dev/null || "$bin" whoami 2>/dev/null || true
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
        status)          cmd_status "$@" ;;
        login)           cmd_login "$@" ;;
        update)          cmd_update "$@" ;;
        -h|--help|help)  usage; exit 0 ;;
        *)               error "未知命令: $command"; usage; exit 1 ;;
    esac
}

main "$@"
