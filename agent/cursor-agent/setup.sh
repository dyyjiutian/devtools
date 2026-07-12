#!/usr/bin/env bash
# Cursor Agent CLI 安装与配置脚本
# 用途：安装、卸载，并同步本机 ~/.cursor/cli-config.json 权限配置
# 不涉及第三方模型渠道；使用 Cursor 自身账号与模型。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_CONFIG="$SCRIPT_DIR/config/cli-config.json"
CURSOR_DIR="${CURSOR_CONFIG_DIR:-$HOME/.cursor}"
CONFIG_FILE="$CURSOR_DIR/cli-config.json"
INSTALL_DIR="$HOME/.local/share/cursor-agent"
BIN_DIR="$HOME/.local/bin"

# 敏感 Shell 命令：不写入 allow，执行前由 Cursor 请求确认（非永久禁止）
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
  install     安装 Cursor Agent CLI
  uninstall   卸载 Cursor Agent CLI（保留 ~/.cursor 配置）
  sync        将 config/cli-config.json 的权限策略合并到本机
  status      查看安装状态与当前权限摘要
  login       使用 agent login 登录 Cursor 账号
  update      更新 Cursor Agent CLI 到最新版

${BOLD}权限策略 (sync):${NC}
  - approvalMode = allowlist；sandbox 默认关闭（接近 Codex danger-full-access）
  - 常用开发命令、Read(**)、Write(**) 写入 allow，自动通过
  - rm / scp / sftp / rsync / curl / wget / nc / ncat / socat 不进 allow，每次确认
  - 不使用 deny 永久禁止敏感命令（与 Codex prompt 策略对齐）
  - 合并时保留本机已有 allow/deny 条目，并强制剔除敏感 Shell 的 allow
  - 不改动 model / auth / privacy 等 Cursor 自身托管字段

${BOLD}示例:${NC}
  $(basename "$0") install
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
            [[ ! "$answer" =~ ^[Yy]$ ]] && { info "跳过安装"; _ensure_path_hint; return 0; }
        else
            info "非交互环境，跳过重新安装"
            _ensure_path_hint
            return 0
        fi
    fi

    info "通过官方安装脚本安装..."
    curl -fsS https://cursor.com/install | bash

    bin=$(_agent_bin)
    if [[ -n "$bin" ]]; then
        success "Cursor Agent 安装成功: $($bin --version 2>/dev/null || true)"
        _ensure_path_hint
        info "下一步: ./$(basename "$0") sync  然后  ./$(basename "$0") login"
    else
        error "安装后未找到 agent / cursor-agent，请检查 $BIN_DIR 是否在 PATH 中"
        exit 1
    fi
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
        deny: dedup(tplPerm.deny, exPerm.deny),
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
    info "敏感命令（每次确认）: ${SENSITIVE_SHELL[*]}"
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
console.log('  approvalMode : ' + (s.approvalMode || '(默认)'));
console.log('  sandbox.mode : ' + ((s.sandbox && s.sandbox.mode) || '(默认)'));
console.log('  allow 条目   : ' + (perm.allow || []).length);
console.log('  deny 条目    : ' + (perm.deny || []).length);
if (allowSensitive.length) {
    console.log('  [WARN] allow 中仍含敏感命令: ' + allowSensitive.join(', '));
    console.log('         运行 sync 可自动剔除');
} else {
    console.log('  敏感命令    : 未在 allow 中（执行前确认）');
}
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
        install)        cmd_install "$@" ;;
        uninstall)      cmd_uninstall "$@" ;;
        sync)           cmd_sync "$@" ;;
        status)         cmd_status "$@" ;;
        login)          cmd_login "$@" ;;
        update)         cmd_update "$@" ;;
        -h|--help|help) usage; exit 0 ;;
        *)              error "未知命令: $command"; usage; exit 1 ;;
    esac
}

main "$@"
