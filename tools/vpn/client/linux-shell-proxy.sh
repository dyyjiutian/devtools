#!/usr/bin/env bash
# =============================================================================
# Linux 终端代理开关：为当前用户写入 shell 环境变量，指向本机 Xray HTTP/SOCKS。
# 需已运行 client/setup.sh，默认 SOCKS 10808、HTTP 10809。
#
#   ./linux-shell-proxy.sh on
#   ./linux-shell-proxy.sh off
#   ./linux-shell-proxy.sh status
#
# 当前终端立即生效（脚本在子 shell 中运行，不会自动影响已打开的终端）:
#   source ./linux-shell-proxy.sh on
#   eval "$(./linux-shell-proxy.sh on --emit)"
#
# 环境变量（可选，覆盖默认）:
#   VPN_SOCKS_HOST     默认 127.0.0.1
#   VPN_SOCKS_PORT     默认 10808
#   VPN_HTTP_HOST      默认 127.0.0.1
#   VPN_HTTP_PORT      默认 10809
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

PROXY_DIR="${HOME}/.config/vpn"
PROXY_ENV="${PROXY_DIR}/proxy.env"
MARKER_BEGIN="# >>> vpn-shell-proxy managed >>>"
MARKER_END="# <<< vpn-shell-proxy managed <<<"
HOOK_LINE='[ -f "${HOME}/.config/vpn/proxy.env" ] && . "${HOME}/.config/vpn/proxy.env"'

SOCKS_HOST="${VPN_SOCKS_HOST:-127.0.0.1}"
SOCKS_PORT="${VPN_SOCKS_PORT:-10808}"
HTTP_HOST="${VPN_HTTP_HOST:-127.0.0.1}"
HTTP_PORT="${VPN_HTTP_PORT:-10809}"

ACTION=""
EMIT=false

usage() {
    cat <<'HELP'
用法:
  ./linux-shell-proxy.sh on
  ./linux-shell-proxy.sh off
  ./linux-shell-proxy.sh status

当前终端立即生效:
  source ./linux-shell-proxy.sh on
  eval "$(./linux-shell-proxy.sh on --emit)"

环境变量（可选）: VPN_SOCKS_HOST, VPN_SOCKS_PORT, VPN_HTTP_HOST, VPN_HTTP_PORT
HELP
    exit "${1:-0}"
}

for arg in "$@"; do
    case $arg in
        on|off|status) ACTION="$arg" ;;
        --emit) EMIT=true ;;
        -h|--help) usage 0 ;;
        *) error "未知参数: $arg"; usage 1 ;;
    esac
done

if [[ -z "$ACTION" ]]; then
    error "请指定动作: on | off | status"
    usage 1
fi

port_listening() {
    local port="$1"
    if command -v ss &>/dev/null; then
        ss -tln | grep -q ":${port} "
        return $?
    fi
    if command -v lsof &>/dev/null; then
        lsof -iTCP:"${port}" -sTCP:LISTEN &>/dev/null
        return $?
    fi
    return 0
}

ensure_shell_hook() {
    local rc="$1"
    [[ -f "$rc" ]] || return 0
    if grep -qF "$MARKER_BEGIN" "$rc" 2>/dev/null; then
        return 0
    fi
    {
        echo ""
        echo "$MARKER_BEGIN"
        echo "$HOOK_LINE"
        echo "$MARKER_END"
    } >> "$rc"
    info "已写入 shell 钩子: ${rc}"
}

remove_shell_hook() {
    local rc="$1"
    [[ -f "$rc" ]] || return 0
    if ! grep -qF "$MARKER_BEGIN" "$rc" 2>/dev/null; then
        return 0
    fi
    local tmp
    tmp=$(mktemp)
    awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" '
        $0 == begin { skip=1; next }
        $0 == end { skip=0; next }
        !skip { print }
    ' "$rc" > "$tmp"
    mv "$tmp" "$rc"
    info "已移除 shell 钩子: ${rc}"
}

write_proxy_env() {
    mkdir -p "$PROXY_DIR"
    cat > "$PROXY_ENV" <<EOF
# VPN shell proxy — managed by linux-shell-proxy.sh
export http_proxy="http://${HTTP_HOST}:${HTTP_PORT}"
export https_proxy="http://${HTTP_HOST}:${HTTP_PORT}"
export HTTP_PROXY="http://${HTTP_HOST}:${HTTP_PORT}"
export HTTPS_PROXY="http://${HTTP_HOST}:${HTTP_PORT}"
export all_proxy="socks5h://${SOCKS_HOST}:${SOCKS_PORT}"
export ALL_PROXY="socks5h://${SOCKS_HOST}:${SOCKS_PORT}"
export no_proxy="127.0.0.1,localhost"
export NO_PROXY="127.0.0.1,localhost"
EOF
    chmod 600 "$PROXY_ENV"
}

emit_exports() {
    cat "$PROXY_ENV" | grep -E '^export '
}

apply_to_current_shell() {
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        # shellcheck disable=SC1090
        source "$PROXY_ENV"
        success "当前 shell 已加载代理环境变量"
    fi
}

clear_current_shell() {
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
        unset all_proxy ALL_PROXY no_proxy NO_PROXY
        success "当前 shell 已清除代理环境变量"
    fi
}

proxy_on() {
    if ! port_listening "$HTTP_PORT"; then
        warn "HTTP 代理端口 ${HTTP_HOST}:${HTTP_PORT} 未监听，请先运行 setup.sh 或 systemctl start xray-client"
    fi
    if ! port_listening "$SOCKS_PORT"; then
        warn "SOCKS 代理端口 ${SOCKS_HOST}:${SOCKS_PORT} 未监听，请先运行 setup.sh 或 systemctl start xray-client"
    fi

    write_proxy_env
    ensure_shell_hook "${HOME}/.bashrc"
    [[ -f "${HOME}/.zshrc" ]] && ensure_shell_hook "${HOME}/.zshrc"
    [[ -f "${HOME}/.profile" ]] && ensure_shell_hook "${HOME}/.profile"

    if $EMIT; then
        emit_exports
        return 0
    fi

    success "终端代理已开启（新开的终端自动生效）"
    info "HTTP/HTTPS → http://${HTTP_HOST}:${HTTP_PORT}"
    info "ALL_PROXY  → socks5h://${SOCKS_HOST}:${SOCKS_PORT}"
    info "配置文件   → ${PROXY_ENV}"

    apply_to_current_shell
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        echo ""
        warn "当前已打开的终端需手动加载一次:"
        echo "  source ${PROXY_ENV}"
        echo "  或: eval \"\$(./linux-shell-proxy.sh on --emit)\""
    fi

    if port_listening "$HTTP_PORT"; then
        if curl -x "http://${HTTP_HOST}:${HTTP_PORT}" -fsSL --connect-timeout 10 \
            -o /dev/null https://api4.ipify.org 2>/dev/null; then
            success "代理连通性检查通过（api4.ipify.org）"
        else
            warn "代理端口在监听，但连通性测试未通过，请检查 xray-client 日志"
        fi
    fi
}

proxy_off() {
    rm -f "$PROXY_ENV"
    success "终端代理已关闭（新开的终端将直连）"

    clear_current_shell
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        echo ""
        info "当前已打开的终端请执行:"
        echo "  unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY"
    fi
}

proxy_status() {
    echo -e "${BOLD}配置文件${RESET}"
    if [[ -f "$PROXY_ENV" ]]; then
        echo "  状态: ${GREEN}已开启${RESET}"
        echo "  路径: ${PROXY_ENV}"
        echo ""
        echo -e "${BOLD}代理变量（配置文件）${RESET}"
        sed 's/^/  /' "$PROXY_ENV" | grep -v '^  #' || true
    else
        echo "  状态: ${YELLOW}已关闭${RESET}（${PROXY_ENV} 不存在）"
    fi

    echo ""
    echo -e "${BOLD}当前 shell 环境变量${RESET}"
    for v in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY; do
        if [[ -n "${!v:-}" ]]; then
            echo "  ${v}=${!v}"
        fi
    done
    if [[ -z "${http_proxy:-}${https_proxy:-}${HTTP_PROXY:-}${HTTPS_PROXY:-}${all_proxy:-}${ALL_PROXY:-}" ]]; then
        echo "  （未设置）"
    fi

    echo ""
    echo -e "${BOLD}Xray 本地端口${RESET}"
    if port_listening "$HTTP_PORT"; then
        echo "  HTTP  ${HTTP_HOST}:${HTTP_PORT} ${GREEN}监听中${RESET}"
    else
        echo "  HTTP  ${HTTP_HOST}:${HTTP_PORT} ${RED}未监听${RESET}"
    fi
    if port_listening "$SOCKS_PORT"; then
        echo "  SOCKS ${SOCKS_HOST}:${SOCKS_PORT} ${GREEN}监听中${RESET}"
    else
        echo "  SOCKS ${SOCKS_HOST}:${SOCKS_PORT} ${RED}未监听${RESET}"
    fi

    echo ""
    echo -e "${BOLD}Shell 钩子${RESET}"
    for rc in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.profile"; do
        if [[ -f "$rc" ]] && grep -qF "$MARKER_BEGIN" "$rc" 2>/dev/null; then
            echo "  ${rc}: 已安装"
        fi
    done
}

case "$ACTION" in
    on)  proxy_on ;;
    off) proxy_off ;;
    status) proxy_status ;;
esac
