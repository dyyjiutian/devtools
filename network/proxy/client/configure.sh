#!/usr/bin/env bash
# =============================================================================
# 海外加速 - 客户端自动配置脚本
# 自动修改 hosts 文件，实现 GitHub / Docker Hub 国内加速
# 用法: sudo ./configure.sh <SERVER_IP> [--clean]
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
step()    { echo -e "\n${BOLD}==> $*${RESET}"; }

# ── 参数 ──────────────────────────────────────────────────────────────────────
SERVER_IP="${1:-}"
CLEAN_MODE=false
HOSTS_MARKER="# ── Overseas Proxy [managed by devtools] ──"

for arg in "${@:2}"; do
    case $arg in
        --clean) CLEAN_MODE=true ;;
        --help|-h)
            echo "Usage: sudo $0 <SERVER_IP> [--clean]"
            echo ""
            echo "  <SERVER_IP>  新加坡 ECS 公网 IP"
            echo "  --clean      移除之前添加的 hosts 条目"
            exit 0
            ;;
    esac
done

# ── 检查权限和参数 ─────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "需要 root 权限，请使用: sudo $0 $*"
    exit 1
fi

# 检测 hosts 文件位置
case "$(uname -s)" in
    Darwin|Linux) HOSTS_FILE="/etc/hosts" ;;
    *)            HOSTS_FILE="/etc/hosts" ;;
esac

if $CLEAN_MODE; then
    step "清除之前添加的 hosts 条目"
    if grep -q "$HOSTS_MARKER" "$HOSTS_FILE" 2>/dev/null; then
        # 删除标记块
        TEMP=$(mktemp)
        awk "/$HOSTS_MARKER START/,/$HOSTS_MARKER END/{next} 1" "$HOSTS_FILE" > "$TEMP"
        cp "$TEMP" "$HOSTS_FILE"
        rm -f "$TEMP"
        success "hosts 条目已清除"
    else
        info "未找到之前添加的条目，无需清理"
    fi
    exit 0
fi

if [[ -z "$SERVER_IP" ]]; then
    error "请提供服务器 IP: sudo $0 <SERVER_IP>"
    exit 1
fi

# 验证 IP 格式
if ! echo "$SERVER_IP" | grep -qP '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$'; then
    error "无效的 IP 地址: $SERVER_IP"
    exit 1
fi

# ── 备份 hosts 文件 ────────────────────────────────────────────────────────────
step "备份 hosts 文件"
BACKUP="${HOSTS_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
cp "$HOSTS_FILE" "$BACKUP"
success "已备份到: $BACKUP"

# ── 清理旧条目 ─────────────────────────────────────────────────────────────────
if grep -q "$HOSTS_MARKER" "$HOSTS_FILE" 2>/dev/null; then
    step "检测到旧配置，先清理"
    TEMP=$(mktemp)
    awk "/$HOSTS_MARKER START/,/$HOSTS_MARKER END/{next} 1" "$HOSTS_FILE" > "$TEMP"
    cp "$TEMP" "$HOSTS_FILE"
    rm -f "$TEMP"
    info "旧条目已清除"
fi

# ── 写入新 hosts 条目 ──────────────────────────────────────────────────────────
step "写入海外加速 hosts 条目 (IP: ${SERVER_IP})"

cat >> "$HOSTS_FILE" <<EOF

${HOSTS_MARKER} START
# 配置时间: $(date '+%Y-%m-%d %H:%M:%S')
# 服务器IP: ${SERVER_IP}

# ── GitHub ────────────────────────────────────────────────────────────────
${SERVER_IP}  github.com
${SERVER_IP}  www.github.com
${SERVER_IP}  api.github.com
${SERVER_IP}  gist.github.com
${SERVER_IP}  codeload.github.com
${SERVER_IP}  assets-cdn.github.com

# GitHub 静态资源
${SERVER_IP}  raw.githubusercontent.com
${SERVER_IP}  gist.githubusercontent.com
${SERVER_IP}  cloud.githubusercontent.com
${SERVER_IP}  camo.githubusercontent.com
${SERVER_IP}  avatars.githubusercontent.com
${SERVER_IP}  avatars0.githubusercontent.com
${SERVER_IP}  avatars1.githubusercontent.com
${SERVER_IP}  avatars2.githubusercontent.com
${SERVER_IP}  avatars3.githubusercontent.com
${SERVER_IP}  user-images.githubusercontent.com
${SERVER_IP}  objects.githubusercontent.com
${SERVER_IP}  github-releases.githubusercontent.com
${SERVER_IP}  media.githubusercontent.com
${SERVER_IP}  github.githubassets.com

# ── Docker Hub ────────────────────────────────────────────────────────────
${SERVER_IP}  registry-1.docker.io
${SERVER_IP}  auth.docker.io
${SERVER_IP}  index.docker.io
${SERVER_IP}  production.cloudflare.docker.com

${HOSTS_MARKER} END
EOF

success "hosts 条目写入完成"

# ── 刷新 DNS 缓存 ──────────────────────────────────────────────────────────────
step "刷新 DNS 缓存"

flush_dns() {
    case "$(uname -s)" in
        Darwin)
            dscacheutil -flushcache
            killall -HUP mDNSResponder 2>/dev/null || true
            success "macOS DNS 缓存已刷新"
            ;;
        Linux)
            if systemctl is-active systemd-resolved &>/dev/null; then
                systemd-resolve --flush-caches 2>/dev/null \
                  || resolvectl flush-caches 2>/dev/null \
                  || true
                success "systemd-resolved DNS 缓存已刷新"
            elif command -v nscd &>/dev/null; then
                nscd -i hosts 2>/dev/null || service nscd restart 2>/dev/null || true
                success "nscd 缓存已刷新"
            else
                info "无 DNS 缓存服务，hosts 更改立即生效"
            fi
            ;;
    esac
}

flush_dns

# ── 验证配置 ───────────────────────────────────────────────────────────────────
step "验证配置"

check_domain() {
    local domain=$1
    local resolved
    resolved=$(getent hosts "$domain" 2>/dev/null | awk '{print $1}' || true)
    if [[ "$resolved" == "$SERVER_IP" ]]; then
        success "${domain} -> ${resolved}"
    else
        warn "${domain} -> ${resolved:-未解析} (期望: ${SERVER_IP})"
    fi
}

check_domain "github.com"
check_domain "raw.githubusercontent.com"
check_domain "registry-1.docker.io"

# ── 完成 ───────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}配置完成！${RESET}"
echo ""
echo "测试访问:"
echo "  curl -I https://github.com"
echo "  curl -I https://raw.githubusercontent.com"
echo ""
echo "如需恢复:"
echo "  sudo $0 $SERVER_IP --clean"
echo "  或手动还原备份: sudo cp $BACKUP $HOSTS_FILE"
