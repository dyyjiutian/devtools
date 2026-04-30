#!/usr/bin/env bash
# =============================================================================
# 清理旧 VPN 方案（mihomo + WireGuard + gost + tproxy iptables 规则）
# 用法：sudo ./vpn2/cleanup_vpn1.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
step()    { echo -e "\n${BOLD}==> $*${RESET}"; }

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${RESET} 请以 root 权限运行: sudo $0"
    exit 1
fi

# ── 1. 停止并禁用 mihomo ───────────────────────────────────────────────────────
step "停止 mihomo 服务"

# 先强杀进程（绕过 ExecStop 里的 iptables 卡住问题）
MIHOMO_PID=$(pgrep -x mihomo 2>/dev/null || true)
if [[ -n "$MIHOMO_PID" ]]; then
    kill -9 "$MIHOMO_PID" 2>/dev/null && info "kill -9 mihomo (PID ${MIHOMO_PID})" || true
    sleep 1
fi

systemctl disable mihomo 2>/dev/null || true
systemctl reset-failed mihomo 2>/dev/null || true
success "mihomo 已停止"

# ── 2. 停止并禁用 gost ────────────────────────────────────────────────────────
step "停止 gost 服务"

GOST_PID=$(pgrep -x gost 2>/dev/null || true)
if [[ -n "$GOST_PID" ]]; then
    kill -9 "$GOST_PID" 2>/dev/null && info "kill -9 gost (PID ${GOST_PID})" || true
fi

systemctl stop gost 2>/dev/null || true
systemctl disable gost 2>/dev/null || true
success "gost 已停止"

# ── 3. 清除 mihomo tproxy iptables 规则 ──────────────────────────────────────
step "清除 tproxy iptables/ip rule/ip route 规则"

TPROXY_MARK="0x1"
TPROXY_TABLE="100"
WG_IFACE="wg0"
TPROXY_PORT=7893
REDIR_PORT=7892

# 获取 wg0 IP（用于清理 NAT 规则）
WG_SERVER_IP=$(ip -4 addr show "$WG_IFACE" 2>/dev/null | grep -oP '(?<=inet )\d+\.\d+\.\d+\.\d+' | head -1 || echo "")

# mangle 表
iptables -t mangle -D PREROUTING -i "$WG_IFACE" -p tcp --dport 443 -j MIHOMO_TPROXY 2>/dev/null || true
iptables -t mangle -D PREROUTING -i "$WG_IFACE" -p tcp --dport 80  -j MIHOMO_TPROXY 2>/dev/null || true
iptables -t mangle -F MIHOMO_TPROXY 2>/dev/null || true
iptables -t mangle -X MIHOMO_TPROXY 2>/dev/null || true

# ip rule + ip route
ip rule  del fwmark "$TPROXY_MARK" table "$TPROXY_TABLE" 2>/dev/null || true
ip route del local default dev lo table "$TPROXY_TABLE" 2>/dev/null || true

# nat 表（清理可能存在的旧 REDIRECT / DNAT 规则）
iptables -t nat -D PREROUTING -i "$WG_IFACE" -p tcp --dport 443 -j REDIRECT --to-ports "$REDIR_PORT" 2>/dev/null || true
iptables -t nat -D PREROUTING -i "$WG_IFACE" -p tcp --dport 80  -j REDIRECT --to-ports "$REDIR_PORT" 2>/dev/null || true
if [[ -n "$WG_SERVER_IP" ]]; then
    iptables -t nat -D PREROUTING -i "$WG_IFACE" -p tcp --dport 443 -j DNAT --to-destination "${WG_SERVER_IP}:${REDIR_PORT}" 2>/dev/null || true
    iptables -t nat -D PREROUTING -i "$WG_IFACE" -p tcp --dport 80  -j DNAT --to-destination "${WG_SERVER_IP}:${REDIR_PORT}" 2>/dev/null || true
fi

# 清除 WireGuard MASQUERADE（10.8.0.0/24 出 eth0）
iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE 2>/dev/null || true
iptables -t nat -D POSTROUTING -d 198.51.100.30 -j MASQUERADE 2>/dev/null || true  # 旧 vpn2 relay 规则（如有）

success "tproxy 规则已清除"

# ── 4. 停止 WireGuard ─────────────────────────────────────────────────────────
step "停止 WireGuard (wg0)"

systemctl stop "wg-quick@wg0" 2>/dev/null || true
systemctl disable "wg-quick@wg0" 2>/dev/null || true

# wg-quick down 会清理 wg0 路由，但如果服务已卡住则手动删除接口
if ip link show wg0 &>/dev/null; then
    ip link delete wg0 2>/dev/null || true
    info "wg0 接口已删除"
fi

success "WireGuard 已停止"

# ── 5. 验证清理结果 ───────────────────────────────────────────────────────────
step "验证清理结果"

echo ""
info "剩余相关进程："
pgrep -a -E "mihomo|clash|gost|wg" 2>/dev/null || echo "  (无)"

echo ""
info "网络接口："
ip link show | grep -E "wg|tun" || echo "  (无 wg/tun 接口)"

echo ""
info "NAT 表 POSTROUTING（应只剩 Docker 规则）："
iptables -t nat -L POSTROUTING -n --line-numbers 2>/dev/null || echo "  (无法读取)"

echo ""
info "ip rule 列表："
ip rule list

echo ""
success "旧 VPN 方案清理完成！"
echo ""
echo -e "${BOLD}━━━ 下一步 ━━━${RESET}"
echo "  部署新方案请按 vpn2/README.md 操作："
echo "  1. 新加坡出口节点: sudo ./vpn2/exit/setup.sh"
echo "  2. 杭州中继节点:   sudo ./vpn2/relay/setup.sh"
echo "  3. 本机客户端:     sudo ./vpn2/client/setup.sh --uuid=... --public-key=... --short-id=..."
