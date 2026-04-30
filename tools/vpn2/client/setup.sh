#!/usr/bin/env bash
# =============================================================================
# VPN2 客户端部署脚本 - 国内机器
# 方案：Xray VLESS + Reality 客户端，通过杭州中继访问 claude.ai
# 用法：sudo ./client/setup.sh --relay-ip=198.51.100.10 --uuid=<UUID> \
#           --public-key=<PUB_KEY> --short-id=<SHORT_ID> [OPTIONS]
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
step()    { echo -e "\n${BOLD}==> $*${RESET}"; }

# ── 参数解析 ──────────────────────────────────────────────────────────────────
DRY_RUN=false
RELAY_IP="198.51.100.10"
RELAY_PORT=443
UUID=""
PUBLIC_KEY=""
SHORT_ID=""
SNI="www.microsoft.com"
FINGERPRINT="chrome"
SOCKS_PORT=10808
HTTP_PORT=10809
ACTION="setup"

for arg in "$@"; do
    case $arg in
        --relay-ip=*)    RELAY_IP="${arg#*=}" ;;
        --relay-port=*)  RELAY_PORT="${arg#*=}" ;;
        --uuid=*)        UUID="${arg#*=}" ;;
        --public-key=*)  PUBLIC_KEY="${arg#*=}" ;;
        --short-id=*)    SHORT_ID="${arg#*=}" ;;
        --sni=*)         SNI="${arg#*=}" ;;
        --socks-port=*)  SOCKS_PORT="${arg#*=}" ;;
        --http-port=*)   HTTP_PORT="${arg#*=}" ;;
        --dry-run)       DRY_RUN=true ;;
        --clean)         ACTION="clean" ;;
        --status)        ACTION="status" ;;
        --help|-h)
            cat <<'HELP'
Usage: sudo ./client/setup.sh --uuid=<UUID> --public-key=<KEY> --short-id=<SID> [OPTIONS]

必需参数（从出口节点部署输出中获取）:
  --uuid=UUID          VLESS 用户 UUID
  --public-key=KEY     Reality 公钥
  --short-id=SID       Reality Short ID

可选参数:
  --relay-ip=IP        中继节点 IP（默认 198.51.100.10）
  --relay-port=PORT    中继节点端口（默认 443）
  --sni=DOMAIN         Reality SNI 域名（默认 www.microsoft.com）
  --socks-port=PORT    本地 SOCKS5 监听端口（默认 10808）
  --http-port=PORT     本地 HTTP 代理监听端口（默认 10809）
  --dry-run            预览操作，不实际执行
  --clean              停止并卸载 Xray 客户端
  --status             查看运行状态
  --help               显示帮助
HELP
            exit 0
            ;;
        *) warn "未知参数: $arg" ;;
    esac
done

# ── 状态查询模式 ──────────────────────────────────────────────────────────────
if [[ "$ACTION" == "status" ]]; then
    echo -e "\n${BOLD}━━━ Xray 客户端状态 ━━━${RESET}"
    systemctl status xray-client 2>/dev/null || \
    systemctl status xray 2>/dev/null || \
    echo "Xray 服务未找到"
    echo ""
    echo -e "${BOLD}━━━ 代理端口监听 ━━━${RESET}"
    ss -tlnp | grep -E "10808|10809" || echo "代理端口未监听"
    echo ""
    echo -e "${BOLD}━━━ 连通性测试（通过代理访问 claude.ai）━━━${RESET}"
    curl -x "socks5h://127.0.0.1:10808" -fsSL --connect-timeout 10 \
        -o /dev/null -w "HTTP 状态: %{http_code}\n" https://claude.ai/ 2>/dev/null \
        || echo "连接失败，请检查代理配置"
    exit 0
fi

# ── 清除模式 ──────────────────────────────────────────────────────────────────
if [[ "$ACTION" == "clean" ]]; then
    step "停止并移除 Xray 客户端"
    systemctl stop xray-client 2>/dev/null || true
    systemctl disable xray-client 2>/dev/null || true
    rm -f /etc/systemd/system/xray-client.service
    rm -f /usr/local/etc/xray/client.json
    systemctl daemon-reload
    success "Xray 客户端已停止并移除"
    exit 0
fi

# ── 前置检查 ──────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "请以 root 权限运行: sudo $0"
    exit 1
fi

if [[ -z "$UUID" || -z "$PUBLIC_KEY" || -z "$SHORT_ID" ]]; then
    error "缺少必需参数！请从出口节点部署输出中获取并填写:"
    error "  --uuid=<UUID> --public-key=<PUBLIC_KEY> --short-id=<SHORT_ID>"
    echo ""
    echo "示例:"
    echo "  sudo $0 --uuid=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \\"
    echo "          --public-key=<base64_public_key> \\"
    echo "          --short-id=<8_hex_chars>"
    exit 1
fi

run() {
    if $DRY_RUN; then
        info "[dry-run] $*"
    else
        "$@"
    fi
}

step "部署 Xray 客户端"
info "中继节点  : ${RELAY_IP}:${RELAY_PORT}"
info "UUID      : ${UUID}"
info "SNI       : ${SNI}"
info "SOCKS5    : 127.0.0.1:${SOCKS_PORT}"
info "HTTP代理  : 127.0.0.1:${HTTP_PORT}"

$DRY_RUN && warn "[dry-run] 仅预览，不执行实际操作"

# ── 安装 Xray ─────────────────────────────────────────────────────────────────
step "安装 Xray-core"

XRAY_CONFIG_DIR="/usr/local/etc/xray"

install_xray() {
    if ! command -v curl &>/dev/null; then
        if [[ -f /etc/os-release ]]; then
            # shellcheck source=/dev/null
            source /etc/os-release
            case "$ID" in
                centos|rhel|almalinux|rocky|alinux|anolis) yum install -y curl ;;
                ubuntu|debian) apt-get update -qq && apt-get install -y curl ;;
            esac
        fi
    fi

    info "下载 Xray 官方安装脚本..."
    INSTALL_SCRIPT=$(mktemp)
    curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh -o "$INSTALL_SCRIPT"
    bash "$INSTALL_SCRIPT" install
    rm -f "$INSTALL_SCRIPT"
}

if ! command -v xray &>/dev/null; then
    if $DRY_RUN; then
        info "[dry-run] 将安装 Xray-core"
    else
        install_xray
    fi
else
    XRAY_VER=$(/usr/local/bin/xray version 2>&1 | head -1 | grep -oP '[\d.]+' | head -1)
    success "Xray 已安装: v${XRAY_VER}"
fi

# ── 写入客户端配置 ────────────────────────────────────────────────────────────
step "写入 Xray 客户端配置"

write_client_config() {
    mkdir -p "$XRAY_CONFIG_DIR"
    cat > "${XRAY_CONFIG_DIR}/client.json" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "socks",
      "listen": "127.0.0.1",
      "port": ${SOCKS_PORT},
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    },
    {
      "tag": "http",
      "listen": "127.0.0.1",
      "port": ${HTTP_PORT},
      "protocol": "http",
      "settings": {
        "allowTransparent": false
      }
    }
  ],
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "${RELAY_IP}",
            "port": ${RELAY_PORT},
            "users": [
              {
                "id": "${UUID}",
                "flow": "xtls-rprx-vision",
                "encryption": "none"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "fingerprint": "${FINGERPRINT}",
          "serverName": "${SNI}",
          "publicKey": "${PUBLIC_KEY}",
          "shortId": "${SHORT_ID}",
          "spiderX": "/"
        }
      }
    },
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv4"
      }
    },
    {
      "tag": "block",
      "protocol": "blackhole"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "ip": ["geoip:cn"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "domain": ["geosite:cn"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "domain": [
          "claude.ai",
          "anthropic.com",
          "statsig.anthropic.com",
          "sentry.io"
        ],
        "outboundTag": "proxy"
      },
      {
        "type": "field",
        "domain": ["geosite:geolocation-!cn"],
        "outboundTag": "proxy"
      }
    ]
  }
}
EOF
    chmod 644 "${XRAY_CONFIG_DIR}/client.json"
}

if $DRY_RUN; then
    info "[dry-run] 将写入客户端配置到 ${XRAY_CONFIG_DIR}/client.json"
else
    write_client_config
    success "客户端配置已写入: ${XRAY_CONFIG_DIR}/client.json"
fi

# ── 配置 systemd 服务（独立于服务端实例）────────────────────────────────────
step "配置 xray-client systemd 服务"

write_systemd_service() {
    cat > /etc/systemd/system/xray-client.service <<EOF
[Unit]
Description=Xray Client - VPN2 VLESS+Reality
Documentation=https://xtls.github.io
After=network.target nss-lookup.target

[Service]
User=nobody
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/client.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
}

if $DRY_RUN; then
    info "[dry-run] 将创建 /etc/systemd/system/xray-client.service"
else
    write_systemd_service
    systemctl daemon-reload
    systemctl enable xray-client
    systemctl restart xray-client
    sleep 2
    if systemctl is-active --quiet xray-client; then
        success "xray-client 服务运行中"
    else
        error "xray-client 启动失败，查看日志: journalctl -u xray-client -n 50"
        exit 1
    fi
fi

# ── 验证连通性 ────────────────────────────────────────────────────────────────
step "验证代理连通性"

if ! $DRY_RUN; then
    info "等待代理端口就绪..."
    sleep 1

    # 验证 SOCKS 端口
    if ss -tlnp | grep -q ":${SOCKS_PORT}"; then
        success "SOCKS5 代理端口 ${SOCKS_PORT} 监听中"
    else
        warn "SOCKS5 端口 ${SOCKS_PORT} 未监听，检查 Xray 日志"
    fi

    # 尝试通过代理访问 claude.ai
    info "测试通过代理访问 claude.ai..."
    HTTP_CODE=$(curl -x "socks5h://127.0.0.1:${SOCKS_PORT}" \
        -fsSL --connect-timeout 15 \
        -o /dev/null -w "%{http_code}" \
        https://claude.ai/ 2>/dev/null) || HTTP_CODE="000"

    if [[ "$HTTP_CODE" =~ ^[23] ]]; then
        success "claude.ai 访问成功！HTTP 状态: ${HTTP_CODE}"
    else
        warn "claude.ai 访问测试返回: ${HTTP_CODE}（可能需要几秒钟预热，或检查出口节点配置）"
    fi
fi

# ── 打印使用说明 ──────────────────────────────────────────────────────────────
step "客户端配置完成！"

cat <<EOF

${BOLD}━━━ 代理端口 ━━━${RESET}
  SOCKS5  : socks5h://127.0.0.1:${SOCKS_PORT}
  HTTP    : http://127.0.0.1:${HTTP_PORT}

${BOLD}━━━ 浏览器配置 ━━━${RESET}
  方式一：系统代理 → 手动配置 → SOCKS 主机 127.0.0.1 端口 ${SOCKS_PORT}
  方式二：Chrome 插件 SwitchyOmega → 新建情景模式 → SOCKS5 127.0.0.1:${SOCKS_PORT}

${BOLD}━━━ curl / wget 使用 ━━━${RESET}
  curl -x socks5h://127.0.0.1:${SOCKS_PORT} https://claude.ai/
  curl -x http://127.0.0.1:${HTTP_PORT} https://claude.ai/

${BOLD}━━━ 环境变量（终端全局代理）━━━${RESET}
  export https_proxy=http://127.0.0.1:${HTTP_PORT}
  export http_proxy=http://127.0.0.1:${HTTP_PORT}

${BOLD}━━━ 服务管理命令 ━━━${RESET}
  查看状态   : sudo $0 --status
  查看日志   : journalctl -u xray-client -f
  重启服务   : systemctl restart xray-client
  停止卸载   : sudo $0 --clean

${BOLD}━━━ 路由策略说明 ━━━${RESET}
  国内域名/IP     → 直连（不走代理）
  claude.ai 等    → 通过 ${RELAY_IP} 中继代理
  其余境外流量    → 通过代理

EOF

echo -e "${GREEN}${BOLD}客户端部署完成！${RESET} 现在可以通过 SOCKS5 代理访问 claude.ai"
