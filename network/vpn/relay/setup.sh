#!/usr/bin/env bash
# =============================================================================
# VPN 中继节点部署脚本 - 杭州 ECS (198.51.100.10)
# 方案：iptables DNAT 透明转发，主链路无需任何代理软件
#       内核优化（BBR + conntrack + route_localnet）；可选 WARP 兜底见 fallback.sh
# 用法：sudo ./relay/setup.sh --exit-ip=198.51.100.21 [--exit-port=443] [--listen-port=443] [--dry-run]
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
RELAY_IP=""
ACTION="setup"

for arg in "$@"; do
    case $arg in
        --exit-ip=*)     EXIT_IP="${arg#*=}" ;;
        --exit-port=*)   EXIT_PORT="${arg#*=}" ;;
        --listen-port=*) LISTEN_PORT="${arg#*=}" ;;
        --relay-ip=*)    RELAY_IP="${arg#*=}" ;;
        --dry-run)       DRY_RUN=true ;;
        --clean)         ACTION="clean" ;;
        --help|-h)
            echo "Usage: sudo $0 --exit-ip=<EXIT_IP> [OPTIONS]"
            echo ""
            echo "必需参数:"
            echo "  --exit-ip=IP      出口节点 IP（例：198.51.100.21，东京）"
            echo ""
            echo "可选参数:"
            echo "  --exit-port=PORT     出口节点端口（默认 443）"
            echo "  --listen-port=PORT   中继节点监听端口（默认 443）"
            echo "  --relay-ip=IP        中继公网 IP（默认自动探测；hairpin 规则用）"
            echo "  --dry-run            预览操作，不实际执行"
            echo "  --clean              清除 iptables 转发规则（含历史残留与 hairpin）"
            echo "  --help               显示帮助"
            echo ""
            echo "部署内容:"
            echo "  - 内核优化：ip_forward + BBR + conntrack + route_localnet（兜底必需）"
            echo "  - PREROUTING DNAT：<listen-port> → <exit-ip>:<exit-port>（先清扫同端口旧规则）"
            echo "  - OUTPUT hairpin：本机客户端访问自身公网 IP 也走同一条转发/兜底路径"
            echo "  - 规则持久化（重启自动恢复）；WARP 自动兜底另见 relay/fallback.sh"
            exit 0
            ;;
        *) warn "未知参数: $arg" ;;
    esac
done

# ── 共享库：网络判定 helper（与 fallback.sh 共用）─────────────────────────────
RELAY_SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/net.sh
source "${RELAY_SETUP_DIR}/../lib/net.sh"

# ── 可 source 测试的 helper ───────────────────────────────────────────────────
# 中继内核参数（DNAT 转发 + BBR + conntrack + 兜底所需 route_localnet）
write_relay_sysctl() {
    local conf="${1:-/etc/sysctl.d/99-vpn-relay.conf}"
    cat > "$conf" <<'SYSCTL'
# VPN 中继节点 - IP 转发 + 网络性能优化（relay/setup.sh 管理，重跑幂等覆盖）

vm.swappiness = 0
kernel.sysrq = 1

# IP 转发（DNAT 必需）
net.ipv4.ip_forward = 1

# 关闭 ICMP 重定向（避免路由泄漏）
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# 兜底子系统：DNAT 到 127.0.0.1 的备用 xray 需要 route_localnet
net.ipv4.conf.all.route_localnet = 1
net.ipv4.conf.default.route_localnet = 1

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
net.core.netdev_max_backlog = 16384
net.core.somaxconn = 4096

# 软中断预算：高 pps 下减少 time_squeeze（每轮 NAPI 处理更多包）
net.core.netdev_budget = 600
net.core.netdev_budget_usecs = 4000

# conntrack：DNAT 中继是 conntrack 密集型；默认 established 超时 5 天过长，
# 收紧超时避免死连接占满表项（nf_conntrack_max 默认 65536 偏小）
net.netfilter.nf_conntrack_max = 262144
net.netfilter.nf_conntrack_tcp_timeout_established = 3600
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_syn_sent = 30
net.netfilter.nf_conntrack_tcp_timeout_syn_recv = 30
net.netfilter.nf_conntrack_udp_timeout = 60
net.netfilter.nf_conntrack_icmp_timeout = 15
net.netfilter.nf_conntrack_generic_timeout = 60
# 跨境链路丢包/重排常见：放宽窗口检查，减少重传包被误判 INVALID 而丢 NAT 状态
net.netfilter.nf_conntrack_tcp_be_liberal = 1

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
}

# RPS CPU 掩码：n 核 → 低 n 位置 1 的十六进制（2 核→3，4 核→f）
rps_mask() {
    local n="${1:-1}"
    [[ "$n" =~ ^[0-9]+$ ]] || return 1
    (( n >= 1 && n <= 64 )) || return 1
    printf '%x' $(( (1 << n) - 1 ))
}

# 测试可 source 本脚本复用 helper，避免 root / 系统副作用。
if [[ "${RELAY_SETUP_SOURCE_ONLY:-false}" == "true" ]]; then
    return 0 2>/dev/null || exit 0
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

# 如果未传 --exit-ip，使用默认出口 IP
if [[ -z "$EXIT_IP" ]]; then
    EXIT_IP="198.51.100.21"
    warn "未指定 --exit-ip，使用默认出口 IP: ${EXIT_IP}"
fi

if [[ -z "$RELAY_IP" ]]; then
    RELAY_IP=$(detect_public_ip)
fi
if [[ -z "$RELAY_IP" ]]; then
    RELAY_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    warn "未能探测公网 IP，回退 ${RELAY_IP}（hairpin 将跳过；可用 --relay-ip 指定）"
fi
info "中继节点 IP : ${RELAY_IP}"
info "出口节点    : ${EXIT_IP}:${EXIT_PORT}"
info "监听端口    : ${LISTEN_PORT}"

$DRY_RUN && warn "[dry-run] 仅预览，不执行实际操作"

# ── 清扫转发规则（历史残留 + 标记规则；保留 Docker 链）────────────────────────
# 枚举 PREROUTING 中本端口全部 DNAT 规则（不限目标），连带清理对应目标的
# MASQUERADE / FORWARD；再清 OUTPUT 上带 vpn-relay 标记的 hairpin 旧规则。
sweep_relay_rules() {
    local targets target line tip tport
    targets="$(iptables -t nat -S PREROUTING 2>/dev/null | legacy_dnat_targets "$LISTEN_PORT" || true)"
    for target in $targets; do
        tip="${target%%:*}"
        tport="${target##*:}"
        [[ "$tport" == "$tip" ]] && tport="$EXIT_PORT"
        iptables -t nat -D POSTROUTING -d "${tip}/32" -p tcp -j MASQUERADE 2>/dev/null || true
        iptables -D FORWARD -d "${tip}/32" -p tcp --dport "${tport}" -j ACCEPT 2>/dev/null || true
        iptables -D FORWARD -s "${tip}/32" -p tcp --sport "${tport}" -j ACCEPT 2>/dev/null || true
    done
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        # shellcheck disable=SC2086
        iptables -t nat -D PREROUTING ${line#-A PREROUTING } 2>/dev/null || true
    done < <(iptables -t nat -S PREROUTING 2>/dev/null \
        | grep -E "^-A PREROUTING .*--dport ${LISTEN_PORT} .*-j DNAT" || true)
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        # shellcheck disable=SC2086
        iptables -t nat -D OUTPUT ${line#-A OUTPUT } 2>/dev/null || true
    done < <(iptables -t nat -S OUTPUT 2>/dev/null | grep -- '--comment vpn-relay' || true)
    # 当前出口方向的 FORWARD 放行规则（可能由旧版本脚本写入，无标记）
    iptables -D FORWARD -d "${EXIT_IP}/32" -p tcp --dport "${EXIT_PORT}" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -s "${EXIT_IP}/32" -p tcp --sport "${EXIT_PORT}" -j ACCEPT 2>/dev/null || true
    # mangle 表 TCPMSS 钳制规则（带标记）
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        # shellcheck disable=SC2086
        iptables -t mangle -D FORWARD ${line#-A FORWARD } 2>/dev/null || true
    done < <(iptables -t mangle -S FORWARD 2>/dev/null | grep -- '--comment vpn-relay' || true)
}

# ── NIC 调优：fq qdisc + 单队列 RPS（高并发 pps 关键）─────────────────────────
tune_nic() {
    local iface ncpu rxq_count mask
    iface=$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')
    [[ -n "$iface" ]] || { warn "未找到默认路由网卡，跳过 NIC 调优"; return 0; }

    # fq qdisc：BBR pacing 的最佳搭档（内核 >=4.13 BBR 自带 pacing，缺 tc 不阻塞）
    if ! command -v tc >/dev/null 2>&1; then
        if [[ -f /etc/os-release ]]; then
            # shellcheck source=/dev/null
            source /etc/os-release
            case "$ID" in
                centos|rhel|almalinux|rocky|alinux|anolis) yum install -y iproute-tc >/dev/null 2>&1 || true ;;
                ubuntu|debian) apt-get install -y iproute2 >/dev/null 2>&1 || true ;;
            esac
        fi
    fi
    if command -v tc >/dev/null 2>&1; then
        if tc qdisc replace dev "$iface" root fq 2>/dev/null; then
            success "qdisc: ${iface} → fq（BBR pacing）"
        else
            warn "qdisc 替换失败（容器内常见），跳过"
        fi
    else
        warn "tc 不可用，跳过 qdisc 设置（BBR 内核自带 pacing 仍生效）"
    fi

    # RPS：单队列网卡把软中断分散到所有核（多队列网卡无需，跳过）
    ncpu=$(nproc 2>/dev/null || echo 1)
    rxq_count=$(ls "/sys/class/net/${iface}/queues/" 2>/dev/null | grep -c '^rx-' || true)
    if [[ "$rxq_count" == "1" && "$ncpu" -gt 1 ]]; then
        mask=$(rps_mask "$ncpu")
        if echo "$mask" > "/sys/class/net/${iface}/queues/rx-0/rps_cpus" 2>/dev/null; then
            success "RPS: ${iface} 单队列软中断分散到 ${ncpu} 核（mask=${mask}）"
            # 持久化：重启后网卡队列重建会丢 rps_cpus
            cat > /etc/systemd/system/vpn-relay-rps.service <<EOF
[Unit]
Description=VPN relay RPS - spread single-queue NIC softirqs across cores
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo ${mask} > /sys/class/net/${iface}/queues/rx-0/rps_cpus'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload
            systemctl enable vpn-relay-rps.service >/dev/null 2>&1
        else
            warn "RPS 设置失败（容器/权限限制），跳过"
        fi
    else
        info "NIC ${iface}: ${rxq_count} 个 RX 队列 / ${ncpu} 核，无需 RPS"
    fi
}

# ── 清除规则模式 ──────────────────────────────────────────────────────────────
if [[ "$ACTION" == "clean" ]]; then
    step "清除 iptables 转发规则（含历史残留与 hairpin）"
    if $DRY_RUN; then
        info "[dry-run] 清扫 PREROUTING/OUTPUT/POSTROUTING/FORWARD 中本脚本管理的规则"
        info "[dry-run] 停用并移除 vpn-relay-rps.service，恢复 rps_cpus=0"
    else
        sweep_relay_rules
        systemctl disable --now vpn-relay-rps.service 2>/dev/null || true
        rm -f /etc/systemd/system/vpn-relay-rps.service
        systemctl daemon-reload
        CLEAN_IFACE=$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')
        if [[ -n "$CLEAN_IFACE" ]]; then
            echo 0 > "/sys/class/net/${CLEAN_IFACE}/queues/rx-0/rps_cpus" 2>/dev/null || true
        fi
    fi
    success "iptables 转发规则已清除"
fi

# ── 启用 IP 转发 + 内核优化 ───────────────────────────────────────────────────
if [[ "$ACTION" != "clean" ]]; then
    step "开启内核 IP 转发 + 网络优化（BBR / conntrack / route_localnet）"
    if $DRY_RUN; then
        info "[dry-run] echo 1 > /proc/sys/net/ipv4/ip_forward"
        info "[dry-run] 写入 /etc/sysctl.d/99-vpn-relay.conf（IP 转发 + BBR + conntrack + route_localnet + 软中断预算）"
        info "[dry-run] NIC 调优：默认网卡 qdisc→fq；单队列多核时启用 RPS 并持久化（vpn-relay-rps.service）"
    else
        echo 1 > /proc/sys/net/ipv4/ip_forward
        modprobe nf_conntrack 2>/dev/null || true
        write_relay_sysctl /etc/sysctl.d/99-vpn-relay.conf
        sysctl -p /etc/sysctl.d/99-vpn-relay.conf > /dev/null \
            || warn "部分内核参数未能立即生效（容器内常见）"
        # conntrack 哈希表（运行时 + 持久化），与 nf_conntrack_max 匹配（max/4）
        if [[ -w /sys/module/nf_conntrack/parameters/hashsize ]]; then
            echo 65536 > /sys/module/nf_conntrack/parameters/hashsize 2>/dev/null || true
        fi
        mkdir -p /etc/modprobe.d
        printf 'options nf_conntrack hashsize=65536\n' > /etc/modprobe.d/vpn-relay-conntrack.conf
        tune_nic
        CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
        if [[ "$CC" == "bbr" ]]; then
            success "BBR 拥塞控制已启用"
        else
            warn "BBR 未生效（当前: ${CC}），可能需要升级内核至 4.9+"
        fi
        success "IP 转发及网络优化参数已应用（配置: /etc/sysctl.d/99-vpn-relay.conf）"
    fi
fi

# ── 配置 iptables 转发规则 ────────────────────────────────────────────────────
if [[ "$ACTION" != "clean" ]]; then
    step "配置 iptables DNAT 转发规则"
    if $DRY_RUN; then
        info "[dry-run] 清扫同端口历史 DNAT/MASQUERADE/FORWARD 规则（保留 Docker 链）"
        info "[dry-run] iptables -t nat -A PREROUTING -p tcp --dport ${LISTEN_PORT} -m comment --comment vpn-relay -j DNAT --to-destination ${EXIT_IP}:${EXIT_PORT}"
        info "[dry-run] iptables -t nat -A POSTROUTING -d ${EXIT_IP}/32 -p tcp -j MASQUERADE"
        info "[dry-run] iptables -A FORWARD -d/-s ${EXIT_IP}/32 -p tcp --dport/--sport ${EXIT_PORT} -j ACCEPT"
        info "[dry-run] iptables -t mangle -A FORWARD -d/-s ${EXIT_IP}/32 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1380（跨境 PMTUD 黑洞防护）"
        if is_public_ip "$RELAY_IP"; then
            info "[dry-run] iptables -t nat -A OUTPUT -d ${RELAY_IP}/32 -p tcp --dport ${LISTEN_PORT} -m comment --comment vpn-relay -j DNAT --to-destination ${EXIT_IP}:${EXIT_PORT}（本机 hairpin）"
        fi
    else
        # 先清扫历史残留与旧规则（幂等；避免新旧 DNAT 并存时旧规则优先命中）
        sweep_relay_rules

        # PREROUTING: 将到达中继 listen_port 的 TCP 流量 DNAT 至出口节点
        iptables -t nat -A PREROUTING \
            -p tcp --dport "${LISTEN_PORT}" \
            -m comment --comment vpn-relay \
            -j DNAT --to-destination "${EXIT_IP}:${EXIT_PORT}"

        # POSTROUTING: 对转发至出口节点的流量做 MASQUERADE（使出口节点看到中继 IP）
        iptables -t nat -A POSTROUTING \
            -d "${EXIT_IP}/32" -p tcp \
            -j MASQUERADE

        # FORWARD: 允许转发链路两个方向的流量
        iptables -A FORWARD \
            -d "${EXIT_IP}/32" -p tcp --dport "${EXIT_PORT}" \
            -j ACCEPT
        iptables -A FORWARD \
            -s "${EXIT_IP}/32" -p tcp --sport "${EXIT_PORT}" \
            -j ACCEPT

        # TCPMSS 钳制：跨境段常见 PMTUD 黑洞（路径 MTU < 1500 且 ICMP frag-needed
        # 被丢），1460 的大包静默丢弃导致吞吐崩塌（小请求正常、下载极慢）。
        # 把转发 TCP 的 MSS 钳到 1380（IP 包 ≤1420），所有客户端一次生效。
        iptables -t mangle -A FORWARD -d "${EXIT_IP}/32" -p tcp --tcp-flags SYN,RST SYN \
            -m comment --comment vpn-relay -j TCPMSS --set-mss 1380
        iptables -t mangle -A FORWARD -s "${EXIT_IP}/32" -p tcp --tcp-flags SYN,RST SYN \
            -m comment --comment vpn-relay -j TCPMSS --set-mss 1380

        # OUTPUT hairpin: 本机客户端访问自身公网 IP:listen_port 也走同一条 DNAT，
        # 与外部终端共用兜底切换路径（仅公网 IP 有意义；私网/容器环境跳过）
        if is_public_ip "$RELAY_IP"; then
            iptables -t nat -A OUTPUT \
                -d "${RELAY_IP}/32" -p tcp --dport "${LISTEN_PORT}" \
                -m comment --comment vpn-relay \
                -j DNAT --to-destination "${EXIT_IP}:${EXIT_PORT}"
            success "本机 hairpin 规则已设置（${RELAY_IP}:${LISTEN_PORT} → 出口）"
        else
            warn "RELAY_IP=${RELAY_IP} 非公网 IP，跳过本机 hairpin 规则"
        fi
        success "iptables 转发规则已设置"

        echo ""
        info "当前 NAT 表规则（PREROUTING）:"
        iptables -t nat -L PREROUTING -n -v --line-numbers | grep -E "DNAT|Chain" || true
        info "当前 NAT 表规则（POSTROUTING）:"
        iptables -t nat -L POSTROUTING -n -v --line-numbers | grep -E "MASQ|Chain" || true
    fi
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
if [[ "$ACTION" != "clean" ]]; then
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
fi

# ── 验证转发是否生效 ──────────────────────────────────────────────────────────
if [[ "$ACTION" != "clean" ]] && ! $DRY_RUN; then
    step "验证 IP 转发状态"
    IP_FWD=$(cat /proc/sys/net/ipv4/ip_forward)
    if [[ "$IP_FWD" == "1" ]]; then
        success "IP 转发已开启 (/proc/sys/net/ipv4/ip_forward = 1)"
    else
        error "IP 转发未开启！"
        exit 1
    fi
fi

# ── 打印部署摘要 ──────────────────────────────────────────────────────────────
if [[ "$ACTION" == "clean" ]]; then
    echo -e "${GREEN}${BOLD}中继转发规则已清除！${RESET}"
    exit 0
fi

step "部署完成！"

cat <<EOF

${BOLD}━━━ 中继节点信息 ━━━${RESET}
  中继 IP    : ${RELAY_IP}
  监听端口   : ${LISTEN_PORT}
  出口节点   : ${EXIT_IP}:${EXIT_PORT}

${BOLD}━━━ 转发路径 ━━━${RESET}
  客户端 → ${RELAY_IP}:${LISTEN_PORT} → ${EXIT_IP}:${EXIT_PORT} → 目标站点
  本机客户端 → ${RELAY_IP}:${LISTEN_PORT}（OUTPUT hairpin）→ 同上

${BOLD}━━━ 阿里云控制台安全组配置 ━━━${RESET}
  入方向规则：TCP ${LISTEN_PORT} 来源 0.0.0.0/0（或限制为客户端 IP）
  出方向规则：TCP ${EXIT_PORT} 目标 ${EXIT_IP}/32（确保中继能访问出口）

${BOLD}━━━ 常用管理命令 ━━━${RESET}
  查看 NAT 规则  : iptables -t nat -L -n -v
  查看转发规则   : iptables -L FORWARD -n -v
  清除转发规则   : sudo $0 --exit-ip=${EXIT_IP} --listen-port=${LISTEN_PORT} --clean
  检查 IP 转发   : cat /proc/sys/net/ipv4/ip_forward
  WARP 自动兜底  : sudo ./fallback.sh --help（健康检查 + 被封自动切换）

EOF

echo -e "${GREEN}${BOLD}中继节点部署完成！${RESET}"