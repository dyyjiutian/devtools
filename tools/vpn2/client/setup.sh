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

# ── OS 检测 ───────────────────────────────────────────────────────────────────
OS_TYPE="linux"
if [[ "$(uname)" == "Darwin" ]]; then
    OS_TYPE="macos"
fi

# ── 参数解析 ──────────────────────────────────────────────────────────────────
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
        --no-mirror)     USE_MIRROR=false ;;
        --force)         FORCE_SETUP=true ;;
        --clean)         ACTION="clean" ;;
        --status)        ACTION="status" ;;
        --help|-h)
            cat <<'HELP'
Usage: ./client/setup.sh --uuid=<UUID> --public-key=<KEY> --short-id=<SID> [OPTIONS]
       (macOS 不需要 sudo；Linux 需要 sudo)


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
  --no-mirror          禁用国内镜像，仅从 GitHub 下载（境外环境可用）
  --force              跳过中继节点 TCP 连通性预检
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
    if [[ "$OS_TYPE" == "macos" ]]; then
        BREW_PREFIX=$(brew --prefix 2>/dev/null || echo "/opt/homebrew")
        XRAY_BIN="${BREW_PREFIX}/bin/xray"
        XRAY_CONFIG_DIR="${BREW_PREFIX}/etc/xray"
        XRAY_DAT_DIR="${BREW_PREFIX}/share/xray"
    else
        XRAY_BIN="/usr/local/bin/xray"
        XRAY_CONFIG_DIR="/usr/local/etc/xray"
        XRAY_DAT_DIR="/usr/local/share/xray"
    fi

    echo -e "\n${BOLD}━━━ Xray 客户端状态 ━━━${RESET}"
    if [[ "$OS_TYPE" == "macos" ]]; then
        PLIST="$HOME/Library/LaunchAgents/com.vpn2.xray-client.plist"
        launchctl list | grep "com.vpn2.xray-client" 2>/dev/null \
            || echo "Xray 服务未运行（launchctl 中未找到 com.vpn2.xray-client）"
        [[ -f "$PLIST" ]] && echo "Plist: $PLIST" || echo "Plist 文件不存在: $PLIST"
    else
        systemctl status xray-client 2>/dev/null || \
        systemctl status xray 2>/dev/null || \
        echo "Xray 服务未找到"
    fi
    echo ""
    echo -e "${BOLD}━━━ Geo 路由数据 ━━━${RESET}"
    for f in geoip.dat geosite.dat; do
        fp="${XRAY_DAT_DIR}/${f}"
        if [[ -f "$fp" ]]; then
            sz=$(stat -c%s "$fp" 2>/dev/null || stat -f%z "$fp" 2>/dev/null || echo 0)
            echo "  ${f}: 存在 (${sz} bytes)"
        else
            echo "  ${f}: ${RED}缺失${RESET} — 路由规则 geoip:cn / geosite:cn 无法生效"
        fi
    done
    echo ""
    echo -e "${BOLD}━━━ 中继节点连通性 ━━━${RESET}"
    if tcp_reachable "${RELAY_IP}" "${RELAY_PORT}"; then
        echo "  ${RELAY_IP}:${RELAY_PORT} TCP 可达"
    else
        echo "  ${RELAY_IP}:${RELAY_PORT} ${RED}TCP 不可达${RESET} — 请检查中继节点部署与安全组"
    fi
    echo ""
    echo -e "${BOLD}━━━ 代理端口监听 ━━━${RESET}"
    if [[ "$OS_TYPE" == "macos" ]]; then
        lsof -iTCP:${SOCKS_PORT} -sTCP:LISTEN 2>/dev/null || echo "SOCKS5 端口 ${SOCKS_PORT} 未监听"
        lsof -iTCP:${HTTP_PORT} -sTCP:LISTEN 2>/dev/null || echo "HTTP 端口 ${HTTP_PORT} 未监听"
    else
        ss -tlnp | grep -E "10808|10809" || echo "代理端口未监听"
    fi
    if [[ -f "${XRAY_CONFIG_DIR}/client.json" ]] && command -v xray &>/dev/null; then
        echo ""
        echo -e "${BOLD}━━━ 配置校验 ━━━${RESET}"
        if xray run -test -config "${XRAY_CONFIG_DIR}/client.json" 2>/tmp/xray-status-test.log; then
            echo "  配置文件校验通过"
        else
            echo "  ${RED}配置文件校验失败${RESET}:"
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
    exit 0
fi

# ── 清除模式 ──────────────────────────────────────────────────────────────────
if [[ "$ACTION" == "clean" ]]; then
    step "停止并移除 Xray 客户端"
    if [[ "$OS_TYPE" == "macos" ]]; then
        PLIST="$HOME/Library/LaunchAgents/com.vpn2.xray-client.plist"
        launchctl unload "$PLIST" 2>/dev/null || true
        rm -f "$PLIST"
        BREW_PREFIX=$(brew --prefix 2>/dev/null || echo "/usr/local")
        rm -f "${BREW_PREFIX}/etc/xray/client.json"
    else
        systemctl stop xray-client 2>/dev/null || true
        systemctl disable xray-client 2>/dev/null || true
        rm -f /etc/systemd/system/xray-client.service
        rm -f /usr/local/etc/xray/client.json
        systemctl daemon-reload
    fi
    success "Xray 客户端已停止并移除"
    exit 0
fi

# ── 前置检查 ──────────────────────────────────────────────────────────────────
if [[ "$OS_TYPE" == "linux" && $EUID -ne 0 ]]; then
    error "Linux 下请以 root 权限运行: sudo $0"
    exit 1
fi

if [[ "$OS_TYPE" == "macos" && $EUID -eq 0 ]]; then
    warn "macOS 下不建议以 root 运行，使用普通用户权限即可"
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

UUID_NORM=$(echo "$UUID" | tr '[:upper:]' '[:lower:]')
if [[ ! "$UUID_NORM" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    error "UUID 格式无效（须为十六进制且形如 xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx）。"
    error "请从出口节点 cat /root/.vpn2_exit_config 完整复制，避免手打出错字符。"
    exit 1
fi
SHORT_ID_NORM=$(echo "$SHORT_ID" | tr '[:upper:]' '[:lower:]')
if [[ ! "$SHORT_ID_NORM" =~ ^[0-9a-f]+$ ]] || [[ ${#SHORT_ID_NORM} -gt 16 ]]; then
    error "Short ID 须为非空的十六进制字符串（常见长度 8）。当前值无效。"
    exit 1
fi
UUID="$UUID_NORM"
SHORT_ID="$SHORT_ID_NORM"

port_listening() {
    local p="$1"
    if [[ "$OS_TYPE" == "macos" ]]; then
        lsof -iTCP:"$p" -sTCP:LISTEN &>/dev/null
    else
        ss -tlnp | grep -q ":$p"
    fi
}

run() {
    if $DRY_RUN; then
        info "[dry-run] $*"
    else
        "$@"
    fi
}

file_size() {
    local f="$1"
    if [[ "$OS_TYPE" == "macos" ]]; then
        stat -f%z "$f" 2>/dev/null || echo 0
    else
        stat -c%s "$f" 2>/dev/null || echo 0
    fi
}

tcp_reachable() {
    local host="$1" port="$2"
    if command -v nc &>/dev/null; then
        if [[ "$OS_TYPE" == "macos" ]]; then
            nc -z -G 5 "$host" "$port" 2>/dev/null
        else
            nc -z -w 5 "$host" "$port" 2>/dev/null
        fi
        return $?
    fi
    (echo > /dev/tcp/"$host"/"$port") 2>/dev/null
}

download_file_with_mirrors() {
    local dest="$1"
    shift
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

# ── 安装 Xray ─────────────────────────────────────────────────────────────────
step "安装 Xray-core"

if [[ "$OS_TYPE" == "macos" ]]; then
    BREW_PREFIX=$(brew --prefix 2>/dev/null || echo "/opt/homebrew")
    XRAY_BIN="${BREW_PREFIX}/bin/xray"
    XRAY_CONFIG_DIR="${BREW_PREFIX}/etc/xray"
    XRAY_DAT_DIR="${BREW_PREFIX}/share/xray"
    LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/com.vpn2.xray-client.plist"
else
    XRAY_BIN="/usr/local/bin/xray"
    XRAY_CONFIG_DIR="/usr/local/etc/xray"
    XRAY_DAT_DIR="/usr/local/share/xray"
fi

install_xray_linux_from_mirror() {
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
    if [[ "$OS_TYPE" == "macos" ]]; then
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
        return
    fi

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
    install_xray_linux_from_mirror || { error "Xray 安装失败，请检查网络或手动安装"; exit 1; }
}

if ! command -v xray &>/dev/null; then
    if $DRY_RUN; then
        info "[dry-run] 将安装 Xray-core"
    else
        install_xray
    fi
else
    XRAY_VER=$(xray version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    success "Xray 已安装: v${XRAY_VER}"
fi

if ! $DRY_RUN; then
    ensure_geo_data "$XRAY_DAT_DIR" || exit 1
fi

# ── 写入客户端配置 ────────────────────────────────────────────────────────────
step "写入 Xray 客户端配置"

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
JSON_EOF
    chmod 644 "${XRAY_CONFIG_DIR}/client.json"
}

if $DRY_RUN; then
    info "[dry-run] 将写入客户端配置到 ${XRAY_CONFIG_DIR}/client.json"
else
    write_client_config
    success "客户端配置已写入: ${XRAY_CONFIG_DIR}/client.json"
    validate_xray_config
fi

# ── 配置后台服务 ──────────────────────────────────────────────────────────────
if [[ "$OS_TYPE" == "macos" ]]; then
    step "配置 xray-client LaunchAgent（macOS）"

    write_launch_agent() {
        mkdir -p "$HOME/Library/LaunchAgents"
        cat > "$LAUNCH_AGENT_PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.vpn2.xray-client</string>
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
else
    step "配置 xray-client systemd 服务（Linux）"

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
ExecStart=${XRAY_BIN} run -config ${XRAY_CONFIG_DIR}/client.json
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
fi

# ── 验证连通性 ────────────────────────────────────────────────────────────────
step "验证代理连通性"

if ! $DRY_RUN; then
    info "等待代理端口就绪..."
    sleep 1

    # 验证 SOCKS 端口
    if port_listening "${SOCKS_PORT}"; then
        success "SOCKS5 代理端口 ${SOCKS_PORT} 监听中"
    else
        warn "SOCKS5 端口 ${SOCKS_PORT} 未监听，检查 Xray 日志"
    fi

    # 尝试通过代理访问（ipify 比 claude.ai 更可靠；claude 可能返回 403）
    info "测试通过代理访问 api4.ipify.org..."
    HTTP_CODE=$(curl -x "socks5h://127.0.0.1:${SOCKS_PORT}" \
        -fsSL --connect-timeout 15 \
        -o /dev/null -w "%{http_code}" \
        https://api4.ipify.org 2>/dev/null) || HTTP_CODE="000"

    if [[ "$HTTP_CODE" =~ ^2 ]]; then
        success "代理链路畅通！ipify.org HTTP 状态: ${HTTP_CODE}"
    else
        warn "ipify.org 访问测试返回: ${HTTP_CODE}"
        warn "若 SOCKS 端口已监听，请检查 UUID / PublicKey / ShortID 是否与出口节点一致"
        warn "诊断命令: $0 --status  或  journalctl -u xray-client -n 30"
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
  查看状态   : $0 --status
  停止卸载   : $0 --clean
$(if [[ "$OS_TYPE" == "macos" ]]; then
echo "  查看日志   : tail -f /tmp/xray-client.log"
echo "  重启服务   : launchctl unload ~/Library/LaunchAgents/com.vpn2.xray-client.plist && launchctl load -w ~/Library/LaunchAgents/com.vpn2.xray-client.plist"
else
echo "  查看日志   : journalctl -u xray-client -f"
echo "  重启服务   : systemctl restart xray-client"
fi)

${BOLD}━━━ 路由策略说明 ━━━${RESET}
  国内域名/IP     → 直连（不走代理）
  claude.ai 等    → 通过 ${RELAY_IP} 中继代理
  其余境外流量    → 通过代理

EOF

echo -e "${GREEN}${BOLD}客户端部署完成！${RESET} 现在可以通过 SOCKS5 代理访问 claude.ai"
