#!/usr/bin/env bash
# =============================================================================
# VPN 客户端（macOS）一体化脚本
# 方案：Xray VLESS + Reality 客户端，通过杭州中继访问 claude.ai 等站点
#
# ❗推荐方案：macOS 桌面用户优先使用 V2RayXS（白屏化菜单栏 GUI）：
#     https://github.com/tzmax/V2RayXS/releases
#   导入 VLESS 链接即可启用「系统代理」+「PAC 智能分流」，无需运行本脚本。
#   配套 PAC 文件参见同目录 pac.js（已内置常见境外站点 / AI 服务）。
#
# 本脚本适合：希望走 Homebrew + LaunchAgent 命令行托管 Xray 的用户，或服务器风
# 格管理偏好；不想用菜单栏 GUI 时使用。
#
# 子命令：
#   install   通过 Homebrew 安装 Xray + 写入 LaunchAgent（默认子命令）
#   status    查看进程 / 配置 / 监听 / 连通性
#   clean     停止并卸载 Xray 客户端（含 plist）
#   proxy     管理 macOS「系统代理」on | off | status | list-services
#
# 用法示例：
#   ./macos_setup.sh install \
#        --relay-ip=198.51.100.10 \
#        --uuid=<UUID> --public-key=<PUB_KEY> --short-id=<SHORT_ID>
#   ./macos_setup.sh status
#   ./macos_setup.sh clean
#   ./macos_setup.sh proxy on [--service=Wi-Fi]
#   ./macos_setup.sh proxy off
#   ./macos_setup.sh proxy status
#   ./macos_setup.sh proxy list-services
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
step()    { echo -e "\n${BOLD}==> $*${RESET}"; }

if [[ "$(uname)" != "Darwin" ]]; then
    error "本脚本仅支持 macOS。Linux 请使用 linux_setup.sh"
    exit 1
fi

usage() {
    cat <<'HELP'
用法（macOS 桌面用户推荐先看 V2RayXS：https://github.com/tzmax/V2RayXS/releases）:
  ./macos_setup.sh install --uuid=<UUID> --public-key=<KEY> --short-id=<SID> [OPTIONS]
  ./macos_setup.sh status
  ./macos_setup.sh clean
  ./macos_setup.sh proxy on | off | status | list-services [--service=Wi-Fi]

子命令:
  install        Homebrew 安装 Xray + 用户级 LaunchAgent（默认；可省略）
  status         查看 LaunchAgent、监听端口、Geo 数据、连通性
  clean          停止并卸载 Xray 客户端 + LaunchAgent
  proxy          管理 macOS 系统代理（SOCKS + HTTP + HTTPS 三项一并设置）

install 必需参数（从出口节点 cat /root/.vpn_exit_config 获取）:
  --uuid=UUID          VLESS 用户 UUID
  --public-key=KEY     Reality 公钥
  --short-id=SID       Reality Short ID

install 可选参数:
  --relay-ip=IP        中继节点 IP（默认 198.51.100.10）
  --relay-port=PORT    中继节点端口（默认 443）
  --sni=DOMAIN         Reality SNI 域名（默认 www.microsoft.com）
  --socks-port=PORT    本地 SOCKS5 端口（默认 10808）
  --http-port=PORT     本地 HTTP 端口（默认 10809）
  --dry-run            仅预览，不实际执行
  --no-mirror          仅从 GitHub 下载，禁用国内镜像
  --force              跳过中继 TCP 连通性预检

proxy 子命令:
  proxy on             开启系统代理（需管理员密码）
  proxy off            关闭系统代理
  proxy status         查看当前网络服务的代理设置
  proxy list-services  列出可用网络服务名（Wi-Fi / Ethernet ...）
  --service=NAME       指定网络服务名（默认 Wi-Fi，或环境变量 VPN_PROXY_SERVICE）
HELP
}

# ── 子命令分发 ────────────────────────────────────────────────────────────────
SUBCOMMAND=""
case "${1:-}" in
    install|status|clean|proxy) SUBCOMMAND="$1"; shift ;;
    --help|-h)                  usage; exit 0 ;;
    "")                         SUBCOMMAND="install" ;;
    --*)                        SUBCOMMAND="install" ;;
    *) error "未知子命令: $1"; usage; exit 1 ;;
esac

# ── 默认参数 ──────────────────────────────────────────────────────────────────
DRY_RUN=false
USE_MIRROR=true
FORCE_SETUP=false
RELAY_IP="198.51.100.10"
RELAY_PORT=443
UUID=""
PUBLIC_KEY=""
SHORT_ID=""
SNI="www.microsoft.com"
FINGERPRINT="chrome"
SOCKS_PORT=10808
HTTP_PORT=10809
PROXY_ACTION=""
PROXY_SERVICE="${VPN_PROXY_SERVICE:-Wi-Fi}"

SOCKS_HOST="${VPN_SOCKS_HOST:-127.0.0.1}"
HTTP_HOST="${VPN_HTTP_HOST:-127.0.0.1}"
[[ -n "${VPN_SOCKS_PORT:-}" ]] && SOCKS_PORT="$VPN_SOCKS_PORT"
[[ -n "${VPN_HTTP_PORT:-}"  ]] && HTTP_PORT="$VPN_HTTP_PORT"

BREW_PREFIX=""
detect_brew_prefix() {
    BREW_PREFIX=$(brew --prefix 2>/dev/null || true)
    if [[ -z "$BREW_PREFIX" ]]; then
        if [[ -d /opt/homebrew ]]; then BREW_PREFIX="/opt/homebrew"
        else BREW_PREFIX="/usr/local"
        fi
    fi
}
detect_brew_prefix

XRAY_BIN="${BREW_PREFIX}/bin/xray"
XRAY_CONFIG_DIR="${BREW_PREFIX}/etc/xray"
XRAY_DAT_DIR="${BREW_PREFIX}/share/xray"
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/com.vpn.xray-client.plist"

for arg in "$@"; do
    case $arg in
        --relay-ip=*)         RELAY_IP="${arg#*=}" ;;
        --relay-port=*)       RELAY_PORT="${arg#*=}" ;;
        --uuid=*)             UUID="${arg#*=}" ;;
        --public-key=*)       PUBLIC_KEY="${arg#*=}" ;;
        --short-id=*)         SHORT_ID="${arg#*=}" ;;
        --sni=*)              SNI="${arg#*=}" ;;
        --socks-port=*)       SOCKS_PORT="${arg#*=}" ;;
        --http-port=*)        HTTP_PORT="${arg#*=}" ;;
        --service=*)          PROXY_SERVICE="${arg#*=}" ;;
        --dry-run)            DRY_RUN=true ;;
        --no-mirror)          USE_MIRROR=false ;;
        --force)              FORCE_SETUP=true ;;
        on|off|status|list-services) PROXY_ACTION="$arg" ;;
        --help|-h)            usage; exit 0 ;;
        *) warn "未知参数: $arg" ;;
    esac
done

# ── 工具函数 ──────────────────────────────────────────────────────────────────
port_listening() {
    lsof -iTCP:"$1" -sTCP:LISTEN &>/dev/null
}

file_size() { stat -f%z "$1" 2>/dev/null || echo 0; }

tcp_reachable() {
    local host="$1" port="$2"
    if command -v nc &>/dev/null; then
        nc -z -G 5 "$host" "$port" 2>/dev/null && return 0
    fi
    (echo > /dev/tcp/"$host"/"$port") 2>/dev/null
}

download_file_with_mirrors() {
    local dest="$1"; shift
    local urls=("$@") url max_time="${DOWNLOAD_MAX_TIME:-120}"
    mkdir -p "$(dirname "$dest")"
    for url in "${urls[@]}"; do
        info "下载: ${url%%\?*} ..."
        if curl -fsSL --connect-timeout 25 --max-time "$max_time" \
            --retry 2 --retry-delay 2 -o "$dest" "$url" \
            && [[ -s "$dest" ]]; then
            return 0
        fi
        warn "下载失败，尝试下一源..."
        rm -f "$dest"
    done
    return 1
}

ensure_geo_data() {
    local dat_dir="$1"
    local geoip="${dat_dir}/geoip.dat"
    local geosite="${dat_dir}/geosite.dat"
    local min_size=65536 need=false

    [[ ! -f "$geoip" ]] || [[ $(file_size "$geoip") -lt $min_size ]] && need=true
    [[ ! -f "$geosite" ]] || [[ $(file_size "$geosite") -lt $min_size ]] && need=true

    if ! $need; then
        success "Geo 路由数据已就绪: ${dat_dir}"
        return 0
    fi

    step "下载 Geo 路由数据（国内镜像，路由规则必需）"
    mkdir -p "$dat_dir"
    DOWNLOAD_MAX_TIME=300

    local geoip_urls geosite_urls
    if $USE_MIRROR; then
        geoip_urls=(
            "https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geoip.dat"
            "https://fastly.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geoip.dat"
            "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
        )
        geosite_urls=(
            "https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geosite.dat"
            "https://fastly.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geosite.dat"
            "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
        )
    else
        geoip_urls=("https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat")
        geosite_urls=("https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat")
    fi

    download_file_with_mirrors "$geoip" "${geoip_urls[@]}" \
        || { error "geoip.dat 下载失败"; return 1; }
    download_file_with_mirrors "$geosite" "${geosite_urls[@]}" \
        || { error "geosite.dat 下载失败"; return 1; }
    unset DOWNLOAD_MAX_TIME
    success "Geo 路由数据已下载: ${dat_dir}"
}

preflight_relay_check() {
    step "检查到中继节点的网络连通性"
    if tcp_reachable "${RELAY_IP}" "${RELAY_PORT}"; then
        success "中继节点 ${RELAY_IP}:${RELAY_PORT} TCP 可达"
        return 0
    fi
    warn "无法连接中继节点 ${RELAY_IP}:${RELAY_PORT}"
    warn "请确认：① relay/setup.sh 已在中继 ECS 部署  ② 安全组放行 TCP ${RELAY_PORT}  ③ 本机防火墙未拦截"
    if $FORCE_SETUP; then
        warn "--force 已启用，跳过中继连通性检查"
        return 0
    fi
    error "中止安装。若确认中继正常，可加 --force 跳过此检查"
    exit 1
}

validate_xray_config() {
    local cfg="${XRAY_CONFIG_DIR}/client.json"
    step "校验 Xray 配置文件"
    if "$XRAY_BIN" run -test -config "$cfg" 2>/tmp/xray-config-test.log; then
        success "配置文件校验通过"
        return 0
    fi
    error "配置文件校验失败:"
    tail -10 /tmp/xray-config-test.log >&2 || true
    if grep -qiE 'geo(ip|site)|geodata|not found|failed to load' /tmp/xray-config-test.log 2>/dev/null; then
        warn "检测到 Geo 数据问题，尝试重新下载..."
        ensure_geo_data "$XRAY_DAT_DIR" \
            && "$XRAY_BIN" run -test -config "$cfg" \
            && { success "重新下载 Geo 数据后配置校验通过"; return 0; }
    fi
    exit 1
}

# ── install ──────────────────────────────────────────────────────────────────
install_xray() {
    if ! command -v brew &>/dev/null; then
        error "需要 Homebrew，请先安装: https://brew.sh"
        exit 1
    fi
    info "通过 Homebrew 安装 Xray..."
    if $USE_MIRROR; then
        export HOMEBREW_BOTTLE_DOMAIN="${HOMEBREW_BOTTLE_DOMAIN:-https://mirrors.aliyun.com/homebrew/homebrew-bottles}"
        info "使用 Homebrew 国内镜像加速（可通过 HOMEBREW_BOTTLE_DOMAIN 覆盖）"
    fi
    brew install xray
    detect_brew_prefix
    XRAY_BIN="${BREW_PREFIX}/bin/xray"
    XRAY_CONFIG_DIR="${BREW_PREFIX}/etc/xray"
    XRAY_DAT_DIR="${BREW_PREFIX}/share/xray"
}

write_client_config() {
    mkdir -p "$XRAY_CONFIG_DIR"
    cat > "${XRAY_CONFIG_DIR}/client.json" <<JSON_EOF
{
  "log": {
    "loglevel": "warning"
  },
  "dns": {
    "servers": [
      {
        "address": "223.5.5.5",
        "port": 53,
        "domains": ["geosite:cn"],
        "expectIPs": ["geoip:cn"]
      },
      {
        "address": "119.29.29.29",
        "port": 53,
        "domains": ["geosite:cn"],
        "expectIPs": ["geoip:cn"]
      },
      "223.5.5.5"
    ],
    "queryStrategy": "UseIPv4",
    "disableFallback": true
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
      { "type": "field", "ip": ["geoip:private"], "outboundTag": "direct" },
      { "type": "field", "ip": ["geoip:cn"],      "outboundTag": "direct" },
      { "type": "field", "domain": ["geosite:cn"], "outboundTag": "direct" },
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
      { "type": "field", "domain": ["geosite:geolocation-!cn"], "outboundTag": "proxy" }
    ]
  }
}
JSON_EOF
    chmod 644 "${XRAY_CONFIG_DIR}/client.json"
}

write_launch_agent() {
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$LAUNCH_AGENT_PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.vpn.xray-client</string>
    <key>ProgramArguments</key>
    <array>
        <string>${XRAY_BIN}</string>
        <string>run</string>
        <string>-config</string>
        <string>${XRAY_CONFIG_DIR}/client.json</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/xray-client.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/xray-client.log</string>
</dict>
</plist>
PLIST_EOF
}

do_install() {
    if [[ $EUID -eq 0 ]]; then
        warn "macOS 下不建议以 root 运行，使用普通用户权限即可"
    fi

    if [[ -z "$UUID" || -z "$PUBLIC_KEY" || -z "$SHORT_ID" ]]; then
        error "缺少必需参数！请从出口节点部署输出中获取并填写:"
        error "  --uuid=<UUID> --public-key=<PUBLIC_KEY> --short-id=<SHORT_ID>"
        echo ""
        echo "示例:"
        echo "  $0 install --uuid=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \\"
        echo "             --public-key=<base64_public_key> \\"
        echo "             --short-id=<8_hex_chars>"
        echo ""
        echo "或考虑使用 V2RayXS 图形客户端: https://github.com/tzmax/V2RayXS/releases"
        exit 1
    fi

    local UUID_NORM SHORT_ID_NORM
    UUID_NORM=$(echo "$UUID" | tr '[:upper:]' '[:lower:]')
    if [[ ! "$UUID_NORM" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        error "UUID 格式无效（须为十六进制且形如 xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx）。"
        error "请从出口节点 cat /root/.vpn_exit_config 完整复制，避免手打出错字符。"
        exit 1
    fi
    SHORT_ID_NORM=$(echo "$SHORT_ID" | tr '[:upper:]' '[:lower:]')
    if [[ ! "$SHORT_ID_NORM" =~ ^[0-9a-f]+$ ]] || [[ ${#SHORT_ID_NORM} -gt 16 ]]; then
        error "Short ID 须为非空的十六进制字符串（常见长度 8）。当前值无效。"
        exit 1
    fi
    UUID="$UUID_NORM"
    SHORT_ID="$SHORT_ID_NORM"

    step "部署 Xray 客户端"
    info "中继节点  : ${RELAY_IP}:${RELAY_PORT}"
    info "UUID      : ${UUID}"
    info "SNI       : ${SNI}"
    info "SOCKS5    : 127.0.0.1:${SOCKS_PORT}"
    info "HTTP代理  : 127.0.0.1:${HTTP_PORT}"
    $DRY_RUN && warn "[dry-run] 仅预览，不执行实际操作"

    if ! $DRY_RUN; then
        preflight_relay_check
    fi

    step "安装 Xray-core（Homebrew）"
    if ! command -v xray &>/dev/null; then
        if $DRY_RUN; then
            info "[dry-run] 将通过 Homebrew 安装 Xray"
        else
            install_xray
        fi
    else
        local XRAY_VER
        XRAY_VER=$(xray version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        success "Xray 已安装: v${XRAY_VER}"
    fi

    if ! $DRY_RUN; then
        ensure_geo_data "$XRAY_DAT_DIR" || exit 1
    fi

    step "写入 Xray 客户端配置"
    if $DRY_RUN; then
        info "[dry-run] 将写入客户端配置到 ${XRAY_CONFIG_DIR}/client.json"
    else
        write_client_config
        success "客户端配置已写入: ${XRAY_CONFIG_DIR}/client.json"
        validate_xray_config
    fi

    step "配置 xray-client LaunchAgent"
    if $DRY_RUN; then
        info "[dry-run] 将创建 ${LAUNCH_AGENT_PLIST}"
    else
        write_launch_agent
        launchctl unload "$LAUNCH_AGENT_PLIST" 2>/dev/null || true
        launchctl load -w "$LAUNCH_AGENT_PLIST"
        sleep 2
        if port_listening "${SOCKS_PORT}"; then
            success "xray-client LaunchAgent 运行中（SOCKS 端口 ${SOCKS_PORT} 已监听）"
        else
            error "xray-client 未监听 SOCKS 端口 ${SOCKS_PORT}，进程可能因配置错误退出。"
            error "查看日志: tail -50 /tmp/xray-client.log"
            if [[ -f /tmp/xray-client.log ]]; then
                echo ""
                tail -15 /tmp/xray-client.log >&2 || true
            fi
            exit 1
        fi
    fi

    step "验证代理连通性"
    if ! $DRY_RUN; then
        sleep 1
        info "测试通过代理访问 api4.ipify.org..."
        local HTTP_CODE
        HTTP_CODE=$(curl -x "socks5h://127.0.0.1:${SOCKS_PORT}" \
            -fsSL --connect-timeout 15 \
            -o /dev/null -w "%{http_code}" \
            https://api4.ipify.org 2>/dev/null) || HTTP_CODE="000"

        if [[ "$HTTP_CODE" =~ ^2 ]]; then
            success "代理链路畅通！ipify.org HTTP 状态: ${HTTP_CODE}"
        else
            warn "ipify.org 访问测试返回: ${HTTP_CODE}"
            warn "若 SOCKS 端口已监听，请检查 UUID / PublicKey / ShortID 是否与出口节点一致"
            warn "诊断命令: $0 status  或  tail -50 /tmp/xray-client.log"
        fi
    fi

    step "客户端配置完成！"
    cat <<EOF

${BOLD}━━━ 代理端口 ━━━${RESET}
  SOCKS5  : socks5h://127.0.0.1:${SOCKS_PORT}
  HTTP    : http://127.0.0.1:${HTTP_PORT}

${BOLD}━━━ 系统代理（一键开关）━━━${RESET}
  $0 proxy on               # 当前网络服务（默认 Wi-Fi）启用 SOCKS+HTTP+HTTPS
  $0 proxy off              # 关闭系统代理
  $0 proxy status           # 查看当前代理设置
  $0 proxy list-services    # 列出可用网络服务
  $0 proxy on --service="Ethernet"

${BOLD}━━━ 浏览器配置 ━━━${RESET}
  SwitchyOmega → SOCKS5 → 127.0.0.1:${SOCKS_PORT}

${BOLD}━━━ curl / wget 使用 ━━━${RESET}
  curl -x socks5h://127.0.0.1:${SOCKS_PORT} https://claude.ai/
  curl -x http://127.0.0.1:${HTTP_PORT}      https://claude.ai/

${BOLD}━━━ 服务管理命令 ━━━${RESET}
  查看状态   : $0 status
  停止卸载   : $0 clean
  查看日志   : tail -f /tmp/xray-client.log
  重启服务   : launchctl unload ${LAUNCH_AGENT_PLIST} && launchctl load -w ${LAUNCH_AGENT_PLIST}

${BOLD}━━━ 路由策略说明 ━━━${RESET}
  国内域名/IP     → 直连（不走代理）
  claude.ai 等    → 通过 ${RELAY_IP} 中继代理
  其余境外流量    → 通过代理

${YELLOW}提示${RESET}：若希望白屏化体验，推荐使用 V2RayXS 菜单栏 GUI：
  https://github.com/tzmax/V2RayXS/releases
  搭配同目录 pac.js 即可实现智能分流。
EOF

    echo -e "${GREEN}${BOLD}客户端部署完成！${RESET} 现在可以通过 SOCKS5 代理访问 claude.ai"
}

# ── status ───────────────────────────────────────────────────────────────────
do_status() {
    echo -e "\n${BOLD}━━━ Xray 客户端状态 ━━━${RESET}"
    launchctl list | grep "com.vpn.xray-client" 2>/dev/null \
        || echo "Xray 服务未运行（launchctl 中未找到 com.vpn.xray-client）"
    [[ -f "$LAUNCH_AGENT_PLIST" ]] && echo "Plist: $LAUNCH_AGENT_PLIST" \
                                  || echo "Plist 文件不存在: $LAUNCH_AGENT_PLIST"

    echo ""
    echo -e "${BOLD}━━━ Geo 路由数据 ━━━${RESET}"
    for f in geoip.dat geosite.dat; do
        fp="${XRAY_DAT_DIR}/${f}"
        if [[ -f "$fp" ]]; then
            sz=$(file_size "$fp")
            echo "  ${f}: 存在 (${sz} bytes)"
        else
            echo -e "  ${f}: ${RED}缺失${RESET} — 路由规则 geoip:cn / geosite:cn 无法生效"
        fi
    done

    echo ""
    echo -e "${BOLD}━━━ 中继节点连通性 ━━━${RESET}"
    if tcp_reachable "${RELAY_IP}" "${RELAY_PORT}"; then
        echo "  ${RELAY_IP}:${RELAY_PORT} TCP 可达"
    else
        echo -e "  ${RELAY_IP}:${RELAY_PORT} ${RED}TCP 不可达${RESET}"
    fi

    echo ""
    echo -e "${BOLD}━━━ 代理端口监听 ━━━${RESET}"
    lsof -iTCP:${SOCKS_PORT} -sTCP:LISTEN 2>/dev/null || echo "SOCKS5 端口 ${SOCKS_PORT} 未监听"
    lsof -iTCP:${HTTP_PORT}  -sTCP:LISTEN 2>/dev/null || echo "HTTP 端口 ${HTTP_PORT} 未监听"

    if [[ -f "${XRAY_CONFIG_DIR}/client.json" ]] && command -v xray &>/dev/null; then
        echo ""
        echo -e "${BOLD}━━━ 配置校验 ━━━${RESET}"
        if xray run -test -config "${XRAY_CONFIG_DIR}/client.json" 2>/tmp/xray-status-test.log; then
            echo "  配置文件校验通过"
        else
            echo -e "  ${RED}配置文件校验失败${RESET}:"
            tail -5 /tmp/xray-status-test.log 2>/dev/null | sed 's/^/    /'
        fi
    fi

    echo ""
    echo -e "${BOLD}━━━ 系统代理 ━━━${RESET}"
    echo "  网络服务: ${PROXY_SERVICE}"
    networksetup -getsocksfirewallproxy "$PROXY_SERVICE"        2>/dev/null | sed 's/^/  /'
    networksetup -getwebproxy "$PROXY_SERVICE"                  2>/dev/null | sed 's/^/  /'
    networksetup -getsecurewebproxy "$PROXY_SERVICE"            2>/dev/null | sed 's/^/  /'

    echo ""
    echo -e "${BOLD}━━━ 连通性测试（通过代理访问）━━━${RESET}"
    curl -x "socks5h://127.0.0.1:${SOCKS_PORT}" -fsSL --connect-timeout 10 \
        -o /dev/null -w "  ipify.org HTTP: %{http_code}\n" https://api4.ipify.org 2>/dev/null \
        || echo "  ipify.org 连接失败"
    curl -x "socks5h://127.0.0.1:${SOCKS_PORT}" -fsSL --connect-timeout 10 \
        -o /dev/null -w "  claude.ai HTTP: %{http_code}\n" https://claude.ai/ 2>/dev/null \
        || echo "  claude.ai 连接失败（403 也可能表示代理已通）"
}

# ── clean ────────────────────────────────────────────────────────────────────
do_clean() {
    step "停止并移除 Xray 客户端"
    launchctl unload "$LAUNCH_AGENT_PLIST" 2>/dev/null || true
    rm -f "$LAUNCH_AGENT_PLIST"
    rm -f "${XRAY_CONFIG_DIR}/client.json"
    success "Xray 客户端已停止并移除"
    info "如需同时关闭系统代理：$0 proxy off"
}

# ── proxy: macOS 系统代理 ────────────────────────────────────────────────────
proxy_on() {
    info "网络服务: ${PROXY_SERVICE}"
    info "SOCKS ${SOCKS_HOST}:${SOCKS_PORT}；HTTP/HTTPS ${HTTP_HOST}:${HTTP_PORT}"
    sudo networksetup -setsocksfirewallproxy "$PROXY_SERVICE" "$SOCKS_HOST" "$SOCKS_PORT" off
    sudo networksetup -setsocksfirewallproxystate "$PROXY_SERVICE" on
    sudo networksetup -setwebproxy "$PROXY_SERVICE" "$HTTP_HOST" "$HTTP_PORT"
    sudo networksetup -setsecurewebproxy "$PROXY_SERVICE" "$HTTP_HOST" "$HTTP_PORT"
    sudo networksetup -setwebproxystate "$PROXY_SERVICE" on
    sudo networksetup -setsecurewebproxystate "$PROXY_SERVICE" on
    success "系统代理已开启（SOCKS + HTTP + HTTPS）"
    warn "关闭前请保持本机 Xray 在 ${SOCKS_PORT}/${HTTP_PORT} 监听，否则整机可能无法上网"
}

proxy_off() {
    info "网络服务: ${PROXY_SERVICE}"
    sudo networksetup -setsocksfirewallproxystate "$PROXY_SERVICE" off
    sudo networksetup -setwebproxystate "$PROXY_SERVICE" off
    sudo networksetup -setsecurewebproxystate "$PROXY_SERVICE" off
    success "系统代理已关闭"
}

proxy_status() {
    echo -e "${BOLD}网络服务: ${PROXY_SERVICE}${RESET}"
    echo -e "${BOLD}SOCKS${RESET}"
    networksetup -getsocksfirewallproxy "$PROXY_SERVICE"
    echo -e "${BOLD}HTTP${RESET}"
    networksetup -getwebproxy "$PROXY_SERVICE"
    echo -e "${BOLD}HTTPS${RESET}"
    networksetup -getsecurewebproxy "$PROXY_SERVICE"
}

proxy_list_services() {
    echo -e "${BOLD}可用网络服务:${RESET}"
    networksetup -listallnetworkservices | tail -n +2
}

do_proxy() {
    case "$PROXY_ACTION" in
        on)             proxy_on ;;
        off)            proxy_off ;;
        status)         proxy_status ;;
        list-services)  proxy_list_services ;;
        "") error "请指定动作: $0 proxy on | off | status | list-services"; exit 1 ;;
        *)  error "未知 proxy 动作: $PROXY_ACTION"; exit 1 ;;
    esac
}

# ── 主流程 ────────────────────────────────────────────────────────────────────
case "$SUBCOMMAND" in
    install) do_install ;;
    status)  do_status ;;
    clean)   do_clean ;;
    proxy)   do_proxy ;;
esac
