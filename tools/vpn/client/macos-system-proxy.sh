#!/usr/bin/env bash
# =============================================================================
# macOS 系统代理开关：将「当前网络服务」的 SOCKS / HTTP / HTTPS 代理指向本机 Xray。
# 需已运行 client/setup.sh，默认 SOCKS 10808、HTTP 10809。
#
#   ./macos-system-proxy.sh on [--service=Wi-Fi]
#   ./macos-system-proxy.sh off [--service=Wi-Fi]
#   ./macos-system-proxy.sh status [--service=Wi-Fi]
#   ./macos-system-proxy.sh list-services
#
# 环境变量（可选，覆盖默认）:
#   VPN_PROXY_SERVICE  网络服务名，默认 Wi-Fi
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

usage() {
    cat <<'HELP'
用法:
  ./macos-system-proxy.sh on [--service=Wi-Fi]
  ./macos-system-proxy.sh off [--service=Wi-Fi]
  ./macos-system-proxy.sh status [--service=Wi-Fi]
  ./macos-system-proxy.sh list-services

环境变量（可选）: VPN_PROXY_SERVICE, VPN_SOCKS_HOST, VPN_SOCKS_PORT,
                  VPN_HTTP_HOST, VPN_HTTP_PORT
HELP
    exit "${1:-0}"
}

if [[ "$(uname)" != "Darwin" ]]; then
    error "本脚本仅支持 macOS。"
    exit 1
fi

SERVICE="${VPN_PROXY_SERVICE:-Wi-Fi}"
SOCKS_HOST="${VPN_SOCKS_HOST:-127.0.0.1}"
SOCKS_PORT="${VPN_SOCKS_PORT:-10808}"
HTTP_HOST="${VPN_HTTP_HOST:-127.0.0.1}"
HTTP_PORT="${VPN_HTTP_PORT:-10809}"

ACTION=""
for arg in "$@"; do
    case $arg in
        on|off|status|list-services) ACTION="$arg" ;;
        --service=*) SERVICE="${arg#*=}" ;;
        -h|--help) usage 0 ;;
        *) error "未知参数: $arg"; usage 1 ;;
    esac
done

if [[ -z "$ACTION" ]]; then
    error "请指定动作: on | off | status | list-services"
    usage 1
fi

proxy_on() {
    info "网络服务: ${SERVICE}"
    info "SOCKS ${SOCKS_HOST}:${SOCKS_PORT}；HTTP/HTTPS ${HTTP_HOST}:${HTTP_PORT}"
    sudo networksetup -setsocksfirewallproxy "$SERVICE" "$SOCKS_HOST" "$SOCKS_PORT" off
    sudo networksetup -setsocksfirewallproxystate "$SERVICE" on
    sudo networksetup -setwebproxy "$SERVICE" "$HTTP_HOST" "$HTTP_PORT"
    sudo networksetup -setsecurewebproxy "$SERVICE" "$HTTP_HOST" "$HTTP_PORT"
    sudo networksetup -setwebproxystate "$SERVICE" on
    sudo networksetup -setsecurewebproxystate "$SERVICE" on
    success "系统代理已开启（SOCKS + HTTP + HTTPS）"
    warn "关闭前请保持本机 Xray 在 ${SOCKS_PORT}/${HTTP_PORT} 监听，否则整机可能无法上网"
}

proxy_off() {
    info "网络服务: ${SERVICE}"
    sudo networksetup -setsocksfirewallproxystate "$SERVICE" off
    sudo networksetup -setwebproxystate "$SERVICE" off
    sudo networksetup -setsecurewebproxystate "$SERVICE" off
    success "系统代理已关闭"
}

proxy_status() {
    echo -e "${BOLD}网络服务: ${SERVICE}${RESET}"
    echo -e "${BOLD}SOCKS${RESET}"
    networksetup -getsocksfirewallproxy "$SERVICE"
    echo -e "${BOLD}HTTP${RESET}"
    networksetup -getwebproxy "$SERVICE"
    echo -e "${BOLD}HTTPS${RESET}"
    networksetup -getsecurewebproxy "$SERVICE"
}

case "$ACTION" in
    on)  proxy_on ;;
    off) proxy_off ;;
    status) proxy_status ;;
    list-services)
        echo -e "${BOLD}可用网络服务:${RESET}"
        networksetup -listallnetworkservices | tail -n +2
        ;;
esac
