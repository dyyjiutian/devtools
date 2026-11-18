#!/usr/bin/env bash
# =============================================================================
# 网络判定共享库（relay/setup.sh 与 relay/fallback.sh 共用）
# 约定：调用方须 set -euo pipefail；纯函数，无副作用，可 source 测试。
# =============================================================================

set -euo pipefail

# 公网 IP 判定（排除私网/回环/链路本地/CGNAT 100.64/10）
is_public_ip() {
    local ip="${1:-}" a b rest
    [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
    case "$ip" in
        10.*|127.*|169.254.*|192.168.*) return 1 ;;
        172.1[6-9].*|172.2[0-9].*|172.3[01].*) return 1 ;;
    esac
    a="${ip%%.*}"
    rest="${ip#*.}"
    b="${rest%%.*}"
    if [[ "$a" == "100" && "$b" -ge 64 && "$b" -le 127 ]]; then
        return 1
    fi
    return 0
}

# 从 `iptables -t nat -S PREROUTING` 文本（stdin）提取指定端口的 DNAT 目标。
# 用于清扫历史残留（不限目标 IP），Docker 链等非 DNAT 规则不受影响。
legacy_dnat_targets() {
    local port="${1:?legacy_dnat_targets 需要端口}"
    grep -E "^-A PREROUTING .*--dport ${port} .*-j DNAT" \
        | sed -n 's/.*--to-destination \([^ ]*\).*/\1/p'
}

# 探测本机公网 IP：阿里云 metadata（国内直连最可靠）→ 境外 echo 服务 → 网卡公网地址。
# 每一步结果都经 is_public_ip 过滤，避免拿到 docker 网桥/内网地址（hairpin 会失效）。
detect_public_ip() {
    local ip="" cand
    ip=$(curl -sf --connect-timeout 3 http://100.100.100.200/latest/meta-data/eipv4 2>/dev/null || true)
    if ! is_public_ip "$ip"; then
        ip=$(curl -sf --connect-timeout 3 http://100.100.100.200/latest/meta-data/public-ipv4 2>/dev/null || true)
    fi
    if ! is_public_ip "$ip"; then
        ip=$(curl -sf --connect-timeout 5 https://api4.ipify.org 2>/dev/null || true)
    fi
    if ! is_public_ip "$ip"; then
        ip=$(curl -sf --connect-timeout 5 https://ifconfig.me 2>/dev/null || true)
    fi
    if ! is_public_ip "$ip"; then
        for cand in $(hostname -I 2>/dev/null || true); do
            if is_public_ip "$cand"; then
                ip="$cand"
                break
            fi
        done
    fi
    echo "$ip"
}
