#!/usr/bin/env bash
# =============================================================================
# VPN 客户端（Linux）一体化脚本
# 方案：Xray VLESS + Reality 客户端，通过杭州中继访问 claude.ai 等站点
#
# 子命令：
#   install   安装并配置 Xray 客户端（默认；可省略子命令直接传 --uuid=...）
#   status    查看运行 / 配置 / 连通性状态
#   clean     停止并卸载 Xray 客户端
#   proxy     管理当前用户的终端代理环境变量（on | off | status | test）
#
# 用法示例：
#   sudo ./linux_setup.sh install \
#        --relay-ip=198.51.100.10 \
#        --uuid=<UUID> --public-key=<PUB_KEY> --short-id=<SHORT_ID>
#   sudo ./linux_setup.sh install --vless="vless://<uuid>@<host>:<port>?...&pbk=...&sid=...#tag"
#   （--vless 与 --uuid/--public-key/--short-id 二者只可选其一，不能同时使用）
#   sudo ./linux_setup.sh status
#   sudo ./linux_setup.sh clean
#   ./linux_setup.sh proxy on
#   ./linux_setup.sh proxy off
#   ./linux_setup.sh proxy status
#   ./linux_setup.sh proxy test
#
# 提示：也可执行 ./install-setproxy.sh 安装独立的 setproxy 命令到
#      ~/.local/bin，之后任意目录下可直接执行 setproxy on/off/status/test。
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
step()    { echo -e "\n${BOLD}==> $*${RESET}"; }

if [[ "$(uname)" == "Darwin" ]]; then
    error "本脚本仅支持 Linux。macOS 请使用 macos_setup.sh"
    exit 1
fi

usage() {
    cat <<'HELP'
用法:
  sudo ./linux_setup.sh install --uuid=<UUID> --public-key=<KEY> --short-id=<SID> [OPTIONS]
  sudo ./linux_setup.sh install --vless="vless://<uuid>@<host>:<port>?...#tag"
  sudo ./linux_setup.sh status
  sudo ./linux_setup.sh clean
  ./linux_setup.sh proxy on | off | status | test

子命令:
  install   安装并配置 Xray 客户端（默认；可省略，等价于 install）
  status    查看 systemd 服务、监听端口、Geo 数据、连通性
  clean     停止并卸载 Xray 客户端及配置
  proxy     管理终端环境变量代理（写入 ~/.config/vpn/proxy.env，自动加载到 ~/.bashrc / ~/.zshrc）

install 必需参数（两种方式二选一，不能同时使用）:
  方式一：--vless=<LINK>  直接传入完整 VLESS 链接（出口节点部署输出会打印该链接）
       sudo ./linux_setup.sh install --vless="vless://<UUID>@<HOST>:<PORT>?encryption=none&flow=xtls-rprx-vision&security=reality&sni=<SNI>&fp=chrome&pbk=<PUBKEY>&sid=<SID>&type=tcp&headerType=none#标签"
     注意：需用引号包裹整个 --vless= 参数，否则 shell 会把 & 当作后台执行符处理。
     可解析：uuid / 中继 host:port / pbk / sid / sni / fp / flow / spx。
  方式二：手动指定三个必需参数
       --uuid=UUID --public-key=KEY --short-id=SID
  若同时提供 --vless 与 --uuid/--public-key/--short-id 中任意一个，脚本会报错退出。

install 可选参数:
  --relay-ip=IP        中继节点 IP（默认 198.51.100.10）
  --relay-port=PORT    中继节点端口（默认 443）
  --sni=DOMAIN         Reality SNI 域名（默认 www.icloud.com）
  --socks-port=PORT    本地 SOCKS5 端口（默认 10808）
  --http-port=PORT     本地 HTTP 端口（默认 10809）
  --dry-run            仅预览，不实际执行
  --no-mirror          仅从 GitHub 下载，禁用国内镜像
  --force              跳过中继 TCP 连通性预检

proxy 子命令:
  proxy on      开启终端代理环境变量，写入 ~/.config/vpn/proxy.env
  proxy off     关闭终端代理环境变量
  proxy status  查看当前代理状态、端口监听情况，以及 xray 日志查看方式
  proxy test    临时启用/禁用之外，测试代理端口 + 实际连通性是否正常

proxy 子命令对应环境变量（可选）：
  VPN_SOCKS_HOST / VPN_SOCKS_PORT / VPN_HTTP_HOST / VPN_HTTP_PORT
  当前 shell 立即生效:
    source ./linux_setup.sh proxy on
    eval "$(./linux_setup.sh proxy on --emit)"
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
SNI="www.icloud.com"
FINGERPRINT="chrome"
FLOW="xtls-rprx-vision"
SPIDER_X="/"
SOCKS_PORT=10808
HTTP_PORT=10809
PROXY_ACTION=""
PROXY_EMIT=false

XRAY_BIN="/usr/local/bin/xray"
XRAY_CONFIG_DIR="/usr/local/etc/xray"
XRAY_DAT_DIR="/usr/local/share/xray"

PROXY_DIR="${HOME}/.config/vpn"
PROXY_ENV="${PROXY_DIR}/proxy.env"
MARKER_BEGIN="# >>> vpn-shell-proxy managed >>>"
MARKER_END="# <<< vpn-shell-proxy managed <<<"
HOOK_LINE='[ -f "${HOME}/.config/vpn/proxy.env" ] && . "${HOME}/.config/vpn/proxy.env"'

SOCKS_HOST="${VPN_SOCKS_HOST:-127.0.0.1}"
HTTP_HOST="${VPN_HTTP_HOST:-127.0.0.1}"
[[ -n "${VPN_SOCKS_PORT:-}" ]] && SOCKS_PORT="$VPN_SOCKS_PORT"
[[ -n "${VPN_HTTP_PORT:-}"  ]] && HTTP_PORT="$VPN_HTTP_PORT"

# ── VLESS 链接解析（install 的另一种参数输入方式）───────────────────────────
url_decode() {
    local data="${1//+/ }"
    printf '%b' "${data//%/\\x}"
}

parse_vless_link() {
    local link="$1"
    local body fragment query hostport host port uuid_part
    local enc_v="" sec_v=""

    body="${link#vless://}"

    fragment=""
    if [[ "$body" == *'#'* ]]; then
        fragment="${body#*#}"
        body="${body%%#*}"
    fi

    if [[ "$body" != *'@'* ]]; then
        error "无效的 VLESS 链接：缺少 <uuid>@<host> 部分"
        exit 1
    fi
    uuid_part="${body%%@*}"
    body="${body#*@}"

    query=""
    if [[ "$body" == *'?'* ]]; then
        query="${body#*\?}"
        hostport="${body%%\?*}"
    else
        hostport="$body"
    fi

    host="${hostport%%:*}"
    port="${hostport#*:}"
    if [[ -z "$host" || -z "$port" || "$host" == "$hostport" ]]; then
        error "无效的 VLESS 链接：缺少 <host>:<port> 部分"
        exit 1
    fi

    UUID="$uuid_part"
    RELAY_IP="$host"
    RELAY_PORT="$port"

    local pair key key_lc value type_v="" header_v=""
    IFS='&' read -ra __vless_pairs <<< "$query"
    for pair in "${__vless_pairs[@]}"; do
        [[ -z "$pair" ]] && continue
        key="${pair%%=*}"
        key_lc="$(echo "$key" | tr '[:upper:]' '[:lower:]')"
        value="$(url_decode "${pair#*=}")"
        case "$key_lc" in
            pbk)        PUBLIC_KEY="$value" ;;
            sid)        SHORT_ID="$value" ;;
            sni)        SNI="$value" ;;
            fp)         FINGERPRINT="$value" ;;
            flow)       FLOW="$value" ;;
            spx)        SPIDER_X="$value" ;;
            encryption) enc_v="$value" ;;
            security)   sec_v="$value" ;;
            type)       type_v="$value" ;;
            headertype) header_v="$value" ;;
        esac
    done

    if [[ -n "$sec_v" && "$sec_v" != "reality" ]]; then
        warn "VLESS 链接 security=${sec_v}，本脚本仅支持 reality，可能无法正常工作"
    fi
    if [[ -n "$enc_v" && "$enc_v" != "none" ]]; then
        warn "VLESS 链接 encryption=${enc_v}，预期为 none"
    fi
    if [[ -n "$type_v" && "$type_v" != "tcp" ]]; then
        warn "VLESS 链接 type=${type_v}，本脚本客户端配置仅支持 tcp，可能无法正常工作"
    fi
    if [[ -n "$header_v" && "$header_v" != "none" ]]; then
        warn "VLESS 链接 headerType=${header_v}，本脚本客户端配置仅支持 none，可能无法正常工作"
    fi

    info "已从 VLESS 链接解析参数${fragment:+ [$(url_decode "$fragment")]}:"
    info "  中继节点  : ${RELAY_IP}:${RELAY_PORT}"
    info "  UUID      : ${UUID}"
    info "  SNI       : ${SNI}"
    info "  PublicKey : ${PUBLIC_KEY}"
    info "  ShortId   : ${SHORT_ID}"
}

# 第一遍扫描：只提取 --vless= 与三个手动身份参数，用于互斥校验 + 先解析链接
# （链接负责给出 UUID/中继地址/公钥等基础值，第二遍扫描时其它显式参数可再覆盖）
VLESS_LINK=""
MANUAL_PARAM_SET=false
for arg in "$@"; do
    case $arg in
        --vless=*)       VLESS_LINK="${arg#*=}" ;;
        --uuid=*|--public-key=*|--short-id=*) MANUAL_PARAM_SET=true ;;
    esac
done

if [[ -n "$VLESS_LINK" ]]; then
    if $MANUAL_PARAM_SET; then
        error "--vless 与 --uuid/--public-key/--short-id 不能同时使用，请二选一"
        exit 1
    fi
    parse_vless_link "$VLESS_LINK"
fi

# 第二遍扫描：处理其余参数；若未使用 --vless，则 --uuid/--public-key/--short-id 在此生效
for arg in "$@"; do
    case $arg in
        --vless=*)       ;; # 已在上面处理
        --relay-ip=*)    RELAY_IP="${arg#*=}" ;;
        --relay-port=*)  RELAY_PORT="${arg#*=}" ;;
        --uuid=*)        UUID="${arg#*=}" ;;
        --public-key=*)  PUBLIC_KEY="${arg#*=}" ;;
        --short-id=*)    SHORT_ID="${arg#*=}" ;;
        --sni=*)         SNI="${arg#*=}" ;;
        --socks-port=*)  SOCKS_PORT="${arg#*=}" ;;
        --http-port=*)   HTTP_PORT="${arg#*=}" ;;
        --dry-run)       DRY_RUN=true ;;
        --no-mirror)     USE_MIRROR=false ;;
        --force)         FORCE_SETUP=true ;;
        --emit)          PROXY_EMIT=true ;;
        on|off|status|test) PROXY_ACTION="$arg" ;;
        --help|-h)       usage; exit 0 ;;
        *) warn "未知参数: $arg" ;;
    esac
done

# ── 工具函数 ──────────────────────────────────────────────────────────────────
run() {
    if $DRY_RUN; then info "[dry-run] $*"; else "$@"; fi
}

port_listening() {
    local p="$1"
    if command -v ss &>/dev/null; then
        ss -tln | grep -q ":${p} "
    else
        lsof -iTCP:"$p" -sTCP:LISTEN &>/dev/null
    fi
}

file_size() { stat -c%s "$1" 2>/dev/null || echo 0; }

tcp_reachable() {
    local host="$1" port="$2"
    if command -v nc &>/dev/null; then
        nc -z -w 5 "$host" "$port" 2>/dev/null && return 0
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

# ── install: Xray 安装 ────────────────────────────────────────────────────────
install_xray_from_mirror() {
    local machine tmpdir zip
    case "$(uname -m)" in
        x86_64|amd64)  machine=64 ;;
        aarch64|arm64) machine=arm64-v8a ;;
        armv7l)        machine=arm32-v7a ;;
        *) error "不支持的 CPU 架构: $(uname -m)"; return 1 ;;
    esac

    if ! command -v unzip &>/dev/null; then
        if [[ -f /etc/os-release ]]; then
            # shellcheck source=/dev/null
            source /etc/os-release
            case "$ID" in
                centos|rhel|almalinux|rocky|alinux|anolis) yum install -y unzip ;;
                ubuntu|debian) apt-get update -qq && apt-get install -y unzip ;;
            esac
        fi
    fi
    command -v unzip &>/dev/null || { error "需要 unzip 命令"; return 1; }

    tmpdir=$(mktemp -d)
    zip="${tmpdir}/xray.zip"
    local urls
    if $USE_MIRROR; then
        urls=(
            "https://ghfast.top/https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${machine}.zip"
            "https://mirror.ghproxy.com/https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${machine}.zip"
            "https://cdn.jsdelivr.net/gh/XTLS/Xray-core@latest-release/Xray-linux-${machine}.zip"
            "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${machine}.zip"
        )
    else
        urls=("https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${machine}.zip")
    fi

    info "从镜像下载 Xray 二进制（linux-${machine}）..."
    download_file_with_mirrors "$zip" "${urls[@]}" || { rm -rf "$tmpdir"; return 1; }
    unzip -o -q "$zip" xray -d "$tmpdir"
    install -m 755 "${tmpdir}/xray" /usr/local/bin/xray
    mkdir -p /usr/local/share/xray /usr/local/etc/xray /var/log/xray
    rm -rf "$tmpdir"
    success "Xray 二进制已安装: /usr/local/bin/xray"
}

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

    local script_urls install_script
    if $USE_MIRROR; then
        script_urls=(
            "https://cdn.jsdelivr.net/gh/XTLS/Xray-install@main/install-release.sh"
            "https://ghfast.top/https://github.com/XTLS/Xray-install/raw/main/install-release.sh"
            "https://github.com/XTLS/Xray-install/raw/main/install-release.sh"
        )
    else
        script_urls=("https://github.com/XTLS/Xray-install/raw/main/install-release.sh")
    fi

    install_script=$(mktemp)
    info "下载 Xray 安装脚本..."
    if download_file_with_mirrors "$install_script" "${script_urls[@]}" \
        && bash "$install_script" install; then
        rm -f "$install_script"
        return
    fi
    rm -f "$install_script"

    warn "官方安装脚本失败（国内访问 GitHub 常受限），尝试镜像直装..."
    install_xray_from_mirror || { error "Xray 安装失败，请检查网络或手动安装"; exit 1; }
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
                "flow": "${FLOW}",
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
          "spiderX": "${SPIDER_X}"
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

write_systemd_service() {
    cat > /etc/systemd/system/xray-client.service <<EOF
[Unit]
Description=Xray Client - VPN VLESS+Reality
Documentation=https://xtls.github.io
After=network.target nss-lookup.target

[Service]
User=nobody
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=${XRAY_BIN} run -config ${XRAY_CONFIG_DIR}/client.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
}

do_install() {
    if [[ $EUID -ne 0 ]]; then
        error "Linux 下请以 root 权限运行: sudo $0 install ..."
        exit 1
    fi

    if [[ -z "$UUID" || -z "$PUBLIC_KEY" || -z "$SHORT_ID" ]]; then
        error "缺少必需参数！请从出口节点部署输出中获取并填写，二选一:"
        echo ""
        echo "方式一：--vless= 直接传入完整 VLESS 链接（务必用引号包裹）:"
        echo "  sudo $0 install --vless=\"vless://<UUID>@<HOST>:<PORT>?...&pbk=...&sid=...#标签\""
        echo ""
        echo "方式二：手动指定三个必需参数:"
        echo "  sudo $0 install --uuid=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \\"
        echo "                  --public-key=<base64_public_key> \\"
        echo "                  --short-id=<8_hex_chars>"
        echo ""
        echo "两者不能同时使用。"
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

    step "安装 Xray-core"
    if ! command -v xray &>/dev/null; then
        if $DRY_RUN; then
            info "[dry-run] 将安装 Xray-core"
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

    step "配置 xray-client systemd 服务"
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

    step "验证代理连通性"
    if ! $DRY_RUN; then
        sleep 1
        if port_listening "${SOCKS_PORT}"; then
            success "SOCKS5 代理端口 ${SOCKS_PORT} 监听中"
        else
            warn "SOCKS5 端口 ${SOCKS_PORT} 未监听，检查 Xray 日志"
        fi

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
            warn "诊断命令: $0 status  或  journalctl -u xray-client -n 30"
        fi
    fi

    step "客户端配置完成！"
    cat <<EOF

${BOLD}━━━ 代理端口 ━━━${RESET}
  SOCKS5  : socks5h://127.0.0.1:${SOCKS_PORT}
  HTTP    : http://127.0.0.1:${HTTP_PORT}

${BOLD}━━━ 终端代理（可选）━━━${RESET}
  $0 proxy on      # 写入 ~/.config/vpn/proxy.env 并自动加载到 ~/.bashrc / ~/.zshrc
  $0 proxy off     # 关闭终端代理
  $0 proxy status  # 查看当前状态 + xray 日志查看方式
  $0 proxy test    # 测试代理端口 + 实际连通性是否正常

${BOLD}━━━ 全局 setproxy 命令（可选）━━━${RESET}
  ./install-setproxy.sh          # 安装 setproxy 到 ~/.local/bin
  setproxy on | off | status | test  # 之后任意目录可直接使用

${BOLD}━━━ 浏览器配置 ━━━${RESET}
  SwitchyOmega → SOCKS5 → 127.0.0.1:${SOCKS_PORT}

${BOLD}━━━ curl / wget 使用 ━━━${RESET}
  curl -x socks5h://127.0.0.1:${SOCKS_PORT} https://claude.ai/
  curl -x http://127.0.0.1:${HTTP_PORT}      https://claude.ai/

${BOLD}━━━ 服务管理命令 ━━━${RESET}
  查看状态   : $0 status
  停止卸载   : $0 clean
  查看日志   : journalctl -u xray-client -f
  重启服务   : systemctl restart xray-client

${BOLD}━━━ 路由策略说明 ━━━${RESET}
  国内域名/IP     → 直连（不走代理）
  claude.ai 等    → 通过 ${RELAY_IP} 中继代理
  其余境外流量    → 通过代理
EOF

    echo -e "${GREEN}${BOLD}客户端部署完成！${RESET} 现在可以通过 SOCKS5 代理访问 claude.ai"
}

# ── status ───────────────────────────────────────────────────────────────────
do_status() {
    echo -e "\n${BOLD}━━━ Xray 客户端状态 ━━━${RESET}"
    systemctl status xray-client 2>/dev/null || \
        systemctl status xray 2>/dev/null || \
        echo "Xray 服务未找到"

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
    ss -tlnp 2>/dev/null | grep -E "${SOCKS_PORT}|${HTTP_PORT}" || echo "代理端口未监听"

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
    if [[ $EUID -ne 0 ]]; then
        error "Linux 下请以 root 权限运行: sudo $0 clean"
        exit 1
    fi
    step "停止并移除 Xray 客户端"
    systemctl stop xray-client 2>/dev/null || true
    systemctl disable xray-client 2>/dev/null || true
    rm -f /etc/systemd/system/xray-client.service
    rm -f /usr/local/etc/xray/client.json
    systemctl daemon-reload
    success "Xray 客户端已停止并移除"
}

# ── proxy: 终端环境变量代理 ──────────────────────────────────────────────────
ensure_shell_hook() {
    local rc="$1"
    [[ -f "$rc" ]] || return 0
    if grep -qF "$MARKER_BEGIN" "$rc" 2>/dev/null; then
        return 0
    fi
    {
        echo ""
        echo "$MARKER_BEGIN"
        echo "$HOOK_LINE"
        echo "$MARKER_END"
    } >> "$rc"
    info "已写入 shell 钩子: ${rc}"
}

write_proxy_env() {
    mkdir -p "$PROXY_DIR"
    cat > "$PROXY_ENV" <<EOF
# VPN shell proxy — managed by linux_setup.sh
export http_proxy="http://${HTTP_HOST}:${HTTP_PORT}"
export https_proxy="http://${HTTP_HOST}:${HTTP_PORT}"
export HTTP_PROXY="http://${HTTP_HOST}:${HTTP_PORT}"
export HTTPS_PROXY="http://${HTTP_HOST}:${HTTP_PORT}"
export all_proxy="socks5h://${SOCKS_HOST}:${SOCKS_PORT}"
export ALL_PROXY="socks5h://${SOCKS_HOST}:${SOCKS_PORT}"
export no_proxy="127.0.0.1,localhost"
export NO_PROXY="127.0.0.1,localhost"
EOF
    chmod 600 "$PROXY_ENV"
}

emit_exports() { grep -E '^export ' "$PROXY_ENV"; }

apply_to_current_shell() {
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        # shellcheck disable=SC1090
        source "$PROXY_ENV"
        success "当前 shell 已加载代理环境变量"
    fi
}

clear_current_shell() {
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
        unset all_proxy ALL_PROXY no_proxy NO_PROXY
        success "当前 shell 已清除代理环境变量"
    fi
}

xray_log_hint() {
    echo -e "${BOLD}━━━ 查看 Xray 是否正常工作 ━━━${RESET}"
    echo "  服务状态 : systemctl status xray-client"
    echo "  最近日志 : journalctl -u xray-client -n 50 --no-pager"
    echo "  实时日志 : journalctl -u xray-client -f"
}

proxy_on() {
    if ! port_listening "$HTTP_PORT"; then
        warn "HTTP 代理端口 ${HTTP_HOST}:${HTTP_PORT} 未监听，请先 install 或 systemctl start xray-client"
    fi
    if ! port_listening "$SOCKS_PORT"; then
        warn "SOCKS 代理端口 ${SOCKS_HOST}:${SOCKS_PORT} 未监听，请先 install 或 systemctl start xray-client"
    fi

    write_proxy_env
    ensure_shell_hook "${HOME}/.bashrc"
    [[ -f "${HOME}/.zshrc"   ]] && ensure_shell_hook "${HOME}/.zshrc"
    [[ -f "${HOME}/.profile" ]] && ensure_shell_hook "${HOME}/.profile"

    if $PROXY_EMIT; then
        emit_exports
        return 0
    fi

    success "终端代理已开启（新开的终端自动生效）"
    info "HTTP/HTTPS → http://${HTTP_HOST}:${HTTP_PORT}"
    info "ALL_PROXY  → socks5h://${SOCKS_HOST}:${SOCKS_PORT}"
    info "配置文件   → ${PROXY_ENV}"

    apply_to_current_shell
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        echo ""
        warn "当前已打开的终端需手动加载一次:"
        echo "  source ${PROXY_ENV}"
        echo "  或: eval \"\$(./linux_setup.sh proxy on --emit)\""
    fi

    if port_listening "$HTTP_PORT"; then
        if curl -x "http://${HTTP_HOST}:${HTTP_PORT}" -fsSL --connect-timeout 10 \
            -o /dev/null https://api4.ipify.org 2>/dev/null; then
            success "代理连通性检查通过（api4.ipify.org）"
        else
            warn "代理端口在监听，但连通性测试未通过，请检查 xray-client 日志"
        fi
    fi
}

proxy_off() {
    rm -f "$PROXY_ENV"
    success "终端代理已关闭（新开的终端将直连）"
    clear_current_shell
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        echo ""
        info "当前已打开的终端请执行:"
        echo "  unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY"
    fi
}

proxy_status() {
    echo -e "${BOLD}配置文件${RESET}"
    if [[ -f "$PROXY_ENV" ]]; then
        echo -e "  状态: ${GREEN}已开启${RESET}"
        echo "  路径: ${PROXY_ENV}"
        echo ""
        echo -e "${BOLD}代理变量（配置文件）${RESET}"
        sed 's/^/  /' "$PROXY_ENV" | grep -v '^  #' || true
    else
        echo -e "  状态: ${YELLOW}已关闭${RESET}（${PROXY_ENV} 不存在）"
    fi

    echo ""
    echo -e "${BOLD}当前 shell 环境变量${RESET}"
    local any=false
    for v in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY; do
        if [[ -n "${!v:-}" ]]; then
            echo "  ${v}=${!v}"
            any=true
        fi
    done
    $any || echo "  （未设置）"

    echo ""
    echo -e "${BOLD}Xray 本地端口${RESET}"
    if port_listening "$HTTP_PORT"; then
        echo -e "  HTTP  ${HTTP_HOST}:${HTTP_PORT} ${GREEN}监听中${RESET}"
    else
        echo -e "  HTTP  ${HTTP_HOST}:${HTTP_PORT} ${RED}未监听${RESET}"
    fi
    if port_listening "$SOCKS_PORT"; then
        echo -e "  SOCKS ${SOCKS_HOST}:${SOCKS_PORT} ${GREEN}监听中${RESET}"
    else
        echo -e "  SOCKS ${SOCKS_HOST}:${SOCKS_PORT} ${RED}未监听${RESET}"
    fi

    echo ""
    echo -e "${BOLD}Shell 钩子${RESET}"
    for rc in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.profile"; do
        if [[ -f "$rc" ]] && grep -qF "$MARKER_BEGIN" "$rc" 2>/dev/null; then
            echo "  ${rc}: 已安装"
        fi
    done

    echo ""
    xray_log_hint
}

proxy_test() {
    local ok=true

    echo -e "${BOLD}━━━ 1. 配置与端口 ━━━${RESET}"
    if [[ -f "$PROXY_ENV" ]]; then
        echo -e "  proxy.env: ${GREEN}存在${RESET} (${PROXY_ENV})"
    else
        echo -e "  proxy.env: ${YELLOW}不存在${RESET}（尚未 proxy on，以下仍按固定端口测试）"
    fi
    if [[ -n "${http_proxy:-}${all_proxy:-}" ]]; then
        echo -e "  当前 shell 环境变量: ${GREEN}已设置${RESET}"
    else
        echo -e "  当前 shell 环境变量: ${YELLOW}未设置${RESET}（不影响本次测试，测试直接使用固定端口）"
    fi

    if port_listening "$HTTP_PORT"; then
        echo -e "  HTTP  端口 ${HTTP_PORT}: ${GREEN}监听中${RESET}"
    else
        echo -e "  HTTP  端口 ${HTTP_PORT}: ${RED}未监听${RESET}"
        ok=false
    fi
    if port_listening "$SOCKS_PORT"; then
        echo -e "  SOCKS 端口 ${SOCKS_PORT}: ${GREEN}监听中${RESET}"
    else
        echo -e "  SOCKS 端口 ${SOCKS_PORT}: ${RED}未监听${RESET}"
        ok=false
    fi

    echo ""
    echo -e "${BOLD}━━━ 2. 连通性测试（直接经过代理端口，不依赖当前 shell 变量）━━━${RESET}"
    local ipify_code claude_code
    ipify_code=$(curl -x "http://${HTTP_HOST}:${HTTP_PORT}" -fsSL --connect-timeout 10 \
        -o /dev/null -w "%{http_code}" https://api4.ipify.org 2>/dev/null) || ipify_code="000"
    if [[ "$ipify_code" =~ ^2 ]]; then
        echo -e "  ipify.org  (HTTP代理) : ${GREEN}HTTP ${ipify_code}${RESET}"
    else
        echo -e "  ipify.org  (HTTP代理) : ${RED}HTTP ${ipify_code}${RESET}"
        ok=false
    fi

    claude_code=$(curl -x "socks5h://${SOCKS_HOST}:${SOCKS_PORT}" -fsSL --connect-timeout 10 \
        -o /dev/null -w "%{http_code}" https://claude.ai/ 2>/dev/null) || claude_code="000"
    if [[ "$claude_code" =~ ^2 ]] || [[ "$claude_code" == "403" ]]; then
        echo -e "  claude.ai  (SOCKS代理): ${GREEN}HTTP ${claude_code}${RESET}（403 也可能表示代理已通，属 Cloudflare 策略）"
    else
        echo -e "  claude.ai  (SOCKS代理): ${RED}HTTP ${claude_code}${RESET}"
        ok=false
    fi

    echo ""
    if $ok; then
        success "代理测试通过：端口监听正常，且可经代理访问外网"
    else
        error "代理测试未完全通过，请检查 Xray 客户端是否正常运行"
        echo ""
        xray_log_hint
    fi
}

do_proxy() {
    case "$PROXY_ACTION" in
        on)     proxy_on ;;
        off)    proxy_off ;;
        status) proxy_status ;;
        test)   proxy_test ;;
        "") error "请指定动作: $0 proxy on | off | status | test"; exit 1 ;;
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
