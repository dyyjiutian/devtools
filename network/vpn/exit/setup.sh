#!/usr/bin/env bash
# =============================================================================
# VPN 出口节点部署脚本 - 新加坡 ECS (198.51.100.30)
# 方案：Xray VLESS + Reality，伪装 www.icloud.com，支持多用户
# 用法：sudo ./exit/setup.sh [--dry-run] [--port PORT] [--users=NAME[,NAME...]]
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
LISTEN_PORT=443
REALITY_DEST="www.icloud.com:443"
REALITY_SNI="www.icloud.com"
USERS_ARG=""

for arg in "$@"; do
    case $arg in
        --dry-run)   DRY_RUN=true ;;
        --port=*)    LISTEN_PORT="${arg#*=}" ;;
        --users=*)   USERS_ARG="${arg#*=}" ;;
        --help|-h)
            cat <<'HELP'
Usage: sudo ./exit/setup.sh [OPTIONS]

Options:
  --port=PORT          Xray 监听端口（默认 443）
  --users=LIST         用户列表，逗号分隔（默认 user1）
                       数字：--users=3 → 创建 user1 user2 user3
                       名称：--users=alice,bob,carol
  --dry-run            预览操作，不实际执行
  --help               显示帮助

多用户日常管理请使用 manage.sh：
  sudo ./exit/manage.sh --help
HELP
            exit 0
            ;;
        *) warn "未知参数: $arg" ;;
    esac
done

# ── 工具函数 ──────────────────────────────────────────────────────────────────
run() { $DRY_RUN && { info "[dry-run] $*"; return; }; "$@"; }

validate_username() {
    local name="$1"
    [[ "$name" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]] || {
        error "用户名必须以字母开头，只能含字母/数字/下划线: '$name'"
        return 1
    }
}

expand_users_arg() {
    local arg="$1"
    if [[ "$arg" =~ ^[0-9]+$ ]]; then
        local list=""
        for ((i=1; i<=arg; i++)); do list="${list}${list:+ }user${i}"; done
        echo "$list"
    else
        echo "${arg//,/ }"
    fi
}

# ── 前置检查 ──────────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || { error "请以 root 权限运行: sudo $0"; exit 1; }

# ── 系统环境检测 ──────────────────────────────────────────────────────────────
step "检测系统环境"

OS=""
PKG_MGR=""
if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    case "$ID" in
        centos|rhel|almalinux|rocky|alinux|anolis) OS="rhel"; PKG_MGR="yum" ;;
        ubuntu|debian) OS="debian"; PKG_MGR="apt" ;;
        *) error "不支持的发行版: $ID"; exit 1 ;;
    esac
fi

SERVER_IP=$(curl -sf --connect-timeout 5 https://api4.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
info "服务器公网 IP : ${SERVER_IP}"
info "操作系统      : ${PRETTY_NAME:-unknown}"
info "监听端口      : ${LISTEN_PORT}"
info "Reality 伪装  : ${REALITY_DEST}"
$DRY_RUN && warn "[dry-run] 仅预览，不执行实际操作"

# ── 安装 Xray ─────────────────────────────────────────────────────────────────
step "安装 Xray-core"

XRAY_BIN="/usr/local/bin/xray"
XRAY_CONFIG_DIR="/usr/local/etc/xray"
XRAY_LOG_DIR="/var/log/xray"

install_xray() {
    if ! command -v curl &>/dev/null; then
        case $OS in
            rhel)   yum install -y curl ;;
            debian) apt-get update -qq && apt-get install -y curl ;;
        esac
    fi
    info "下载 Xray 官方安装脚本..."
    INSTALL_SCRIPT=$(mktemp)
    curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh -o "$INSTALL_SCRIPT"
    bash "$INSTALL_SCRIPT" install
    rm -f "$INSTALL_SCRIPT"
}

if ! command -v xray &>/dev/null; then
    $DRY_RUN && info "[dry-run] 将安装 Xray-core" || install_xray
else
    XRAY_VER=$("$XRAY_BIN" version 2>&1 | head -1 | grep -oP '[\d.]+' | head -1)
    success "Xray 已安装: v${XRAY_VER}"
fi

# ── 安装配置 Cloudflare WARP ──────────────────────────────────────────────────
# Cloudflare 对数据中心 IP 的出站连接会触发 Bot Challenge（cf-mitigated: challenge），
# 导致 Claude iOS App 等原生客户端无法通过 TLS 握手后的 HTTP 层鉴权。
# WARP 将 Anthropic 域名流量从 Cloudflare 自有 IP 出站，绕过该拦截。
step "安装配置 Cloudflare WARP（绕过 Cloudflare Bot 防护）"

install_warp() {
    case $OS in
        rhel)
            if [[ ! -f /etc/yum.repos.d/cloudflare-warp.repo ]]; then
                curl -fsSL https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo \
                    -o /etc/yum.repos.d/cloudflare-warp.repo
            fi
            yum install -y cloudflare-warp
            ;;
        debian)
            curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
                | gpg --dearmor > /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] \
https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" \
                > /etc/apt/sources.list.d/cloudflare-client.list
            apt-get update -qq && apt-get install -y cloudflare-warp
            ;;
    esac
    systemctl enable --now warp-svc
    sleep 2
    warp-cli --accept-tos registration new 2>/dev/null || true
    warp-cli --accept-tos mode proxy
    warp-cli --accept-tos connect
    sleep 3
}

if $DRY_RUN; then
    info "[dry-run] 将安装 Cloudflare WARP 并设置 proxy 模式（SOCKS5 on 40000）"
else
    if command -v warp-cli &>/dev/null && warp-cli --accept-tos status 2>/dev/null | grep -q "Connected"; then
        WARP_IP=$(curl -s --connect-timeout 5 -x socks5h://127.0.0.1:40000 https://api4.ipify.org 2>/dev/null || echo "unknown")
        success "WARP 已连接，出口 IP: ${WARP_IP}"
    else
        install_warp
        if warp-cli --accept-tos status 2>/dev/null | grep -q "Connected"; then
            WARP_IP=$(curl -s --connect-timeout 5 -x socks5h://127.0.0.1:40000 https://api4.ipify.org 2>/dev/null || echo "unknown")
            success "WARP 已连接，出口 IP: ${WARP_IP}"
        else
            warn "WARP 连接失败，Anthropic 流量将直连（可能被 Cloudflare Bot 防护拦截）"
        fi
    fi
fi

# ── 内核参数优化 ──────────────────────────────────────────────────────────────
step "优化内核网络参数（BBR + TCP 缓冲区）"

tune_kernel() {
    SYSCTL_CONF="/etc/sysctl.d/99-vpn-exit.conf"
    cat > "$SYSCTL_CONF" <<'SYSCTL'
# VPN 出口节点 - 网络性能优化

vm.swappiness = 0
kernel.sysrq = 1

# BBR 拥塞控制（需内核 4.9+）
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 网络缓冲区
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 65536
net.core.wmem_default = 65536
net.core.netdev_max_backlog = 4096
net.core.somaxconn = 4096

# 邻居表 / ARP（云主机多网卡场景，见 https://help.aliyun.com/knowledge_detail/39428.html）
net.ipv4.neigh.default.gc_stale_time = 120
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.default.arp_announce = 2
net.ipv4.conf.lo.arp_announce = 2
net.ipv4.conf.all.arp_announce = 2

# TCP 优化（见 https://help.aliyun.com/knowledge_detail/41334.html）
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
net.ipv4.ip_local_port_range = 1024 65535
SYSCTL
    sysctl -p "$SYSCTL_CONF" > /dev/null
}

if $DRY_RUN; then
    info "[dry-run] 将写入 /etc/sysctl.d/99-vpn-exit.conf 并应用内核参数"
else
    tune_kernel
    CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    [[ "$CC" == "bbr" ]] && success "BBR 拥塞控制已启用" \
        || warn "BBR 未生效（当前: ${CC}），可能需要升级内核至 4.9+"
    success "内核网络参数已优化（配置: /etc/sysctl.d/99-vpn-exit.conf）"
fi

# ── 配置缓存读写 ───────────────────────────────────────────────────────────────
CONFIG_CACHE="/root/.vpn_exit_config"

# 全局变量（由 load_or_init_config 填充）
USERS=""
PRIVATE_KEY=""
PUBLIC_KEY=""
SHORT_ID=""

write_config() {
    {
        echo "PRIVATE_KEY=\"${PRIVATE_KEY}\""
        echo "PUBLIC_KEY=\"${PUBLIC_KEY}\""
        echo "SHORT_ID=\"${SHORT_ID}\""
        echo "LISTEN_PORT=${LISTEN_PORT}"
        echo "REALITY_SNI=\"${REALITY_SNI}\""
        echo "USERS=\"${USERS}\""
        for u in $USERS; do
            local uuid_var="USER_${u}_UUID"
            local quota_var="USER_${u}_QUOTA_GB"
            echo "USER_${u}_UUID=\"${!uuid_var}\""
            echo "USER_${u}_QUOTA_GB=${!quota_var:-0}"
        done
    } > "$CONFIG_CACHE"
    chmod 600 "$CONFIG_CACHE"
}

# ── 生成/加载密钥与用户配置 ───────────────────────────────────────────────────
step "生成/加载 Reality 密钥对与用户 UUID"

if [[ -f "$CONFIG_CACHE" ]] && ! $DRY_RUN; then
    # shellcheck source=/dev/null
    source "$CONFIG_CACHE"
    info "复用已有密钥配置: ${CONFIG_CACHE}"
else
    if $DRY_RUN; then
        PRIVATE_KEY="<private_key_will_be_generated>"
        PUBLIC_KEY="<public_key_will_be_generated>"
        SHORT_ID="$(openssl rand -hex 8 2>/dev/null || echo 'aabbccdd11223344')"
    else
        KEY_OUTPUT=$("$XRAY_BIN" x25519)
        PRIVATE_KEY=$(echo "$KEY_OUTPUT" | grep -E "^PrivateKey:|^Private key:" | awk '{print $NF}')
        PUBLIC_KEY=$(echo "$KEY_OUTPUT"  | grep -E "^\s*Password \(PublicKey\):|^Public key:" | awk '{print $NF}')
        SHORT_ID=$(openssl rand -hex 8)
    fi
fi

# 处理 --users 参数：在已有用户列表基础上新增
if [[ -n "$USERS_ARG" ]]; then
    NEW_USERS=$(expand_users_arg "$USERS_ARG")
    for u in $NEW_USERS; do
        validate_username "$u"
        if [[ " ${USERS} " != *" ${u} "* ]]; then
            USERS="${USERS}${USERS:+ }${u}"
            info "新增用户: ${u}"
        else
            info "用户已存在，跳过: ${u}"
        fi
    done
fi

# 默认至少一个用户
[[ -n "$USERS" ]] || { USERS="user1"; info "使用默认用户: user1"; }

# 为每个用户生成（或复用）UUID
for u in $USERS; do
    uuid_var="USER_${u}_UUID"
    if [[ -z "${!uuid_var:-}" ]]; then
        if $DRY_RUN; then
            declare "${uuid_var}=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
        else
            declare "${uuid_var}=$(cat /proc/sys/kernel/random/uuid)"
        fi
        info "生成新 UUID: ${u} → ${!uuid_var}"
    else
        info "复用已有 UUID: ${u} → ${!uuid_var}"
    fi
    quota_var="USER_${u}_QUOTA_GB"
    [[ -n "${!quota_var:-}" ]] || declare "${quota_var}=0"
done

$DRY_RUN || write_config

# ── 构建 clients JSON ─────────────────────────────────────────────────────────
build_clients_json() {
    local result="" first=true
    for u in $USERS; do
        local uuid_var="USER_${u}_UUID"
        $first || result="${result},"
        first=false
        result="${result}
          {\"id\":\"${!uuid_var}\",\"flow\":\"xtls-rprx-vision\",\"email\":\"${u}@vpn\"}"
    done
    echo "$result"
}

# ── 写入 Xray 配置（含 Stats API）────────────────────────────────────────────
user_count=$(echo "$USERS" | wc -w)
step "写入 Xray 服务端配置（${user_count} 个用户：${USERS}）"

write_xray_config() {
    mkdir -p "$XRAY_CONFIG_DIR" "$XRAY_LOG_DIR"
    local clients_json
    clients_json=$(build_clients_json)

    cat > "${XRAY_CONFIG_DIR}/config.json" <<EOF
{
  "stats": {},
  "api": {
    "tag": "api",
    "services": ["StatsService"]
  },
  "policy": {
    "levels": {
      "0": {
        "statsUserUplink": true,
        "statsUserDownlink": true
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true
    }
  },
  "log": {
    "loglevel": "warning",
    "access": "${XRAY_LOG_DIR}/access.log",
    "error": "${XRAY_LOG_DIR}/error.log"
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 10085,
      "protocol": "dokodemo-door",
      "settings": {"address": "127.0.0.1"},
      "tag": "api"
    },
    {
      "listen": "0.0.0.0",
      "port": ${LISTEN_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [${clients_json}
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${REALITY_DEST}",
          "xver": 0,
          "serverNames": ["${REALITY_SNI}"],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["${SHORT_ID}"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct",
      "settings": {"domainStrategy": "UseIPv4"}
    },
    {
      "protocol": "socks",
      "tag": "warp",
      "settings": {
        "servers": [{"address": "127.0.0.1", "port": 40000}]
      }
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["api"],
        "outboundTag": "api"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "domain": ["domain:anthropic.com", "domain:claude.ai"],
        "outboundTag": "warp"
      }
    ]
  }
}
EOF
    chmod 644 "${XRAY_CONFIG_DIR}/config.json"
}

if $DRY_RUN; then
    info "[dry-run] 将写入配置到 ${XRAY_CONFIG_DIR}/config.json（含 Stats API，端口 10085）"
else
    write_xray_config
    success "Xray 配置已写入: ${XRAY_CONFIG_DIR}/config.json"
fi

# ── 配置 systemd 服务 ─────────────────────────────────────────────────────────
step "配置并启动 Xray systemd 服务"

if $DRY_RUN; then
    info "[dry-run] systemctl enable --now xray"
else
    systemctl daemon-reload
    systemctl enable xray
    systemctl restart xray
    sleep 2
    if systemctl is-active --quiet xray; then
        success "Xray 服务运行中"
    else
        error "Xray 服务启动失败，查看日志: journalctl -u xray -n 50"
        exit 1
    fi
fi

# ── 配置防火墙 ────────────────────────────────────────────────────────────────
step "开放防火墙端口 ${LISTEN_PORT}/tcp"

open_firewall() {
    if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
        run firewall-cmd --permanent --add-port="${LISTEN_PORT}/tcp"
        run firewall-cmd --reload
        success "firewalld: 已开放 ${LISTEN_PORT}/tcp"
    elif command -v ufw &>/dev/null; then
        run ufw allow "${LISTEN_PORT}/tcp"
        success "ufw: 已开放 ${LISTEN_PORT}/tcp"
    else
        warn "未检测到 firewalld/ufw，请在阿里云控制台「安全组」手动放行 ${LISTEN_PORT}/tcp 入方向"
    fi
}

open_firewall

# ── 打印各用户连接参数 ────────────────────────────────────────────────────────
step "部署完成！以下是各用户连接参数"

cat <<EOF

${BOLD}━━━ 出口节点信息 ━━━${RESET}
  服务器 IP  : ${SERVER_IP}
  监听端口   : ${LISTEN_PORT}
  协议       : VLESS + Reality (xtls-rprx-vision)
  伪装域名   : ${REALITY_SNI}
  Stats API  : 127.0.0.1:10085（本机本地，勿对外暴露）
  Public Key : ${PUBLIC_KEY}
  Short ID   : ${SHORT_ID}

EOF

for u in $USERS; do
    uuid_var="USER_${u}_UUID"
    quota_var="USER_${u}_QUOTA_GB"
    uuid="${!uuid_var}"
    quota="${!quota_var:-0}"
    [[ "$quota" == "0" ]] && quota_str="无限制" || quota_str="${quota} GB/月"

    cat <<EOF
${BOLD}━━━ 用户: ${u}（配额: ${quota_str}）━━━${RESET}
  UUID: ${uuid}

  macOS / Windows / Linux (fp=chrome):
  vless://${uuid}@<中继IP>:${LISTEN_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#VPN-${u}

  iOS Shadowrocket (fp=ios):
  vless://${uuid}@<中继IP>:${LISTEN_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SNI}&fp=ios&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#VPN-${u}-iOS

EOF
done

cat <<EOF
${BOLD}━━━ 用户管理（在出口节点执行）━━━${RESET}
  查看流量统计 : sudo ./exit/manage.sh list
  新增用户     : sudo ./exit/manage.sh add <name>
  移除用户     : sudo ./exit/manage.sh remove <name>
  设置配额     : sudo ./exit/manage.sh quota <name> <GB>
  打印 VLESS   : sudo ./exit/manage.sh vless <name>
  安装配额巡检 : sudo ./exit/manage.sh install-cron

${BOLD}━━━ 服务管理 ━━━${RESET}
  查看状态   : systemctl status xray
  查看日志   : journalctl -u xray -f
  配置参数   : cat ${CONFIG_CACHE}

EOF

echo -e "${GREEN}${BOLD}出口节点部署完成！${RESET}"
echo -e "将上方 VLESS 链接中的 ${BOLD}<中继IP>${RESET} 替换为实际中继节点 IP 后，发给各用户。"
