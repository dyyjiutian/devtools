#!/usr/bin/env bash
# =============================================================================
# FRP 客户端部署脚本 - macOS（frpc）
# 功能：将本机 SSH/VNC 注册到 Linux frps，通过服务器 IP 远程访问
# 用法：./setup.sh --server-ip=IP --token=TOKEN [OPTIONS]
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
step()    { echo -e "\n${BOLD}==> $*${RESET}"; }

FRP_VERSION="0.69.1"
INSTALL_DIR="${HOME}/.local/frp"
CONFIG_DIR="${HOME}/.config/frp"
CONFIG_FILE="${CONFIG_DIR}/frpc.toml"
LAUNCH_AGENT="com.frp.client"
LAUNCH_AGENT_PLIST="${HOME}/Library/LaunchAgents/${LAUNCH_AGENT}.plist"

SERVER_IP=""
SERVER_PORT=7000
TOKEN=""
CLIENT_NAME=""
SSH_LOCAL_PORT=22
VNC_LOCAL_PORT=5900
SSH_REMOTE_PORT=6000
VNC_REMOTE_PORT=6001
DRY_RUN=false
ACTION="setup"

for arg in "$@"; do
    case $arg in
        --server-ip=*)        SERVER_IP="${arg#*=}" ;;
        --server-port=*)      SERVER_PORT="${arg#*=}" ;;
        --token=*)            TOKEN="${arg#*=}" ;;
        --client-name=*)      CLIENT_NAME="${arg#*=}" ;;
        --ssh-local-port=*)   SSH_LOCAL_PORT="${arg#*=}" ;;
        --vnc-local-port=*)   VNC_LOCAL_PORT="${arg#*=}" ;;
        --ssh-remote-port=*)  SSH_REMOTE_PORT="${arg#*=}" ;;
        --vnc-remote-port=*)  VNC_REMOTE_PORT="${arg#*=}" ;;
        --dry-run)            DRY_RUN=true ;;
        --clean)              ACTION="clean" ;;
        --status)             ACTION="status" ;;
        --help|-h)
            cat <<'HELP'
Usage: ./setup.sh --server-ip=IP --token=TOKEN [OPTIONS]

在 macOS 上部署 frpc，将 SSH/VNC 注册到 Linux frps 服务端。

必需参数:
  --server-ip=IP           frps 服务器 IP（Linux 机器）
  --token=TOKEN            与服务端一致的认证 token

可选参数:
  --server-port=PORT       frps 控制端口（默认 7000）
  --client-name=NAME       客户端名称（默认主机名）
  --ssh-local-port=PORT    本机 SSH 端口（默认 22）
  --vnc-local-port=PORT    本机 VNC 端口（默认 5900）
  --ssh-remote-port=PORT   服务器 SSH 映射端口（默认 6000）
  --vnc-remote-port=PORT   服务器 VNC 映射端口（默认 6001）
  --dry-run                预览操作，不实际执行
  --clean                  停止并卸载 frpc
  --status                 查看运行状态
  --help                   显示帮助

前置条件（macOS）:
  1. 系统设置 > 通用 > 共享 > 开启「远程登录」（SSH）
  2. 系统设置 > 通用 > 共享 > 开启「屏幕共享」（VNC）

示例:
  ./setup.sh --server-ip=172.18.11.150 --token=abc123 --client-name=macbook
HELP
            exit 0
            ;;
        *) warn "未知参数: $arg" ;;
    esac
done

run() {
    if $DRY_RUN; then
        info "[dry-run] $*"
    else
        "$@"
    fi
}

detect_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64)  echo "amd64" ;;
        arm64)   echo "arm64" ;;
        *) error "不支持的架构: $arch"; exit 1 ;;
    esac
}

port_listening() {
    local p="$1"
    lsof -iTCP:"$p" -sTCP:LISTEN &>/dev/null
}

check_macos_sharing() {
    step "检查 macOS 共享服务"

    if port_listening "${SSH_LOCAL_PORT}"; then
        success "SSH 服务已开启（端口 ${SSH_LOCAL_PORT}）"
    else
        warn "SSH 未监听端口 ${SSH_LOCAL_PORT}"
        warn "请在 系统设置 > 通用 > 共享 中开启「远程登录」"
    fi

    if port_listening "${VNC_LOCAL_PORT}"; then
        success "VNC 服务已开启（端口 ${VNC_LOCAL_PORT}）"
    else
        warn "VNC 未监听端口 ${VNC_LOCAL_PORT}"
        warn "请在 系统设置 > 通用 > 共享 中开启「屏幕共享」"
    fi
}

# ── 状态查询 ──────────────────────────────────────────────────────────────────
if [[ "$ACTION" == "status" ]]; then
    echo -e "\n${BOLD}━━━ frpc 服务状态 ━━━${RESET}"
    launchctl list 2>/dev/null | grep "${LAUNCH_AGENT}" || echo "frpc 服务未运行"
    echo ""
    echo -e "${BOLD}━━━ 本地端口 ━━━${RESET}"
    lsof -iTCP:"${SSH_LOCAL_PORT}" -sTCP:LISTEN 2>/dev/null || echo "SSH 端口 ${SSH_LOCAL_PORT} 未监听"
    lsof -iTCP:"${VNC_LOCAL_PORT}" -sTCP:LISTEN 2>/dev/null || echo "VNC 端口 ${VNC_LOCAL_PORT} 未监听"
    echo ""
    if [[ -f "$CONFIG_FILE" ]]; then
        echo -e "${BOLD}━━━ 配置信息 ━━━${RESET}"
        grep -E '^(serverAddr|serverPort)' "$CONFIG_FILE" 2>/dev/null || true
        grep -E 'remotePort' "$CONFIG_FILE" 2>/dev/null || true
        echo "  配置文件: ${CONFIG_FILE}"
    fi
    exit 0
fi

# ── 清除模式 ──────────────────────────────────────────────────────────────────
if [[ "$ACTION" == "clean" ]]; then
    step "停止并卸载 frpc"
    run launchctl bootout "gui/$(id -u)/${LAUNCH_AGENT}" 2>/dev/null \
        || run launchctl unload "${LAUNCH_AGENT_PLIST}" 2>/dev/null \
        || true
    run rm -f "${LAUNCH_AGENT_PLIST}"
    run rm -f "${CONFIG_FILE}"
    run rm -rf "${CONFIG_DIR}"
    run rm -rf "${INSTALL_DIR}"
    success "frpc 已卸载"
    exit 0
fi

# ── 前置检查 ──────────────────────────────────────────────────────────────────
if [[ "$(uname)" != "Darwin" ]]; then
    error "此脚本仅支持 macOS，Linux 客户端请手动配置 frpc"
    exit 1
fi

if [[ $EUID -eq 0 ]]; then
    warn "macOS 下不建议以 root 运行，使用普通用户权限即可"
fi

if [[ -z "$SERVER_IP" || -z "$TOKEN" ]]; then
    error "缺少必需参数: --server-ip 和 --token"
    echo ""
    echo "先从 Linux 服务端获取连接信息:"
    echo "  sudo network/frp/server/setup.sh --status"
    echo ""
    echo "示例:"
    echo "  $0 --server-ip=172.18.11.150 --token=<token>"
    exit 1
fi

if [[ -z "$CLIENT_NAME" ]]; then
    CLIENT_NAME="$(hostname -s 2>/dev/null || hostname)"
fi

ARCH="$(detect_arch)"
FRP_TARBALL="frp_${FRP_VERSION}_darwin_${ARCH}.tar.gz"
FRP_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FRP_TARBALL}"

step "部署 frpc 客户端"
info "服务器     : ${SERVER_IP}:${SERVER_PORT}"
info "客户端名称 : ${CLIENT_NAME}"
info "SSH 映射   : ${SERVER_IP}:${SSH_REMOTE_PORT} -> 127.0.0.1:${SSH_LOCAL_PORT}"
info "VNC 映射   : ${SERVER_IP}:${VNC_REMOTE_PORT} -> 127.0.0.1:${VNC_LOCAL_PORT}"

$DRY_RUN && warn "[dry-run] 仅预览，不执行实际操作"

# ── 安装 frpc ─────────────────────────────────────────────────────────────────
step "安装 frpc"

install_frpc() {
    if command -v brew &>/dev/null && brew list frpc &>/dev/null 2>&1; then
        local brew_bin
        brew_bin="$(brew --prefix)/bin/frpc"
        run mkdir -p "${INSTALL_DIR}"
        run cp "${brew_bin}" "${INSTALL_DIR}/frpc"
        run chmod +x "${INSTALL_DIR}/frpc"
        success "使用 Homebrew 安装的 frpc"
        return
    fi

    if ! command -v curl &>/dev/null; then
        error "需要 curl，请先安装 Xcode Command Line Tools: xcode-select --install"
        exit 1
    fi

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' RETURN

    info "下载 ${FRP_URL}"
    curl -fsSL "${FRP_URL}" -o "${tmpdir}/${FRP_TARBALL}"
    tar -xzf "${tmpdir}/${FRP_TARBALL}" -C "${tmpdir}"

    run mkdir -p "${INSTALL_DIR}"
    run cp "${tmpdir}/frp_${FRP_VERSION}_darwin_${ARCH}/frpc" "${INSTALL_DIR}/frpc"
    run chmod +x "${INSTALL_DIR}/frpc"
    success "frpc 已安装到 ${INSTALL_DIR}/frpc"
}

if [[ -x "${INSTALL_DIR}/frpc" ]]; then
    success "frpc 已存在: $("${INSTALL_DIR}/frpc" --version 2>&1 | head -1 || echo 'unknown')"
elif command -v frpc &>/dev/null; then
    run mkdir -p "${INSTALL_DIR}"
    run cp "$(command -v frpc)" "${INSTALL_DIR}/frpc"
    success "frpc 已复制到 ${INSTALL_DIR}/frpc"
else
    if $DRY_RUN; then
        info "[dry-run] 将下载并安装 frpc v${FRP_VERSION}"
    else
        install_frpc
    fi
fi

FRPC_BIN="${INSTALL_DIR}/frpc"

# ── 写入配置 ──────────────────────────────────────────────────────────────────
step "写入 frpc 配置"

write_config() {
    run mkdir -p "${CONFIG_DIR}"

    cat > "${CONFIG_DIR}/frpc.toml" <<TOML
# FRP 客户端配置 - 由 network/frp/client/setup.sh 生成
# 客户端: ${CLIENT_NAME}

serverAddr = "${SERVER_IP}"
serverPort = ${SERVER_PORT}

auth.method = "token"
auth.token = "${TOKEN}"

# 传输层保活（应对网络波动）
transport.heartbeatInterval = 30
transport.heartbeatTimeout = 90
transport.tcpMux = true

# SSH 代理
[[proxies]]
name = "${CLIENT_NAME}-ssh"
type = "tcp"
localIP = "127.0.0.1"
localPort = ${SSH_LOCAL_PORT}
remotePort = ${SSH_REMOTE_PORT}

# VNC / 屏幕共享代理
[[proxies]]
name = "${CLIENT_NAME}-vnc"
type = "tcp"
localIP = "127.0.0.1"
localPort = ${VNC_LOCAL_PORT}
remotePort = ${VNC_REMOTE_PORT}
TOML

    run chmod 600 "${CONFIG_FILE}"
}

if $DRY_RUN; then
    info "[dry-run] 将写入 ${CONFIG_FILE}"
else
    write_config
    success "配置已写入 ${CONFIG_FILE}"
fi

# ── launchd 自启动 ────────────────────────────────────────────────────────────
step "配置 launchd 自启动"

write_launch_agent() {
    cat > "${LAUNCH_AGENT_PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LAUNCH_AGENT}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${FRPC_BIN}</string>
        <string>-c</string>
        <string>${CONFIG_FILE}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${CONFIG_DIR}/frpc.log</string>
    <key>StandardErrorPath</key>
    <string>${CONFIG_DIR}/frpc.error.log</string>
    <key>ThrottleInterval</key>
    <integer>10</integer>
</dict>
</plist>
PLIST

    # macOS 12+ 使用 bootout/bootstrap，旧版 fallback 到 unload/load
    run launchctl bootout "gui/$(id -u)/${LAUNCH_AGENT}" 2>/dev/null \
        || run launchctl unload "${LAUNCH_AGENT_PLIST}" 2>/dev/null \
        || true
    run launchctl bootstrap "gui/$(id -u)" "${LAUNCH_AGENT_PLIST}" 2>/dev/null \
        || run launchctl load -w "${LAUNCH_AGENT_PLIST}"
}

if $DRY_RUN; then
    info "[dry-run] 将创建 LaunchAgent ${LAUNCH_AGENT}"
else
    write_launch_agent
    sleep 2
    if launchctl list 2>/dev/null | grep -q "${LAUNCH_AGENT}"; then
        success "frpc 服务已启动"
    else
        warn "frpc 可能未成功启动，请检查日志: ${CONFIG_DIR}/frpc.error.log"
    fi
fi

check_macos_sharing

# ── 输出连接信息 ──────────────────────────────────────────────────────────────
step "部署完成"

MAC_USER="$(whoami)"
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  FRP 客户端已就绪 (${CLIENT_NAME})${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "${BOLD}远程连接此 Mac:${RESET}"
echo -e "  SSH : ssh -p ${SSH_REMOTE_PORT} ${MAC_USER}@${SERVER_IP}"
echo -e "  VNC : open vnc://${SERVER_IP}:${VNC_REMOTE_PORT}"
echo -e "        或在 Finder > 前往 > 连接服务器 输入 vnc://${SERVER_IP}:${VNC_REMOTE_PORT}"
echo ""
echo -e "${BOLD}常用命令:${RESET}"
echo -e "  $0 --status"
echo -e "  launchctl list | grep ${LAUNCH_AGENT}"
echo -e "  tail -f ${CONFIG_DIR}/frpc.log"
echo -e "  $0 --clean"
echo ""
echo -e "${BOLD}多台 Mac:${RESET}"
echo -e "  每台 Mac 使用不同的 --ssh-remote-port / --vnc-remote-port"
echo -e "  例: Mac-A 用 6000/6001，Mac-B 用 6002/6003"
echo ""
