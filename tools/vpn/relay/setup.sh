#!/usr/bin/env bash
# =============================================================================
# VPN 中继节点部署脚本 - 杭州 ECS (198.51.100.10)
# 方案：iptables DNAT 透明转发，无需安装任何代理软件
# 用法：sudo ./relay/setup.sh --exit-ip=198.51.100.30 [--exit-port=443] [--listen-port=443] [--dry-run]
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
EXIT_IP=""
EXIT_PORT=443
LISTEN_PORT=443

for arg in "$@"; do
    case $arg in
        --exit-ip=*)     EXIT_IP="${arg#*=}" ;;
        --exit-port=*)   EXIT_PORT="${arg#*=}" ;;
        --listen-port=*) LISTEN_PORT="${arg#*=}" ;;
        --dry-run)       DRY_RUN=true ;;
        --clean)         ACTION="clean" ;;
        --help|-h)
            echo "Usage: sudo $0 --exit-ip=<EXIT_IP> [OPTIONS]"
            echo ""
            echo "必需参数:"
            echo "  --exit-ip=IP      新加坡出口节点 IP（例：198.51.100.30）"
            echo ""
            echo "可选参数:"
            echo "  --exit-port=PORT     出口节点端口（默认 443）"
            echo "  --listen-port=PORT   中继节点监听端口（默认 443）"
            echo "  --dry-run            预览操作，不实际执行"
            echo "  --clean              清除 iptables 转发规则"
            echo "  --help               显示帮助"
            exit 0
            ;;
        *) warn "未知参数: $arg" ;;
    esac
done

ACTION="${ACTION:-setup}"

# 如果未传 --exit-ip，使用默认出口 IP
if [[ -z "$EXIT_IP" ]]; then
    EXIT_IP="198.51.100.30"
    warn "未指定 --exit-ip，使用默认出口 IP: ${EXIT_IP}"
fi

# ── 前置检查 ──────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "请以 root 权限运行: sudo $0"
    exit 1
fi

run() {
    if $DRY_RUN; then
        info "[dry-run] $*"
    else
        "$@"
    fi
}

RELAY_IP=$(curl -sf --connect-timeout 5 https://api4.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
info "中继节点 IP : ${RELAY_IP}"
info "出口节点    : ${EXIT_IP}:${EXIT_PORT}"
info "监听端口    : ${LISTEN_PORT}"

$DRY_RUN && warn "[dry-run] 仅预览，不执行实际操作"

# ── 清除规则模式 ──────────────────────────────────────────────────────────────
if [[ "$ACTION" == "clean" ]]; then
    step "清除 iptables 转发规则"
    run iptables -t nat -D PREROUTING -p tcp --dport "${LISTEN_PORT}" -j DNAT \
        --to-destination "${EXIT_IP}:${EXIT_PORT}" 2>/dev/null || true
    run iptables -t nat -D POSTROUTING -d "${EXIT_IP}/32" -p tcp -j MASQUERADE 2>/dev/null || true
    run iptables -D FORWARD -d "${EXIT_IP}/32" -p tcp --dport "${EXIT_PORT}" -j ACCEPT 2>/dev/null || true
    run iptables -D FORWARD -s "${EXIT_IP}/32" -p tcp --sport "${EXIT_PORT}" -j ACCEPT 2>/dev/null || true
    success "iptables 转发规则已清除"
    # 保存
    if command -v iptables-save &>/dev/null; then
        if [[ -d /etc/iptables ]]; then
            run sh -c "iptables-save > /etc/iptables/rules.v4"
        elif command -v service &>/dev/null && service iptables status &>/dev/null 2>&1; then
            run service iptables save
        fi
    fi
    exit 0
fi

# ── 启用 IP 转发 ──────────────────────────────────────────────────────────────
step "开启内核 IP 转发"

enable_ip_forward() {
    # 立即生效
    echo 1 > /proc/sys/net/ipv4/ip_forward

    # 持久化（重启后生效）
    SYSCTL_CONF="/etc/sysctl.d/99-vpn-relay.conf"
    cat > "$SYSCTL_CONF" <<'SYSCTL'
# VPN 中继节点 - IP 转发 + 网络性能优化

vm.swappiness = 0
kernel.sysrq = 1

# IP 转发（DNAT 必需）
net.ipv4.ip_forward = 1

# 关闭 ICMP 重定向（避免路由泄漏）
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# 邻居表 / ARP（云主机多网卡场景，见 https://help.aliyun.com/knowledge_detail/39428.html）
net.ipv4.neigh.default.gc_stale_time = 120
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.default.arp_announce = 2
net.ipv4.conf.lo.arp_announce = 2
net.ipv4.conf.all.arp_announce = 2

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

# TCP 优化（见 https://help.aliyun.com/knowledge_detail/41334.html）
# 注：中继节点做 iptables DNAT 纯转发，OS 层 keepalive 对转发流量无效，
#     实际连接保活依赖出口节点/客户端；此处设置仅对中继本机直连生效
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

    CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    if [[ "$CC" == "bbr" ]]; then
        success "BBR 拥塞控制已启用"
    else
        warn "BBR 未生效（当前: ${CC}），可能需要升级内核至 4.9+"
    fi
}

if $DRY_RUN; then
    info "[dry-run] echo 1 > /proc/sys/net/ipv4/ip_forward"
    info "[dry-run] 写入 /etc/sysctl.d/99-vpn-relay.conf（IP 转发 + BBR + TCP 优化）"
else
    enable_ip_forward
    success "IP 转发及网络优化参数已应用（配置: /etc/sysctl.d/99-vpn-relay.conf）"
fi

# ── 配置 iptables 转发规则 ────────────────────────────────────────────────────
step "配置 iptables DNAT 转发规则"

# 先清除可能已存在的旧规则（幂等）
iptables -t nat -D PREROUTING -p tcp --dport "${LISTEN_PORT}" -j DNAT \
    --to-destination "${EXIT_IP}:${EXIT_PORT}" 2>/dev/null || true
iptables -t nat -D POSTROUTING -d "${EXIT_IP}/32" -p tcp -j MASQUERADE 2>/dev/null || true
iptables -D FORWARD -d "${EXIT_IP}/32" -p tcp --dport "${EXIT_PORT}" -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -s "${EXIT_IP}/32" -p tcp --sport "${EXIT_PORT}" -j ACCEPT 2>/dev/null || true

# PREROUTING: 将到达中继 listen_port 的 TCP 流量 DNAT 至出口节点
run iptables -t nat -A PREROUTING \
    -p tcp --dport "${LISTEN_PORT}" \
    -j DNAT --to-destination "${EXIT_IP}:${EXIT_PORT}"

# POSTROUTING: 对转发至出口节点的流量做 MASQUERADE（使出口节点看到中继 IP）
run iptables -t nat -A POSTROUTING \
    -d "${EXIT_IP}/32" -p tcp \
    -j MASQUERADE

# FORWARD: 允许转发链路两个方向的流量
run iptables -A FORWARD \
    -d "${EXIT_IP}/32" -p tcp --dport "${EXIT_PORT}" \
    -j ACCEPT

run iptables -A FORWARD \
    -s "${EXIT_IP}/32" -p tcp --sport "${EXIT_PORT}" \
    -j ACCEPT

success "iptables 转发规则已设置"

# 显示生效规则
if ! $DRY_RUN; then
    echo ""
    info "当前 NAT 表规则（PREROUTING）:"
    iptables -t nat -L PREROUTING -n -v --line-numbers | grep -E "DNAT|Chain" || true
    info "当前 NAT 表规则（POSTROUTING）:"
    iptables -t nat -L POSTROUTING -n -v --line-numbers | grep -E "MASQ|Chain" || true
fi

# ── 持久化 iptables 规则 ──────────────────────────────────────────────────────
step "持久化 iptables 规则（重启后自动恢复）"

persist_iptables_rhel() {
    # RHEL/CentOS 系：安装 iptables-services
    if ! rpm -q iptables-services &>/dev/null; then
        run yum install -y iptables-services
    fi
    run service iptables save
    run systemctl enable iptables
    success "iptables 规则已持久化（iptables-services）"
}

persist_iptables_debian() {
    # Debian/Ubuntu 系：安装 iptables-persistent
    if ! dpkg -l iptables-persistent &>/dev/null 2>&1; then
        run sh -c "DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent"
    fi
    run mkdir -p /etc/iptables
    run sh -c "iptables-save > /etc/iptables/rules.v4"
    success "iptables 规则已持久化（/etc/iptables/rules.v4）"
}

detect_and_persist() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        case "$ID" in
            centos|rhel|almalinux|rocky|alinux|anolis) persist_iptables_rhel ;;
            ubuntu|debian) persist_iptables_debian ;;
            *) warn "未知发行版 $ID，iptables 规则在重启后将丢失，请手动持久化" ;;
        esac
    fi
}

# 使用 systemd oneshot 作为通用持久化备选方案
create_systemd_restore_service() {
    RULES_FILE="/etc/iptables-vpn-relay.rules"
    run sh -c "iptables-save > ${RULES_FILE}"
    chmod 600 "$RULES_FILE"

    cat > /etc/systemd/system/vpn-relay-iptables.service <<EOF
[Unit]
Description=VPN 中继节点 iptables 转发规则恢复
Before=network.target
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore ${RULES_FILE}
ExecStartPost=/bin/sh -c 'echo 1 > /proc/sys/net/ipv4/ip_forward'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    run systemctl daemon-reload
    run systemctl enable vpn-relay-iptables.service
    success "iptables 规则已持久化（systemd: vpn-relay-iptables.service）"
}

if $DRY_RUN; then
    info "[dry-run] 持久化 iptables 规则"
else
    # 优先使用发行版原生工具，失败则退回 systemd 方案
    detect_and_persist 2>/dev/null || create_systemd_restore_service
fi

# ── 配置防火墙放行入站端口 ────────────────────────────────────────────────────
step "开放入站端口 ${LISTEN_PORT}/tcp"

open_firewall() {
    if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
        run firewall-cmd --permanent --add-port="${LISTEN_PORT}/tcp"
        run firewall-cmd --reload
        success "firewalld: 已开放 ${LISTEN_PORT}/tcp"
    elif command -v ufw &>/dev/null; then
        run ufw allow "${LISTEN_PORT}/tcp"
        success "ufw: 已开放 ${LISTEN_PORT}/tcp"
    else
        warn "请在阿里云控制台「安全组」手动放行 ${LISTEN_PORT}/tcp 入方向"
    fi
}

open_firewall

# ── 验证转发是否生效 ──────────────────────────────────────────────────────────
step "验证 IP 转发状态"

if ! $DRY_RUN; then
    IP_FWD=$(cat /proc/sys/net/ipv4/ip_forward)
    if [[ "$IP_FWD" == "1" ]]; then
        success "IP 转发已开启 (/proc/sys/net/ipv4/ip_forward = 1)"
    else
        error "IP 转发未开启！"
        exit 1
    fi
fi

# ── 打印部署摘要 ──────────────────────────────────────────────────────────────
step "部署完成！"

cat <<EOF

${BOLD}━━━ 中继节点信息 ━━━${RESET}
  中继 IP    : ${RELAY_IP}
  监听端口   : ${LISTEN_PORT}
  出口节点   : ${EXIT_IP}:${EXIT_PORT}

${BOLD}━━━ 转发路径 ━━━${RESET}
  客户端 → ${RELAY_IP}:${LISTEN_PORT} → ${EXIT_IP}:${EXIT_PORT} → 目标站点

${BOLD}━━━ 阿里云控制台安全组配置 ━━━${RESET}
  入方向规则：TCP ${LISTEN_PORT} 来源 0.0.0.0/0（或限制为客户端 IP）
  出方向规则：TCP ${EXIT_PORT} 目标 ${EXIT_IP}/32（确保中继能访问出口）

${BOLD}━━━ 常用管理命令 ━━━${RESET}
  查看 NAT 规则  : iptables -t nat -L -n -v
  查看转发规则   : iptables -L FORWARD -n -v
  清除转发规则   : sudo $0 --exit-ip=${EXIT_IP} --listen-port=${LISTEN_PORT} --clean
  检查 IP 转发   : cat /proc/sys/net/ipv4/ip_forward

EOF

echo -e "${GREEN}${BOLD}中继节点部署完成！${RESET}"
