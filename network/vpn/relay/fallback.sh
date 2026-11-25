#!/usr/bin/env bash
# =============================================================================
# VPN 中继 WARP 自动兜底子系统（配合 relay/setup.sh 使用）
#
# 主链路保持纯 iptables DNAT（客户端 → 中继:443 → 出口:443）。
# 本脚本在中继上部署「平时不承载流量」的兜底组件：
#   - Cloudflare WARP（proxy 模式，SOCKS5 127.0.0.1:40000）
#   - 备用 xray（127.0.0.1:8443，复用出口同一套 Reality 凭据，客户端零改动）
#   - 健康检查 timer：每 60s 探测出口 443，连续 3 次失败自动把 DNAT 切到
#     备用 xray → WARP；连续 3 次成功自动切回出口。
#
# 用法：sudo ./fallback.sh install --exit-ip=IP --exit-ssh=user@host [--sudo-pass-file=F]
#       sudo ./fallback.sh status | check | switch <main|fallback> | clean
# 权限：root；install 需要到出口的 SSH（读取 Reality 凭据，全程不回显）。
# 回滚：sudo ./fallback.sh clean（恢复主路 DNAT，移除兜底组件；WARP 保留）。
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
step()    { echo -e "\n${BOLD}==> $*${RESET}"; }

# ── 路径（测试可用环境变量覆盖）───────────────────────────────────────────────
FALLBACK_CONF="${VPN_RELAY_CONF:-/etc/vpn-relay-fallback.conf}"
STATE_FILE="${VPN_RELAY_STATE:-/var/lib/vpn-relay-fallback/state.json}"
CONFIG_DIR="${VPN_RELAY_CONFIG_DIR:-/usr/local/etc/xray-relay-fallback}"
LOG_FILE="${VPN_RELAY_LOG:-/var/log/vpn-relay-fallback.log}"
XRAY_BIN="${VPN_XRAY_BIN:-/usr/local/bin/xray}"
SYSTEMCTL_BIN="${VPN_SYSTEMCTL:-systemctl}"
IPTABLES_BIN="${VPN_IPTABLES:-iptables}"
WARP_CLI_BIN="${VPN_WARP_CLI:-warp-cli}"
GEO_DIR="${VPN_GEO_DIR:-/usr/local/share/xray}"
INSTALL_BIN="/usr/local/sbin/vpn-relay-fallback"
INSTALL_LIB_DIR="/usr/local/lib/vpn-relay"
FALLBACK_SERVICE="vpn-relay-fallback.service"
HEALTH_SERVICE="vpn-relay-healthcheck.service"
HEALTH_TIMER="vpn-relay-healthcheck.timer"
WARP_SOCKS_PORT=40000

# ── 参数解析 ──────────────────────────────────────────────────────────────────
DRY_RUN=false
ACTION=""
SWITCH_TARGET=""
EXIT_IP=""
EXIT_PORT=443
LISTEN_PORT=443
FALLBACK_PORT=8443
RELAY_IP=""
THRESHOLD=3
EXIT_SSH=""
SUDO_PASS_FILE=""

usage() {
    cat <<'HELP'
Usage: sudo ./fallback.sh <command> [OPTIONS]

Commands:
  install                部署兜底组件（WARP + 备用 xray + 健康检查 timer）
  check                  执行一次健康检查（timer 调用；手动亦可）
  status                 查看模式 / 计数 / WARP / 服务 / 当前 DNAT 目标
  switch <main|fallback> 手动强制切换（演练 / 运维）
  clean                  移除兜底组件并恢复主路 DNAT（WARP 保留）

Options:
  --exit-ip=IP           出口节点 IP（install 必需；其余命令读配置文件）
  --exit-port=PORT       出口端口（默认 443）
  --listen-port=PORT     中继监听端口（默认 443）
  --fallback-port=PORT   备用 xray 本地端口（默认 8443，仅 127.0.0.1）
  --relay-ip=IP          中继公网 IP（默认自动探测；hairpin 规则用）
  --threshold=N          连续失败/成功 N 次后切换（默认 3，配合 60s timer ≈ 3 分钟）
  --exit-ssh=user@host   install 时读取出口 Reality 凭据的 SSH 目标（必需）
  --sudo-pass-file=FILE  出口 sudo 密码文件（内容经 stdin 传给远端 sudo -S，不回显）
  --dry-run              预览操作，不实际执行
  --help                 显示帮助

前提：已运行 relay/setup.sh（主路 DNAT + route_localnet + conntrack 优化）。
凭据安全：Reality 私钥仅写入 root:600 文件，任何输出/日志不含密钥。
HELP
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        install|check|status|clean) ACTION="$1"; shift ;;
        switch)
            ACTION="switch"
            SWITCH_TARGET="${2:-}"
            [[ "$SWITCH_TARGET" == "main" || "$SWITCH_TARGET" == "fallback" ]] || {
                error "switch 需要目标：main|fallback"; exit 1; }
            shift 2 ;;
        --exit-ip=*)       EXIT_IP="${1#*=}"; shift ;;
        --exit-port=*)     EXIT_PORT="${1#*=}"; shift ;;
        --listen-port=*)   LISTEN_PORT="${1#*=}"; shift ;;
        --fallback-port=*) FALLBACK_PORT="${1#*=}"; shift ;;
        --relay-ip=*)      RELAY_IP="${1#*=}"; shift ;;
        --threshold=*)     THRESHOLD="${1#*=}"; shift ;;
        --exit-ssh=*)      EXIT_SSH="${1#*=}"; shift ;;
        --sudo-pass-file=*) SUDO_PASS_FILE="${1#*=}"; shift ;;
        --dry-run)         DRY_RUN=true; shift ;;
        --help|-h)         usage; exit 0 ;;
        *) error "未知参数: $1"; usage >&2; exit 1 ;;
    esac
done

# ── 共享库与可测试 helper ─────────────────────────────────────────────────────
FALLBACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 共享库解析：repo 内运行用 ../lib；安装态（/usr/local/sbin）用 INSTALL_LIB_DIR。
fallback_lib() {
    local name="$1" d
    for d in "${FALLBACK_DIR}/../lib" "${INSTALL_LIB_DIR}"; do
        if [[ -f "${d}/${name}" ]]; then
            echo "${d}/${name}"
            return 0
        fi
    done
    error "缺少共享库 ${name}（repo 或 ${INSTALL_LIB_DIR}）"
    return 1
}
# shellcheck source=../lib/net.sh
source "$(fallback_lib net.sh)"

# 状态机决策（纯函数）：输入 当前模式/失败计数/成功计数/本次探测/阈值，
# 输出 "新模式 新失败计数 新成功计数 动作"。探测成功清零失败计数，反之亦然。
next_state() {
    local mode="$1" fail="$2" ok="$3" probe_ok="$4" threshold="$5" action="none"
    if [[ "$probe_ok" == "true" ]]; then
        fail=0; ok=$((ok + 1))
    else
        ok=0; fail=$((fail + 1))
    fi
    if [[ "$mode" == "main" && "$fail" -ge "$threshold" ]]; then
        mode="fallback"; action="switch_fallback"
    elif [[ "$mode" == "fallback" && "$ok" -ge "$threshold" ]]; then
        mode="main"; action="switch_main"
    fi
    echo "$mode $fail $ok $action"
}

# TCP 探测出口端口（测试可覆写本函数注入结果）
probe_exit() {
    local ip="$1" port="$2"
    timeout 5 bash -c "</dev/tcp/${ip}/${port}" 2>/dev/null
}

# 校验 Reality 凭据 JSON 结构（不打印任何值）
validate_reality_json() {
    python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
ok = (d.get("dest") and d.get("serverNames") and d.get("privateKey")
      and d.get("shortIds") and d.get("clients")
      and all(c.get("id") for c in d["clients"]))
sys.exit(0 if ok else 1)
' "$1"
}

# 由 Reality 凭据生成备用 xray 配置：
# inbound 127.0.0.1:fallback_port 终结 Reality（与出口同凭据）；
# 路由：私网→block，国内→direct（中继在国内，直连更快），其余→WARP。
build_fallback_config() {
    local reality="$1" out="$2" fport="$3" wport="$4"
    python3 - "$reality" "$out" "$fport" "$wport" <<'PY'
import json, sys
reality = json.load(open(sys.argv[1]))
out_path, fport, wport = sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
cfg = {
    "log": {"loglevel": "warning"},
    "inbounds": [{
        "listen": "127.0.0.1",
        "port": fport,
        "protocol": "vless",
        "settings": {
            "clients": [
                {"id": c["id"], "flow": c.get("flow") or "xtls-rprx-vision",
                 "email": c.get("email", "")}
                for c in reality["clients"]
            ],
            "decryption": "none"
        },
        "streamSettings": {
            "network": "tcp",
            "security": "reality",
            "realitySettings": {
                "show": False,
                "dest": reality["dest"],
                "xver": 0,
                "serverNames": reality["serverNames"],
                "privateKey": reality["privateKey"],
                "shortIds": reality["shortIds"]
            }
        },
        "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"]}
    }],
    "outbounds": [
        {"protocol": "socks", "tag": "warp",
         "settings": {"servers": [{"address": "127.0.0.1", "port": wport}]}},
        {"protocol": "freedom", "tag": "direct",
         "settings": {"domainStrategy": "UseIPv4"}},
        {"protocol": "blackhole", "tag": "block"}
    ],
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {"type": "field", "ip": ["geoip:private"], "outboundTag": "block"},
            {"type": "field", "ip": ["geoip:cn"], "outboundTag": "direct"},
            {"type": "field", "domain": ["geosite:cn"], "outboundTag": "direct"},
            {"type": "field", "network": "tcp,udp", "outboundTag": "warp"}
        ]
    }
}
json.dump(cfg, open(out_path, "w"), indent=2)
PY
    chmod 600 "$out"
}

read_state() {
    if [[ -f "$STATE_FILE" ]]; then
        python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
print(d.get("mode", "main"), d.get("fail", 0), d.get("ok", 0))
' "$STATE_FILE"
    else
        echo "main 0 0"
    fi
}

write_state() { # mode fail ok last_switch
    mkdir -p "$(dirname "$STATE_FILE")"
    python3 -c '
import json, sys
json.dump({"mode": sys.argv[1], "fail": int(sys.argv[2]), "ok": int(sys.argv[3]),
           "last_switch": sys.argv[4]}, open(sys.argv[5], "w"))
' "$1" "$2" "$3" "$4" "$STATE_FILE"
}

state_last_switch() {
    if [[ -f "$STATE_FILE" ]]; then
        python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("last_switch","-"))' "$STATE_FILE"
    else
        echo "-"
    fi
}

# 测试可 source 本脚本复用 helper，避免 root / 系统副作用。
if [[ "${FALLBACK_SOURCE_ONLY:-false}" == "true" ]]; then
    return 0 2>/dev/null || exit 0
fi

# ── 前置检查 ──────────────────────────────────────────────────────────────────
[[ -n "$ACTION" ]] || { usage >&2; exit 1; }
[[ "$(uname)" == "Linux" ]] || { error "兜底子系统仅支持 Linux 中继"; exit 1; }
[[ $EUID -eq 0 ]] || { error "请以 root 权限运行: sudo $0"; exit 1; }
command -v python3 >/dev/null 2>&1 || { error "需要 python3"; exit 1; }

run() {
    if $DRY_RUN; then
        info "[dry-run] $*"
    else
        "$@"
    fi
}

log_event() {
    local line
    line="$(date '+%Y-%m-%d %H:%M:%S') $*"
    echo "$line" >> "$LOG_FILE"
    command -v logger >/dev/null 2>&1 && logger -t vpn-relay-fallback "$*" || true
    info "$*"
}

load_conf() {
    if [[ -f "$FALLBACK_CONF" ]]; then
        # shellcheck source=/dev/null
        source "$FALLBACK_CONF"
    fi
}

detect_relay_ip() {
    if [[ -z "$RELAY_IP" ]]; then
        RELAY_IP=$(detect_public_ip)
    fi
    if [[ -z "$RELAY_IP" ]]; then
        RELAY_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
        warn "未能探测公网 IP，回退 ${RELAY_IP}（hairpin 将跳过）"
    fi
}

# ── DNAT 替换（主路 ⇄ 兜底，同一套标记规则）──────────────────────────────────
replace_dnat() {
    local target="$1" chain line
    for chain in PREROUTING OUTPUT; do
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            # shellcheck disable=SC2086
            run $IPTABLES_BIN -t nat -D "$chain" ${line#-A "$chain" }
        done < <($IPTABLES_BIN -t nat -S "$chain" 2>/dev/null \
            | grep -E "^-A ${chain} .*--dport ${LISTEN_PORT} .*-j DNAT" || true)
    done
    run $IPTABLES_BIN -t nat -A PREROUTING -p tcp --dport "$LISTEN_PORT" \
        -m comment --comment vpn-relay -j DNAT --to-destination "$target"
    if is_public_ip "$RELAY_IP"; then
        run $IPTABLES_BIN -t nat -A OUTPUT -d "${RELAY_IP}/32" -p tcp --dport "$LISTEN_PORT" \
            -m comment --comment vpn-relay -j DNAT --to-destination "$target"
    fi
}

warp_connected() {
    "$WARP_CLI_BIN" --accept-tos status 2>/dev/null | grep -q "Connected"
}

ensure_warp() {
    if warp_connected; then
        return 0
    fi
    "$WARP_CLI_BIN" --accept-tos connect 2>/dev/null || true
    sleep 3
    warp_connected
}

wait_fallback_listening() {
    local i
    for ((i = 0; i < 10; i++)); do
        if timeout 2 bash -c "</dev/tcp/127.0.0.1/${FALLBACK_PORT}" 2>/dev/null; then
            return 0
        fi
        sleep 1
    done
    return 1
}

do_switch() {
    local target="$1"
    if [[ "$target" == "fallback" ]]; then
        if ! ensure_warp; then
            log_event "ERROR: WARP 不可用，保持当前路径（下个周期重试）"
            return 1
        fi
        run $SYSTEMCTL_BIN start "$FALLBACK_SERVICE"
        if ! $DRY_RUN && ! wait_fallback_listening; then
            log_event "ERROR: 备用 xray 未就绪，保持当前路径（下个周期重试）"
            return 1
        fi
        run sysctl -w net.ipv4.conf.all.route_localnet=1 >/dev/null
        replace_dnat "127.0.0.1:${FALLBACK_PORT}"
        log_event "SWITCH: 出口不可达 → 已切换到 WARP 兜底（127.0.0.1:${FALLBACK_PORT}）"
    else
        replace_dnat "${EXIT_IP}:${EXIT_PORT}"
        run $SYSTEMCTL_BIN stop "$FALLBACK_SERVICE"
        log_event "SWITCH: 出口恢复 → 已切回主链路（${EXIT_IP}:${EXIT_PORT}）"
    fi
    write_state "$target" 0 0 "$(date '+%Y-%m-%d %H:%M:%S')"
}

# ── install ───────────────────────────────────────────────────────────────────
fetch_reality() {
    local out="$1" tmp b64
    [[ -n "$EXIT_SSH" ]] || { error "install 需要 --exit-ssh=user@host"; return 1; }
    [[ "$EXIT_SSH" == *@* ]] || { error "--exit-ssh 需要 user@host 形式"; return 1; }
    if [[ -n "$SUDO_PASS_FILE" ]]; then
        [[ -f "$SUDO_PASS_FILE" ]] || { error "密码文件不存在: $SUDO_PASS_FILE"; return 1; }
    fi
    # 远端提取脚本：只输出 JSON 到 stdout（被本地重定向到 600 文件），不回显。
    b64=$(python3 -c '
import base64
src = """
import json
d = json.load(open("/usr/local/etc/xray/config.json"))
for ib in d.get("inbounds", []):
    rs = (ib.get("streamSettings") or {}).get("realitySettings") or {}
    if rs.get("privateKey"):
        out = {"dest": rs.get("dest"), "serverNames": rs.get("serverNames"),
               "privateKey": rs["privateKey"], "shortIds": rs.get("shortIds", []),
               "clients": [{"id": c["id"], "flow": c.get("flow", ""),
                            "email": c.get("email", "")}
                           for c in ib.get("settings", {}).get("clients", [])]}
        print(json.dumps(out))
        break
"""
print(base64.b64encode(src.encode()).decode())
')
    tmp=$(mktemp)
    chmod 600 "$tmp"
    local ssh_opts=(-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
    # root 下按目标用户降权执行 ssh（复用该用户的密钥/known_hosts，而非 root 的）
    local ssh_user="${EXIT_SSH%%@*}"
    local ssh_cmd=(ssh "${ssh_opts[@]}")
    if [[ $EUID -eq 0 && "$ssh_user" != "root" ]]; then
        command -v runuser >/dev/null 2>&1 || { error "需要 runuser 以 ${ssh_user} 身份执行 ssh"; rm -f "$tmp"; return 1; }
        ssh_cmd=(runuser -u "$ssh_user" -- ssh "${ssh_opts[@]}")
    fi
    if [[ -n "$SUDO_PASS_FILE" ]]; then
        if ! cat "$SUDO_PASS_FILE" | "${ssh_cmd[@]}" "$EXIT_SSH" \
            "sudo -S -k bash -c 'echo $b64 | base64 -d | python3'" >"$tmp" 2>/dev/null; then
            rm -f "$tmp"
            error "从出口提取 Reality 凭据失败（SSH/sudo/远端配置问题）"
            return 1
        fi
    else
        if ! "${ssh_cmd[@]}" "$EXIT_SSH" \
            "sudo -n bash -c 'echo $b64 | base64 -d | python3'" >"$tmp" 2>/dev/null; then
            rm -f "$tmp"
            error "从出口提取 Reality 凭据失败（免密 sudo 不可用时请传 --sudo-pass-file）"
            return 1
        fi
    fi
    if ! validate_reality_json "$tmp"; then
        rm -f "$tmp"
        error "出口返回的 Reality 凭据不完整（检查出口 xray 配置）"
        return 1
    fi
    mkdir -p "$CONFIG_DIR"
    mv "$tmp" "${CONFIG_DIR}/reality.json"
    chmod 600 "${CONFIG_DIR}/reality.json"
}

cmd_install() {
    [[ -n "$EXIT_IP" ]] || { error "install 需要 --exit-ip"; exit 1; }
    detect_relay_ip
    step "部署 WARP 兜底子系统（出口 ${EXIT_IP}:${EXIT_PORT}，兜底端口 ${FALLBACK_PORT}）"
    $DRY_RUN && warn "[dry-run] 仅预览，不执行实际操作"

    # 1) WARP（共享库安装逻辑，proxy 模式不接管系统路由）
    if $DRY_RUN; then
        info "[dry-run] 安装/确认 Cloudflare WARP（proxy 模式，SOCKS5 ${WARP_SOCKS_PORT}）"
    else
        # shellcheck source=../lib/warp.sh
        source "$(fallback_lib warp.sh)"
        local os="" version_id=""
        if [[ -f /etc/os-release ]]; then
            # shellcheck source=/dev/null
            source /etc/os-release
            case "$ID" in
                centos|rhel|almalinux|rocky|alinux|anolis) os="rhel" ;;
                ubuntu|debian) os="debian" ;;
                *) error "不支持的发行版: $ID"; exit 1 ;;
            esac
            version_id="${VERSION_ID:-}"
        fi
        if ensure_warp_connected "$os" "$version_id"; then
            success "WARP 已连接（proxy 模式）"
        else
            error "WARP 连接失败；兜底依赖 WARP，请先排查 warp-svc"
            exit 1
        fi
    fi

    # 2) 从出口安全提取 Reality 凭据
    if $DRY_RUN; then
        info "[dry-run] 经 SSH（${EXIT_SSH:-未指定}）提取出口 Reality 凭据 → ${CONFIG_DIR}/reality.json（600，不回显）"
    else
        fetch_reality "${CONFIG_DIR}/reality.json"
        success "Reality 凭据已安全落盘（${CONFIG_DIR}/reality.json，root:600）"
    fi

    # 3) geo 数据（复用客户端安装的数据；缺失时从仓库缓存复制）
    if $DRY_RUN; then
        info "[dry-run] 确认 ${GEO_DIR}/geoip.dat / geosite.dat（缺失时从 cache/binaries 复制）"
    else
        mkdir -p "$GEO_DIR"
        local repo_cache="${FALLBACK_DIR}/../../../cache/binaries"
        local f
        for f in geoip.dat geosite.dat; do
            if [[ ! -s "${GEO_DIR}/${f}" ]]; then
                if [[ -s "${repo_cache}/${f}" ]]; then
                    cp "${repo_cache}/${f}" "${GEO_DIR}/${f}"
                else
                    error "缺少 ${GEO_DIR}/${f}；请先运行 client/linux_setup.sh 或 cache/download.sh"
                    exit 1
                fi
            fi
        done
        success "geo 数据就绪（${GEO_DIR}）"
    fi

    # 4) 备用 xray 配置 + 校验
    if $DRY_RUN; then
        info "[dry-run] 生成备用 xray 配置（127.0.0.1:${FALLBACK_PORT}，国内直连/其余走 WARP）并 xray -test"
    else
        build_fallback_config "${CONFIG_DIR}/reality.json" "${CONFIG_DIR}/config.json" \
            "$FALLBACK_PORT" "$WARP_SOCKS_PORT"
        "$XRAY_BIN" run -test -config "${CONFIG_DIR}/config.json" >/dev/null 2>&1 \
            || { error "备用 xray 配置校验失败"; exit 1; }
        success "备用 xray 配置已生成并通过校验"
    fi

    # 5) 配置文件 + 状态
    if $DRY_RUN; then
        info "[dry-run] 写入 ${FALLBACK_CONF} 与初始状态（mode=main）"
    else
        cat > "$FALLBACK_CONF" <<EOF
# vpn-relay-fallback 配置（fallback.sh install 管理）
EXIT_IP="${EXIT_IP}"
EXIT_PORT=${EXIT_PORT}
LISTEN_PORT=${LISTEN_PORT}
FALLBACK_PORT=${FALLBACK_PORT}
RELAY_IP="${RELAY_IP}"
THRESHOLD=${THRESHOLD}
EXIT_SSH="${EXIT_SSH}"
EOF
        write_state main 0 0 "-"
    fi

    # 6) systemd：备用 xray（enabled 但平时不运行）+ 健康检查 timer
    if $DRY_RUN; then
        info "[dry-run] 安装 ${FALLBACK_SERVICE}（enabled 不启动）+ ${HEALTH_TIMER}（60s）"
        info "[dry-run] 自拷贝到 ${INSTALL_BIN}（timer 调用路径）"
    else
        mkdir -p "$INSTALL_LIB_DIR"
        cp "${FALLBACK_DIR}/setup.sh" "${INSTALL_LIB_DIR}/setup.sh"
        cp "${FALLBACK_DIR}/../lib/net.sh" "${INSTALL_LIB_DIR}/net.sh"
        cp "${FALLBACK_DIR}/../lib/warp.sh" "${INSTALL_LIB_DIR}/warp.sh"
        cp "${BASH_SOURCE[0]}" "$INSTALL_BIN"
        chmod 755 "$INSTALL_BIN"
        # 安装态脚本经 fallback_lib 自动从 INSTALL_LIB_DIR 解析共享库，无需改写

        cat > "/etc/systemd/system/${FALLBACK_SERVICE}" <<EOF
[Unit]
Description=VPN 中继 WARP 兜底备用 Xray（仅兜底时承载流量）
After=network.target warp-svc.service

[Service]
ExecStart=${XRAY_BIN} run -config ${CONFIG_DIR}/config.json
Environment=XRAY_LOCATION_ASSET=${GEO_DIR}
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
        cat > "/etc/systemd/system/${HEALTH_SERVICE}" <<EOF
[Unit]
Description=VPN 中继出口健康检查（失败自动切 WARP 兜底）

[Service]
Type=oneshot
ExecStart=${INSTALL_BIN} check
EOF
        cat > "/etc/systemd/system/${HEALTH_TIMER}" <<EOF
[Unit]
Description=VPN 中继出口健康检查 timer（每 60s）

[Timer]
OnBootSec=90
OnUnitActiveSec=60
AccuracySec=5

[Install]
WantedBy=timers.target
EOF
        $SYSTEMCTL_BIN daemon-reload
        $SYSTEMCTL_BIN enable "$FALLBACK_SERVICE" >/dev/null 2>&1
        $SYSTEMCTL_BIN enable --now "$HEALTH_TIMER"
        success "systemd 就绪：备用 xray enabled（平时不运行），健康检查 timer 已启动"
    fi

    # 7) 主路 DNAT 前提检查
    if ! $DRY_RUN; then
        if $IPTABLES_BIN -t nat -C PREROUTING -p tcp --dport "$LISTEN_PORT" \
            -m comment --comment vpn-relay -j DNAT --to-destination "${EXIT_IP}:${EXIT_PORT}" 2>/dev/null; then
            success "主路 DNAT 已存在（relay/setup.sh 已部署）"
        else
            warn "未检测到主路 DNAT 规则；请先运行 relay/setup.sh --exit-ip=${EXIT_IP}"
        fi
    fi

    step "兜底子系统部署完成"
    cat <<EOF
  主链路   : 客户端 → ${RELAY_IP}:${LISTEN_PORT} → ${EXIT_IP}:${EXIT_PORT}（纯 iptables）
  兜底链路 : 客户端 → ${RELAY_IP}:${LISTEN_PORT} → 127.0.0.1:${FALLBACK_PORT} → WARP(CF)
  切换策略 : 每 60s 探测，连续 ${THRESHOLD} 次失败切兜底 / 连续 ${THRESHOLD} 次成功切回
  查看状态 : sudo $0 status
  手动切换 : sudo $0 switch fallback | main
  演练/日志: tail -f ${LOG_FILE}
  移除兜底 : sudo $0 clean
EOF
}

# ── check（timer 调用）────────────────────────────────────────────────────────
cmd_check() {
    load_conf
    [[ -n "${EXIT_IP:-}" ]] || { error "缺少配置，请先运行 install"; exit 1; }
    detect_relay_ip
    local mode fail ok probe_ok="false" decision new_mode new_fail new_ok action
    read -r mode fail ok <<< "$(read_state)"
    if probe_exit "$EXIT_IP" "$EXIT_PORT"; then
        probe_ok="true"
    fi
    decision="$(next_state "$mode" "$fail" "$ok" "$probe_ok" "$THRESHOLD")"
    read -r new_mode new_fail new_ok action <<< "$decision"
    if $DRY_RUN; then
        info "[dry-run] probe=${probe_ok} → ${decision}"
        return 0
    fi
    # 兜底期间自愈：WARP 掉线重连、备用 xray 意外退出则拉起
    if [[ "$mode" == "fallback" ]]; then
        ensure_warp || log_event "WARN: 兜底期间 WARP 重连失败（下个周期重试）"
        if ! $SYSTEMCTL_BIN is-active --quiet "$FALLBACK_SERVICE"; then
            $SYSTEMCTL_BIN start "$FALLBACK_SERVICE" || true
        fi
    fi
    case "$action" in
        switch_fallback)
            do_switch fallback || write_state "$mode" "$new_fail" "$new_ok" "$(state_last_switch)"
            ;;
        switch_main)
            do_switch main || write_state "$mode" "$new_fail" "$new_ok" "$(state_last_switch)"
            ;;
        *)
            write_state "$new_mode" "$new_fail" "$new_ok" "$(state_last_switch)"
            ;;
    esac
}

# ── status ────────────────────────────────────────────────────────────────────
cmd_status() {
    load_conf
    step "WARP 兜底子系统状态"
    echo "  出口       : ${EXIT_IP:-未配置}:${EXIT_PORT:-443}"
    echo "  中继/监听  : ${RELAY_IP:-?}:${LISTEN_PORT:-443} → 兜底 127.0.0.1:${FALLBACK_PORT:-8443}"
    echo "  切换阈值   : ${THRESHOLD:-3} 次 × 60s"
    if [[ -f "$STATE_FILE" ]]; then
        python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
print("  当前模式   : %s（fail=%s ok=%s，上次切换 %s）" % (
    d.get("mode"), d.get("fail"), d.get("ok"), d.get("last_switch", "-")))
' "$STATE_FILE"
    else
        echo "  当前模式   : 未初始化"
    fi
    echo "  WARP       : $("$WARP_CLI_BIN" --accept-tos status 2>/dev/null | head -1 || echo 未安装)"
    echo "  备用 xray  : $($SYSTEMCTL_BIN is-active "$FALLBACK_SERVICE" 2>/dev/null || true)（enabled: $($SYSTEMCTL_BIN is-enabled "$FALLBACK_SERVICE" 2>/dev/null || true)）"
    echo "  健康检查   : $($SYSTEMCTL_BIN is-active "$HEALTH_TIMER" 2>/dev/null || true)"
    echo "  当前 DNAT  :"
    $IPTABLES_BIN -t nat -S PREROUTING 2>/dev/null \
        | grep -E -- "--dport ${LISTEN_PORT:-443} .*-j DNAT" | sed 's/^/    /' || echo "    无规则"
}

# ── switch / clean ────────────────────────────────────────────────────────────
cmd_switch() {
    load_conf
    [[ -n "${EXIT_IP:-}" ]] || { error "缺少配置，请先运行 install"; exit 1; }
    detect_relay_ip
    do_switch "$SWITCH_TARGET"
}

cmd_clean() {
    load_conf
    step "移除 WARP 兜底子系统"
    run $SYSTEMCTL_BIN disable --now "$HEALTH_TIMER" 2>/dev/null || true
    run $SYSTEMCTL_BIN stop "$FALLBACK_SERVICE" 2>/dev/null || true
    run $SYSTEMCTL_BIN disable "$FALLBACK_SERVICE" 2>/dev/null || true
    run rm -f "/etc/systemd/system/${FALLBACK_SERVICE}" \
        "/etc/systemd/system/${HEALTH_SERVICE}" "/etc/systemd/system/${HEALTH_TIMER}"
    run $SYSTEMCTL_BIN daemon-reload
    if [[ -n "${EXIT_IP:-}" ]]; then
        detect_relay_ip
        replace_dnat "${EXIT_IP}:${EXIT_PORT}"
        success "主路 DNAT 已恢复（${EXIT_IP}:${EXIT_PORT}）"
    fi
    run rm -f "$FALLBACK_CONF" "$STATE_FILE" "$INSTALL_BIN"
    run rm -rf "$CONFIG_DIR" "$INSTALL_LIB_DIR"
    success "兜底组件已移除（WARP 与 ${LOG_FILE} 保留；彻底卸载 WARP 请另行 yum/apt remove）"
}

case "$ACTION" in
    install) cmd_install ;;
    check)   cmd_check ;;
    status)  cmd_status ;;
    switch)  cmd_switch ;;
    clean)   cmd_clean ;;
esac