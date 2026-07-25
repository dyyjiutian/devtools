#!/usr/bin/env bash
# =============================================================================
# FRP 服务端部署脚本 - Linux（frps）
# 功能：在公网/内网 Linux 上运行 frps，供 Mac 客户端注册 SSH/VNC 代理
# 用法：sudo ./setup.sh [--token=TOKEN] [--bind-port=7000] [--dry-run]
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
INSTALL_DIR="/usr/local/frp"
CONFIG_DIR="/etc/frp"
CONFIG_FILE="${CONFIG_DIR}/frps.toml"
TOKEN_FILE="${CONFIG_DIR}/.token"
SERVICE_NAME="frps"

BIND_PORT=7000
DASHBOARD_PORT=7500
REMOTE_PORT_START=6000
REMOTE_PORT_END=6100
TOKEN=""
DRY_RUN=false
ACTION="setup"

for arg in "$@"; do
    case $arg in
        --token=*)            TOKEN="${arg#*=}" ;;
        --bind-port=*)        BIND_PORT="${arg#*=}" ;;
        --dashboard-port=*)   DASHBOARD_PORT="${arg#*=}" ;;
        --remote-port-start=*) REMOTE_PORT_START="${arg#*=}" ;;
        --remote-port-end=*)  REMOTE_PORT_END="${arg#*=}" ;;
        --dry-run)            DRY_RUN=true ;;
        --clean)              ACTION="clean" ;;
        --status)             ACTION="status" ;;
        --help|-h)
            cat <<'HELP'
Usage: sudo ./setup.sh [OPTIONS]

在 Linux 上部署 frps，Mac 客户端连接后可通过本机 IP 访问 Mac 的 SSH/VNC。

可选参数:
  --token=TOKEN            认证 token（默认自动生成）
  --bind-port=PORT         frps 监听端口（默认 7000）
  --dashboard-port=PORT    管理面板端口（默认 7500，仅本机访问）
  --remote-port-start=N    客户端映射端口范围起始（默认 6000）
  --remote-port-end=N      客户端映射端口范围结束（默认 6100）
  --dry-run                预览操作，不实际执行
  --clean                  停止并卸载 frps
  --status                 查看运行状态
  --help                   显示帮助

示例:
  sudo ./setup.sh
  sudo ./setup.sh --token=my_secret_token
  sudo ./setup.sh --status
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
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) error "不支持的架构: $arch"; exit 1 ;;
    esac
}

server_ip() {
    curl -sf --connect-timeout 5 https://api4.ipify.org 2>/dev/null \
        || hostname -I 2>/dev/null | awk '{print $1}' \
        || ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}'
}

open_firewall_ports() {
    step "配置防火墙"

    local ports=("${BIND_PORT}" "${REMOTE_PORT_START}:${REMOTE_PORT_END}")
    if command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
        for p in "${ports[@]}"; do
            if firewall-cmd --list-ports 2>/dev/null | grep -q "${p}/tcp"; then
                info "firewalld 端口 ${p} 已开放"
            else
                run firewall-cmd --permanent --add-port="${p}/tcp"
                success "firewalld 开放端口 ${p}/tcp"
            fi
        done
        run firewall-cmd --reload
    elif command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        for p in "${ports[@]}"; do
            run ufw allow "${p}/tcp"
        done
        success "ufw 已开放端口"
    else
        warn "未检测到 firewalld/ufw，请手动在云安全组开放端口:"
        warn "  ${BIND_PORT}/tcp（frps 控制端口）"
        warn "  ${REMOTE_PORT_START}-${REMOTE_PORT_END}/tcp（SSH/VNC 映射端口）"
    fi
}

# ── 状态查询 ──────────────────────────────────────────────────────────────────
if [[ "$ACTION" == "status" ]]; then
    echo -e "\n${BOLD}━━━ frps 服务状态 ━━━${RESET}"
    systemctl status "${SERVICE_NAME}" --no-pager 2>/dev/null || echo "frps 服务未安装或未运行"
    echo ""
    echo -e "${BOLD}━━━ 监听端口 ━━━${RESET}"
    ss -tlnp 2>/dev/null | grep -E "frps|:${BIND_PORT} " || echo "frps 端口未监听"
    echo ""
    if [[ -f "$TOKEN_FILE" ]]; then
        echo -e "${BOLD}━━━ 连接信息 ━━━${RESET}"
        echo "  服务器 IP : $(server_ip)"
        echo "  控制端口  : ${BIND_PORT}"
        echo "  Token     : $(cat "$TOKEN_FILE")"
        echo "  配置文件  : ${CONFIG_FILE}"
        if [[ -f "${CONFIG_DIR}/.server_info" ]]; then
            echo ""
            echo -e "${BOLD}━━━ Mac 客户端命令 ━━━${RESET}"
            # shellcheck source=/dev/null
            source "${CONFIG_DIR}/.server_info"
            echo "  cd network/frp/client"
            echo "  ./setup.sh --server-ip=${SERVER_IP} --token=${TOKEN} --client-name=\$(hostname -s)"
        fi
    fi
    exit 0
fi

# ── 清除模式 ──────────────────────────────────────────────────────────────────
if [[ "$ACTION" == "clean" ]]; then
    if [[ $EUID -ne 0 ]]; then
        error "请以 root 权限运行: sudo $0 --clean"
        exit 1
    fi
    step "停止并卸载 frps"
    run systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
    run systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
    run rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    run systemctl daemon-reload
    run rm -f "/usr/local/bin/frps"
    run rm -rf "${INSTALL_DIR}"
    run rm -rf "${CONFIG_DIR}"
    success "frps 已卸载"
    exit 0
fi

# ── 前置检查 ──────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "请以 root 权限运行: sudo $0"
    exit 1
fi

ARCH="$(detect_arch)"
SERVER_IP="$(server_ip)"
FRP_TARBALL="frp_${FRP_VERSION}_linux_${ARCH}.tar.gz"
FRP_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FRP_TARBALL}"

step "检测系统环境"
info "服务器 IP  : ${SERVER_IP}"
info "系统架构   : ${ARCH}"
info "FRP 版本   : v${FRP_VERSION}"
info "控制端口   : ${BIND_PORT}"
info "映射端口   : ${REMOTE_PORT_START}-${REMOTE_PORT_END}"

$DRY_RUN && warn "[dry-run] 仅预览，不执行实际操作"

# ── 安装 frps ─────────────────────────────────────────────────────────────────
step "安装 frps"

install_frps() {
    if ! command -v curl &>/dev/null; then
        if [[ -f /etc/os-release ]]; then
            # shellcheck source=/dev/null
            source /etc/os-release
            case "$ID" in
                centos|rhel|almalinux|rocky|alinux|anolis) yum install -y curl tar ;;
                ubuntu|debian) apt-get update -qq && apt-get install -y curl tar ;;
            esac
        fi
    fi

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' RETURN

    info "下载 ${FRP_URL}"
    curl -fsSL "${FRP_URL}" -o "${tmpdir}/${FRP_TARBALL}"
    tar -xzf "${tmpdir}/${FRP_TARBALL}" -C "${tmpdir}"

    run mkdir -p "${INSTALL_DIR}"
    run cp "${tmpdir}/frp_${FRP_VERSION}_linux_${ARCH}/frps" "${INSTALL_DIR}/frps"
    run chmod +x "${INSTALL_DIR}/frps"
    run ln -sf "${INSTALL_DIR}/frps" /usr/local/bin/frps
    success "frps 已安装到 ${INSTALL_DIR}/frps"
}

if command -v frps &>/dev/null; then
    success "frps 已存在: $(frps --version 2>&1 | head -1 || echo 'unknown')"
else
    if $DRY_RUN; then
        info "[dry-run] 将下载并安装 frps v${FRP_VERSION}"
    else
        install_frps
    fi
fi

# ── 生成 token ────────────────────────────────────────────────────────────────
step "生成认证配置"

if [[ -z "$TOKEN" ]]; then
    if [[ -f "$TOKEN_FILE" ]]; then
        TOKEN="$(cat "$TOKEN_FILE")"
        info "使用已有 token"
    elif command -v openssl &>/dev/null; then
        TOKEN="$(openssl rand -hex 16)"
    else
        TOKEN="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    fi
fi

DASHBOARD_USER="admin"
if command -v openssl &>/dev/null; then
    DASHBOARD_PASS="$(openssl rand -hex 8)"
else
    DASHBOARD_PASS="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-12)"
fi

# ── 写入配置 ──────────────────────────────────────────────────────────────────
step "写入 frps 配置"

write_config() {
    run mkdir -p "${CONFIG_DIR}"
    run chmod 700 "${CONFIG_DIR}"

    cat > "${CONFIG_DIR}/frps.toml" <<TOML
# FRP 服务端配置 - 由 network/frp/server/setup.sh 生成

bindPort = ${BIND_PORT}

# 客户端认证
auth.method = "token"
auth.token = "${TOKEN}"

# 管理面板（仅本机访问，通过 SSH 隧道使用）
webServer.addr = "127.0.0.1"
webServer.port = ${DASHBOARD_PORT}
webServer.user = "${DASHBOARD_USER}"
webServer.password = "${DASHBOARD_PASS}"

# 限制客户端可注册的远程端口范围
allowPorts = [
  { start = ${REMOTE_PORT_START}, end = ${REMOTE_PORT_END} }
]

# 传输层优化
transport.maxPoolCount = 20
transport.tcpKeepalive = 30
TOML

    echo "${TOKEN}" > "${CONFIG_DIR}/.token"
    run chmod 600 "${CONFIG_DIR}/.token" "${CONFIG_DIR}/frps.toml"

    cat > "${CONFIG_DIR}/.dashboard" <<DASH
user=${DASHBOARD_USER}
password=${DASHBOARD_PASS}
port=${DASHBOARD_PORT}
DASH
    run chmod 600 "${CONFIG_DIR}/.dashboard"
}

if $DRY_RUN; then
    info "[dry-run] 将写入 ${CONFIG_FILE}"
else
    write_config
    success "配置已写入 ${CONFIG_FILE}"
fi

# ── systemd 服务 ──────────────────────────────────────────────────────────────
step "配置 systemd 服务"

write_service() {
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<SERVICE
[Unit]
Description=FRP Server (frps)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/frps -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SERVICE

    run systemctl daemon-reload
    run systemctl enable "${SERVICE_NAME}"
    run systemctl restart "${SERVICE_NAME}"
}

if $DRY_RUN; then
    info "[dry-run] 将创建 systemd 服务 ${SERVICE_NAME}"
else
    write_service
    sleep 1
    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        success "frps 服务已启动"
    else
        error "frps 启动失败，请检查: journalctl -u ${SERVICE_NAME} -n 30"
        exit 1
    fi
fi

open_firewall_ports

# ── 保存连接信息 ──────────────────────────────────────────────────────────────
save_server_info() {
    local info_file="${CONFIG_DIR}/.server_info"
    cat > "${info_file}" <<INFO
# FRP 服务端连接信息 - $(date '+%Y-%m-%d %H:%M:%S')
SERVER_IP=${SERVER_IP}
BIND_PORT=${BIND_PORT}
TOKEN=${TOKEN}
REMOTE_PORT_START=${REMOTE_PORT_START}
REMOTE_PORT_END=${REMOTE_PORT_END}
DASHBOARD_PORT=${DASHBOARD_PORT}
DASHBOARD_USER=${DASHBOARD_USER}
DASHBOARD_PASS=${DASHBOARD_PASS}
INFO
    run chmod 600 "${info_file}"
}

if ! $DRY_RUN; then
    save_server_info
    success "连接信息已保存到 ${CONFIG_DIR}/.server_info"
fi

# ── 输出连接信息 ──────────────────────────────────────────────────────────────
step "部署完成"

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  FRP 服务端已就绪${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  ${BOLD}服务器 IP${RESET}  : ${SERVER_IP}"
echo -e "  ${BOLD}控制端口${RESET}  : ${BIND_PORT}"
echo -e "  ${BOLD}Token${RESET}       : ${TOKEN}"
echo -e "  ${BOLD}映射端口${RESET}  : ${REMOTE_PORT_START}-${REMOTE_PORT_END}"
echo ""
echo -e "${BOLD}在 Mac 上运行客户端:${RESET}"
echo ""
echo -e "  cd network/frp/client"
echo -e "  ./setup.sh \\"
echo -e "    --server-ip=${SERVER_IP} \\"
echo -e "    --token=${TOKEN} \\"
echo -e "    --client-name=\$(hostname -s) \\"
echo -e "    --ssh-remote-port=6000 \\"
echo -e "    --vnc-remote-port=6001"
echo ""
echo -e "${BOLD}连接 Mac:${RESET}"
echo -e "  SSH : ssh -p 6000 <mac_user>@${SERVER_IP}"
echo -e "  VNC : vnc://${SERVER_IP}:6001"
echo ""
echo -e "${BOLD}管理面板（需 SSH 隧道）:${RESET}"
echo -e "  ssh -L ${DASHBOARD_PORT}:127.0.0.1:${DASHBOARD_PORT} user@${SERVER_IP}"
echo -e "  浏览器访问 http://127.0.0.1:${DASHBOARD_PORT}  用户: ${DASHBOARD_USER}  密码: ${DASHBOARD_PASS}"
echo ""
echo -e "${BOLD}常用命令:${RESET}"
echo -e "  sudo systemctl status ${SERVICE_NAME}"
echo -e "  sudo journalctl -u ${SERVICE_NAME} -f"
echo -e "  sudo $0 --status"
echo ""
