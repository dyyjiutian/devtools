#!/usr/bin/env bash
# =============================================================================
# VPN 出口节点用户管理脚本
# 用法：sudo ./exit/manage.sh <command> [args]
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; CYAN='\033[0;36m'; RESET='\033[0m'

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

# Paths are overridable for regression tests (see manage_test.sh).
CONFIG_CACHE="${VPN_EXIT_CONFIG:-/root/.vpn_exit_config}"
XRAY_BIN="${VPN_XRAY_BIN:-/usr/local/bin/xray}"
XRAY_CONFIG="${VPN_XRAY_CONFIG:-/usr/local/etc/xray/config.json}"
XRAY_LOG_DIR="/var/log/xray"
STATS_SERVER="${VPN_STATS_SERVER:-127.0.0.1:10085}"
QUOTA_LOG="/var/log/vpn-quota.log"
TRAFFIC_STORE="${VPN_TRAFFIC_STORE:-/var/lib/vpn-exit/traffic.tsv}"
SYSTEMCTL_BIN="${VPN_SYSTEMCTL:-systemctl}"

# ── 配置加载/写入 ──────────────────────────────────────────────────────────────
load_config() {
    [[ -f "$CONFIG_CACHE" ]] || {
        error "配置文件不存在: ${CONFIG_CACHE}"
        error "请先在出口节点运行 exit/setup.sh"
        exit 1
    }
    # shellcheck source=/dev/null
    source "$CONFIG_CACHE"
    [[ -n "${USERS:-}" ]] || {
        error "配置格式错误，缺少 USERS 字段（请重新运行 exit/setup.sh）"
        exit 1
    }
}

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

# ── 持久化流量（跨 Xray restart；仅 reset-stats / 月度 cron 清零）──────────────
traffic_store_get() {
    local user="$1"
    local up=0 down=0 u u_up u_down
    if [[ -f "$TRAFFIC_STORE" ]]; then
        while IFS=$'\t' read -r u u_up u_down || [[ -n "${u:-}" ]]; do
            [[ -n "${u:-}" ]] || continue
            [[ "$u" == "$user" ]] || continue
            up="${u_up:-0}"
            down="${u_down:-0}"
            break
        done < "$TRAFFIC_STORE"
    fi
    echo "${up} ${down}"
}

traffic_store_set() {
    local user="$1" up="$2" down="$3"
    local dir tmp u u_up u_down
    dir=$(dirname "$TRAFFIC_STORE")
    mkdir -p "$dir"
    tmp=$(mktemp "${dir}/.traffic.XXXXXX")
    if [[ -f "$TRAFFIC_STORE" ]]; then
        while IFS=$'\t' read -r u u_up u_down || [[ -n "${u:-}" ]]; do
            [[ -n "${u:-}" ]] || continue
            [[ "$u" == "$user" ]] && continue
            printf '%s\t%s\t%s\n' "$u" "$u_up" "$u_down"
        done < "$TRAFFIC_STORE" >"$tmp"
    else
        : >"$tmp"
    fi
    printf '%s\t%s\t%s\n' "$user" "$up" "$down" >>"$tmp"
    mv -f "$tmp" "$TRAFFIC_STORE"
    chmod 600 "$TRAFFIC_STORE" 2>/dev/null || true
}

traffic_store_add() {
    local user="$1" d_up="$2" d_down="$3"
    local up down
    read -r up down < <(traffic_store_get "$user")
    traffic_store_set "$user" "$((up + d_up))" "$((down + d_down))"
}

traffic_store_clear() {
    local target="${1:-all}"
    local dir tmp u u_up u_down
    if [[ "$target" == "all" ]]; then
        rm -f "$TRAFFIC_STORE"
        return 0
    fi
    [[ -f "$TRAFFIC_STORE" ]] || return 0
    dir=$(dirname "$TRAFFIC_STORE")
    tmp=$(mktemp "${dir}/.traffic.XXXXXX")
    while IFS=$'\t' read -r u u_up u_down || [[ -n "${u:-}" ]]; do
        [[ -n "${u:-}" ]] || continue
        [[ "$u" == "$target" ]] && continue
        printf '%s\t%s\t%s\n' "$u" "$u_up" "$u_down"
    done < "$TRAFFIC_STORE" >"$tmp"
    mv -f "$tmp" "$TRAFFIC_STORE"
}

# Capture live Stats API counters for current USERS into a TSV snapshot file.
snapshot_live_traffic() {
    local snap_file="$1"
    local u up down
    : >"$snap_file"
    for u in $USERS; do
        read -r up down < <(get_user_session_traffic "$u")
        printf '%s\t%s\t%s\n' "$u" "${up:-0}" "${down:-0}" >>"$snap_file"
    done
}

commit_traffic_snapshot() {
    local snap_file="$1"
    local u up down
    [[ -f "$snap_file" ]] || return 0
    while IFS=$'\t' read -r u up down || [[ -n "${u:-}" ]]; do
        [[ -n "${u:-}" ]] || continue
        up="${up:-0}"
        down="${down:-0}"
        [[ "$up" == "0" && "$down" == "0" ]] && continue
        traffic_store_add "$u" "$up" "$down"
    done < "$snap_file"
}

# ── Xray 配置热更新（仅更新 clients 数组，其余设置保持不变）────────────────────
reload_xray_clients() {
    [[ -f "$XRAY_CONFIG" ]] || {
        error "Xray 配置文件不存在: ${XRAY_CONFIG}，请先运行 exit/setup.sh"
        exit 1
    }

    # Snapshot in-memory counters before restart wipes them.
    local snap_file
    snap_file=$(mktemp)
    snapshot_live_traffic "$snap_file"

    # 构造 clients JSON 字符串（单行，传给 Python）
    local clients_arr="["
    local first=true
    for u in $USERS; do
        local uuid_var="USER_${u}_UUID"
        $first || clients_arr="${clients_arr},"
        first=false
        clients_arr="${clients_arr}{\"id\":\"${!uuid_var}\",\"flow\":\"xtls-rprx-vision\",\"email\":\"${u}@vpn\"}"
    done
    clients_arr="${clients_arr}]"

    VPN_XRAY_CONFIG="$XRAY_CONFIG" python3 - "$clients_arr" <<'PYEOF'
import json, os, sys

clients = json.loads(sys.argv[1])
config_path = os.environ.get('VPN_XRAY_CONFIG', '/usr/local/etc/xray/config.json')

with open(config_path) as f:
    config = json.load(f)

# 确保 Stats API 配置存在（兼容旧配置）
config.setdefault('stats', {})
config.setdefault('api', {'tag': 'api', 'services': ['StatsService']})
config.setdefault('policy', {
    'levels': {'0': {'statsUserUplink': True, 'statsUserDownlink': True}},
    'system': {'statsInboundUplink': True, 'statsInboundDownlink': True}
})

inbounds = config.setdefault('inbounds', [])

# 确保 API inbound 存在
if not any(i.get('tag') == 'api' for i in inbounds):
    inbounds.insert(0, {
        'listen': '127.0.0.1', 'port': 10085,
        'protocol': 'dokodemo-door',
        'settings': {'address': '127.0.0.1'},
        'tag': 'api'
    })

# 确保 API routing rule 存在
routing = config.setdefault('routing', {})
rules = routing.setdefault('rules', [])
if not any(r.get('inboundTag') == ['api'] for r in rules):
    rules.insert(0, {'type': 'field', 'inboundTag': ['api'], 'outboundTag': 'api'})

# 更新 VLESS clients
for inbound in inbounds:
    if inbound.get('protocol') == 'vless':
        inbound['settings']['clients'] = clients
        break

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
PYEOF

    "$SYSTEMCTL_BIN" restart xray
    [[ "${MANAGE_SOURCE_ONLY:-false}" == "true" ]] || sleep 1
    if "$SYSTEMCTL_BIN" is-active --quiet xray; then
        # Only commit after a successful restart so we never double-count a live session.
        commit_traffic_snapshot "$snap_file"
        rm -f "$snap_file"
        success "Xray 已重载（${#USERS} 个用户）"
    else
        rm -f "$snap_file"
        error "Xray 重载失败: journalctl -u xray -n 20"
        exit 1
    fi
}

# ── 流量统计工具 ───────────────────────────────────────────────────────────────
bytes_to_human() {
    local bytes="${1:-0}"
    [[ "$bytes" =~ ^[0-9]+$ ]] || { echo "-"; return; }
    if   (( bytes < 1024 ));       then printf "%d B"     "$bytes"
    elif (( bytes < 1048576 ));    then printf "%.1f KB"  "$(echo "scale=1; $bytes/1024" | bc)"
    elif (( bytes < 1073741824 )); then printf "%.1f MB"  "$(echo "scale=1; $bytes/1048576" | bc)"
    else                                printf "%.2f GB"  "$(echo "scale=2; $bytes/1073741824" | bc)"
    fi
}

# Raw Stats API counters for the current Xray process (lost on restart).
get_user_session_traffic() {
    local user="$1"
    local email="${user}@vpn"
    local up=0 down=0 val

    val=$("$XRAY_BIN" api stats --server="$STATS_SERVER" \
        -name "user>>>${email}>>>traffic>>>uplink" 2>/dev/null \
        | sed -n 's/.*"value":[[:space:]]*"*\([0-9][0-9]*\).*/\1/p' | head -1)
    up="${val:-0}"

    val=$("$XRAY_BIN" api stats --server="$STATS_SERVER" \
        -name "user>>>${email}>>>traffic>>>downlink" 2>/dev/null \
        | sed -n 's/.*"value":[[:space:]]*"*\([0-9][0-9]*\).*/\1/p' | head -1)
    down="${val:-0}"

    echo "${up} ${down}"
}

# Billed traffic = persisted (survives reload) + current session.
get_user_traffic() {
    local user="$1"
    local store_up=0 store_down=0 live_up=0 live_down=0
    read -r store_up store_down < <(traffic_store_get "$user")
    read -r live_up live_down < <(get_user_session_traffic "$user")
    echo "$((store_up + live_up)) $((store_down + live_down))"
}

stats_api_alive() {
    "$XRAY_BIN" api statsquery --server="$STATS_SERVER" -pattern "" &>/dev/null 2>&1
}

# ── 命令：list ─────────────────────────────────────────────────────────────────
cmd_list() {
    load_config
    local alive=true
    stats_api_alive || alive=false

    echo ""
    printf "${BOLD}%-14s  %-8s  %-12s  %-12s  %-14s${RESET}\n" \
        "用户" "配额" "上行" "下行" "合计"
    printf '%0.s─' {1..64}; echo

    for u in $USERS; do
        local uuid_var="USER_${u}_UUID"
        local quota_var="USER_${u}_QUOTA_GB"
        local quota="${!quota_var:-0}"
        local quota_str="${quota} GB"
        [[ "$quota" == "0" ]] && quota_str="∞"

        local up_str="-" down_str="-" total_str="-"
        if $alive; then
            local up down total
            read -r up down < <(get_user_traffic "$u")
            total=$(( up + down ))
            up_str=$(bytes_to_human "$up")
            down_str=$(bytes_to_human "$down")
            total_str=$(bytes_to_human "$total")

            # 配额警告色
            if [[ "$quota" != "0" ]]; then
                local quota_bytes=$(( quota * 1073741824 ))
                local pct=$(( total * 100 / quota_bytes ))
                (( pct >= 90 )) && quota_str="${RED}${quota_str} (${pct}%)${RESET}" \
                    || (( pct >= 70 )) && quota_str="${YELLOW}${quota_str} (${pct}%)${RESET}"
            fi
        fi

        printf "%-14s  %-8b  %-12s  %-12s  %-14s\n" \
            "$u" "$quota_str" "$up_str" "$down_str" "$total_str"
    done
    echo ""
    $alive || warn "Stats API 不可用（Xray 未运行或尚无流量），流量列显示为 -"
}

# ── 命令：add ──────────────────────────────────────────────────────────────────
cmd_add() {
    local name="${1:-}"
    [[ -n "$name" ]] || { error "用法: sudo $0 add <用户名>"; exit 1; }
    [[ "$name" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]] || {
        error "用户名必须以字母开头，只能含字母/数字/下划线: '$name'"
        exit 1
    }

    load_config

    if [[ " ${USERS} " == *" ${name} "* ]]; then
        warn "用户 '${name}' 已存在，输出现有 VLESS 链接"
        cmd_vless "$name"
        exit 0
    fi

    local new_uuid
    new_uuid=$(cat /proc/sys/kernel/random/uuid)
    declare "USER_${name}_UUID=${new_uuid}"
    declare "USER_${name}_QUOTA_GB=0"
    USERS="${USERS} ${name}"

    write_config
    reload_xray_clients
    success "用户 '${name}' 已添加（UUID: ${new_uuid}）"
    cmd_vless "$name"
}

# ── 命令：remove ───────────────────────────────────────────────────────────────
cmd_remove() {
    local name="${1:-}"
    [[ -n "$name" ]] || { error "用法: sudo $0 remove <用户名>"; exit 1; }

    load_config

    [[ " ${USERS} " == *" ${name} "* ]] || { error "用户 '${name}' 不存在"; exit 1; }

    local count
    count=$(echo "$USERS" | wc -w)
    (( count > 1 )) || { error "至少保留一个用户，无法删除 '${name}'"; exit 1; }

    USERS=$(echo "$USERS" | tr ' ' '\n' | grep -vxF "$name" | tr '\n' ' ' | xargs)
    traffic_store_clear "$name"

    write_config
    reload_xray_clients
    success "用户 '${name}' 已移除，Xray 已重载"
}

# ── 命令：quota ────────────────────────────────────────────────────────────────
cmd_quota() {
    local name="${1:-}" gb="${2:-}"
    [[ -n "$name" && -n "$gb" ]] || {
        error "用法: sudo $0 quota <用户名> <GB>  （0 = 无限制）"
        exit 1
    }
    [[ "$gb" =~ ^[0-9]+$ ]] || { error "GB 必须为非负整数"; exit 1; }

    load_config
    [[ " ${USERS} " == *" ${name} "* ]] || { error "用户 '${name}' 不存在"; exit 1; }

    declare "USER_${name}_QUOTA_GB=${gb}"
    write_config

    [[ "$gb" == "0" ]] \
        && success "用户 '${name}' 配额已设为无限制" \
        || success "用户 '${name}' 配额已设为 ${gb} GB"
}

# ── 命令：vless ────────────────────────────────────────────────────────────────
cmd_vless() {
    local name="${1:-}"
    local relay_ip="${2:-${RELAY_IP:-198.51.100.11}}"
    [[ -n "$name" ]] || { error "用法: sudo $0 vless <用户名> [中继IP]"; exit 1; }

    load_config
    [[ " ${USERS} " == *" ${name} "* ]] || { error "用户 '${name}' 不存在"; exit 1; }

    local uuid_var="USER_${name}_UUID"
    local uuid="${!uuid_var}"

    echo ""
    echo -e "${BOLD}用户: ${name}${RESET}"
    echo -e "UUID: ${uuid}"
    echo -e "中继: ${relay_ip}:${LISTEN_PORT}"
    echo ""
    echo -e "${CYAN}macOS / Windows / Linux (fp=chrome):${RESET}"
    echo "vless://${uuid}@${relay_ip}:${LISTEN_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#${name}"
    echo ""
    echo -e "${CYAN}iOS Shadowrocket (fp=ios):${RESET}"
    echo "vless://${uuid}@${relay_ip}:${LISTEN_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SNI}&fp=ios&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#${name}-iOS"
    echo ""
}

# ── 命令：stats ────────────────────────────────────────────────────────────────
cmd_stats() {
    load_config
    local target="${1:-}"
    local users_to_check="$USERS"
    [[ -n "$target" ]] && {
        [[ " ${USERS} " == *" ${target} "* ]] || { error "用户 '${target}' 不存在"; exit 1; }
        users_to_check="$target"
    }

    stats_api_alive || { warn "Stats API 不可用，请确认 Xray 正在运行"; exit 1; }

    echo ""
    echo -e "${BOLD}━━━ 流量统计（累计；add/remove/sync 重载不归零）━━━${RESET}"
    echo ""
    printf "%-14s  %-14s  %-14s  %-14s\n" "用户" "上行" "下行" "合计"
    printf '%0.s─' {1..60}; echo

    for u in $users_to_check; do
        local up down total
        read -r up down < <(get_user_traffic "$u")
        total=$(( up + down ))
        printf "%-14s  %-14s  %-14s  %-14s\n" \
            "$u" "$(bytes_to_human "$up")" "$(bytes_to_human "$down")" "$(bytes_to_human "$total")"
    done
    echo ""
}

# ── 命令：reset-stats ─────────────────────────────────────────────────────────
cmd_reset_stats() {
    local target="${1:-all}"
    load_config

    if [[ "$target" == "all" ]]; then
        info "重启 Xray 以重置所有用户流量统计..."
        traffic_store_clear all
        "$SYSTEMCTL_BIN" restart xray
        [[ "${MANAGE_SOURCE_ONLY:-false}" == "true" ]] || sleep 1
        "$SYSTEMCTL_BIN" is-active --quiet xray \
            && success "Xray 已重启，所有流量统计已归零" \
            || { error "Xray 重启失败"; exit 1; }
    else
        [[ " ${USERS} " == *" ${target} "* ]] || { error "用户 '${target}' 不存在"; exit 1; }
        stats_api_alive || { warn "Stats API 不可用，无法单独重置；可用 reset-stats all 重启 Xray"; exit 1; }

        local email="${target}@vpn"
        traffic_store_clear "$target"
        "$XRAY_BIN" api stats --server="$STATS_SERVER" \
            -name "user>>>${email}>>>traffic>>>uplink" --reset &>/dev/null || true
        "$XRAY_BIN" api stats --server="$STATS_SERVER" \
            -name "user>>>${email}>>>traffic>>>downlink" --reset &>/dev/null || true
        success "用户 '${target}' 流量统计已重置"
    fi
}

# ── 命令：check-quotas（供 cron 调用）─────────────────────────────────────────
cmd_check_quotas() {
    load_config
    stats_api_alive || { warn "Stats API 不可用，跳过配额检查"; exit 0; }

    local removed=false
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')

    for u in $USERS; do
        local quota_var="USER_${u}_QUOTA_GB"
        local quota="${!quota_var:-0}"
        [[ "$quota" != "0" ]] || continue

        local up down total
        read -r up down < <(get_user_traffic "$u")
        total=$(( up + down ))
        local quota_bytes=$(( quota * 1073741824 ))

        if (( total >= quota_bytes )); then
            local used_str
            used_str=$(bytes_to_human "$total")
            warn "用户 '${u}' 已用 ${used_str} ≥ 配额 ${quota}GB，正在移除..."
            USERS=$(echo "$USERS" | tr ' ' '\n' | grep -vxF "$u" | tr '\n' ' ' | xargs)
            traffic_store_clear "$u"
            echo "${ts} [QUOTA] 用户 ${u}: 用量 ${used_str} 超出 ${quota}GB，已禁用" >> "$QUOTA_LOG"
            removed=true
        fi
    done

    if $removed; then
        write_config
        reload_xray_clients
        success "配额巡检完成，已移除超限用户"
    else
        info "配额巡检完成，所有用户均在限额内"
    fi
}

# ── 命令：sync ─────────────────────────────────────────────────────────────────
cmd_sync() {
    load_config
    info "将 Xray clients 与 ${CONFIG_CACHE} 同步并重载（已用流量会保留）..."
    reload_xray_clients
    success "配置已同步，流量统计将按 <user>@vpn 计数"
}

# ── 命令：install-cron ────────────────────────────────────────────────────────
cmd_install_cron() {
    local script_path
    script_path=$(realpath "$0")
    local cron_file="/etc/cron.d/vpn-quota"
    local legacy_cron="/etc/cron.d/vpn2-quota"

    if [[ -f "$legacy_cron" ]]; then
        rm -f "$legacy_cron"
        warn "已移除旧版 cron: ${legacy_cron}（路径 network/vpn2/exit 已废弃）"
    fi

    cat > "$cron_file" <<EOF
# VPN 配额巡检：每小时执行一次
0 * * * * root ${script_path} check-quotas >> ${QUOTA_LOG} 2>&1

# VPN 月度流量重置：每月 1 日 00:05 清零，配额从头计算
5 0 1 * * root ${script_path} reset-stats all >> ${QUOTA_LOG} 2>&1
EOF
    chmod 644 "$cron_file"
    success "已安装 cron: ${cron_file}"
    info "  每小时配额巡检：超限用户自动移除"
    info "  每月 1 日 00:05：所有用户流量计数清零（配额月度刷新）"
    info "日志: ${QUOTA_LOG}"
}

# ── 帮助 ──────────────────────────────────────────────────────────────────────
cmd_help() {
    cat <<'HELP'
VPN 出口节点用户管理

用法：sudo ./exit/manage.sh <command> [args]

命令：
  list                       列出所有用户及流量统计
  add    <name>              新增用户，输出 VLESS 链接
  remove <name>              移除用户（立即生效，Xray 热重载）
  quota  <name> <GB>         设置月流量配额（0 = 无限制）
  vless  <name> [relay_ip]   打印指定用户的 VLESS 链接（默认中继 IP: 198.51.100.11）
  stats  [name]              显示流量统计（可选：指定单用户）
  reset-stats [name|all]     重置流量计数（all 会重启 Xray）
  sync                       同步 Xray clients 并重载（保留已用流量）
  check-quotas               检查并执行配额限制（供 cron 调用）
  install-cron               安装每小时配额巡检 cron 任务

环境变量：
  RELAY_IP=<ip>              指定中继 IP（影响 vless 命令输出的链接地址）

示例：
  sudo ./exit/manage.sh list
  sudo ./exit/manage.sh add alice
  sudo ./exit/manage.sh quota alice 50
  sudo ./exit/manage.sh remove bob
  sudo ./exit/manage.sh vless alice
  sudo ./exit/manage.sh vless alice 1.2.3.4
  sudo ./exit/manage.sh reset-stats all
  sudo ./exit/manage.sh sync
  sudo ./exit/manage.sh install-cron
HELP
}

# ── 入口 ──────────────────────────────────────────────────────────────────────
if [[ "${MANAGE_SOURCE_ONLY:-false}" == "true" ]]; then
    return 0 2>/dev/null || exit 0
fi

[[ $EUID -eq 0 ]] || { error "请以 root 权限运行: sudo $0 $*"; exit 1; }

COMMAND="${1:-help}"
shift 2>/dev/null || true

case "$COMMAND" in
    list)           cmd_list ;;
    add)            cmd_add "$@" ;;
    remove|rm)      cmd_remove "$@" ;;
    quota)          cmd_quota "$@" ;;
    vless)          cmd_vless "$@" ;;
    stats)          cmd_stats "${1:-}" ;;
    reset-stats)    cmd_reset_stats "${1:-all}" ;;
    sync)           cmd_sync ;;
    check-quotas)   cmd_check_quotas ;;
    install-cron)   cmd_install_cron ;;
    help|--help|-h) cmd_help ;;
    *) error "未知命令: $COMMAND"; echo ""; cmd_help; exit 1 ;;
esac
