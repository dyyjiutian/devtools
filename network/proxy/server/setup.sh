#!/usr/bin/env bash
# =============================================================================
# 海外代理站点 - 服务端安装脚本（新加坡 ECS）
# 功能：基于 Nginx Stream SNI 透明代理，无需 SSL 证书
# 支持：CentOS/RHEL 7/8/9、Ubuntu 20.04/22.04
# 用法：sudo ./setup.sh [--with-docker-mirror] [--dry-run]
# =============================================================================

set -euo pipefail

# ── 颜色输出 ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
step()    { echo -e "\n${BOLD}==> $*${RESET}"; }

# ── 参数解析 ──────────────────────────────────────────────────────────────────
WITH_DOCKER_MIRROR=false
DRY_RUN=false

for arg in "$@"; do
    case $arg in
        --with-docker-mirror) WITH_DOCKER_MIRROR=true ;;
        --dry-run)            DRY_RUN=true ;;
        --help|-h)
            echo "Usage: sudo $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --with-docker-mirror   同时部署 Docker Hub 镜像站（pull-through cache）"
            echo "  --dry-run              预览操作，不实际执行"
            echo "  --help                 显示帮助"
            exit 0
            ;;
        *) warn "未知参数: $arg" ;;
    esac
done

# ── 前置检查 ──────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "请以 root 权限运行: sudo $0"
    exit 1
fi

step "检测系统环境"

OS=""
PKG_MGR=""
if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    case "$ID" in
        centos|rhel|almalinux|rocky|alinux|anolis) OS="rhel"; PKG_MGR="yum" ;;
        ubuntu|debian)               OS="debian"; PKG_MGR="apt" ;;
        *) error "不支持的发行版: $ID"; exit 1 ;;
    esac
fi

SERVER_IP="$(curl -sf --connect-timeout 5 https://api4.ipify.org || true)"
if [[ -z "$SERVER_IP" ]]; then
    SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
fi
info "服务器公网 IP: ${SERVER_IP}"
info "操作系统: ${PRETTY_NAME:-unknown}"
info "包管理器: ${PKG_MGR}"

$DRY_RUN && { warn "[dry-run] 仅预览，不执行实际操作"; }

run() {
    if $DRY_RUN; then
        info "[dry-run] $*"
    else
        "$@"
    fi
}

# ── 安装 Nginx ─────────────────────────────────────────────────────────────────
step "安装 Nginx（带 stream 模块）"

install_nginx_rhel() {
    # 优先使用系统自带仓库的 nginx（Alibaba Cloud Linux / RHEL 系均可用）
    # nginx-mod-stream 提供 stream 动态模块
    run yum install -y nginx nginx-mod-stream
}

install_nginx_debian() {
    run apt-get update -qq
    run apt-get install -y nginx
}

if ! command -v nginx &>/dev/null; then
    case $OS in
        rhel)   install_nginx_rhel ;;
        debian) install_nginx_debian ;;
    esac
    success "Nginx 安装完成"
else
    NGINX_VER=$(nginx -v 2>&1 | sed -n 's/.*\([0-9][0-9.]*\).*/\1/p' | head -1)
    success "Nginx 已安装: v${NGINX_VER}"
fi

# 验证 stream 模块（静态编译 或 动态模块文件均可）
STREAM_MODULE_OK=false
nginx -V 2>&1 | grep -q 'with-stream' && STREAM_MODULE_OK=true
ls /usr/lib64/nginx/modules/ngx_stream_module.so 2>/dev/null && STREAM_MODULE_OK=true
ls /etc/nginx/conf.modules.d/*stream* 2>/dev/null && STREAM_MODULE_OK=true
if ! $STREAM_MODULE_OK; then
    error "未找到 stream 模块，请安装: sudo yum install -y nginx-mod-stream"
    exit 1
fi
success "stream 模块可用"

# ── 配置 Nginx Stream SNI 代理 ────────────────────────────────────────────────
step "配置 Nginx SNI 透明代理"

STREAM_DIR="/etc/nginx/stream.d"
SNI_CONF="${STREAM_DIR}/sni_proxy.conf"
NGINX_CONF="/etc/nginx/nginx.conf"

run mkdir -p "$STREAM_DIR"

# 写入 SNI 代理配置
write_sni_conf() {
    cat > "$SNI_CONF" <<'NGINX_CONF_EOF'
# Nginx Stream SNI Proxy - 透明转发 HTTPS，无需 SSL 证书
stream {
    log_format sni_proxy '$remote_addr [$time_local] '
                         '$protocol $status $bytes_sent $bytes_received '
                         '$session_time -> $upstream_addr '
                         'sni=[$ssl_preread_server_name]';

    access_log /var/log/nginx/sni_proxy.log sni_proxy;

    resolver 8.8.8.8 8.8.4.4 1.1.1.1 valid=300s ipv6=off;
    resolver_timeout 10s;

    map $ssl_preread_server_name $proxy_target {
        # GitHub 生态
        ~^(.+\.)?github\.com$               $ssl_preread_server_name:443;
        ~^(.+\.)?githubusercontent\.com$     $ssl_preread_server_name:443;
        ~^(.+\.)?githubassets\.com$          $ssl_preread_server_name:443;
        ~^(.+\.)?githubstatus\.com$          $ssl_preread_server_name:443;

        # Docker Hub
        ~^(.+\.)?docker\.io$                $ssl_preread_server_name:443;
        ~^(.+\.)?docker\.com$               $ssl_preread_server_name:443;

        # 未匹配：不转发，避免成为开放代理
        default                              "";
    }

    server {
        listen 0.0.0.0:443;
        ssl_preread on;
        proxy_pass $proxy_target;
        proxy_connect_timeout 30s;
        proxy_timeout 600s;
        proxy_buffer_size 32k;
        proxy_socket_keepalive on;
    }
}
NGINX_CONF_EOF
}

if $DRY_RUN; then
    info "[dry-run] 将写入 SNI 代理配置到 ${SNI_CONF}"
else
    write_sni_conf
    success "SNI 代理配置已写入: ${SNI_CONF}"
fi

# 在 nginx.conf 中添加 stream include（如果未配置）
patch_nginx_conf() {
    if grep -q "stream.d" "$NGINX_CONF"; then
        info "nginx.conf 已包含 stream.d include，跳过"
        return
    fi
    # 在文件末尾（http 块外）追加 stream include
    if grep -q "^stream" "$NGINX_CONF"; then
        warn "nginx.conf 已有 stream 块，请手动将以下内容合并:"
        echo "    include ${STREAM_DIR}/*.conf;"
        return
    fi
    # 追加到文件末尾
    echo "" >> "$NGINX_CONF"
    echo "# SNI Proxy - included by setup.sh" >> "$NGINX_CONF"
    echo "include ${STREAM_DIR}/*.conf;" >> "$NGINX_CONF"
    success "已在 nginx.conf 末尾追加 stream include"
}

if $DRY_RUN; then
    info "[dry-run] 将修改 ${NGINX_CONF} 添加 stream include"
else
    patch_nginx_conf
fi

# ── 配置防火墙 ────────────────────────────────────────────────────────────────
step "配置防火墙开放端口 443"

open_firewall() {
    if command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
        run firewall-cmd --permanent --add-port=443/tcp
        run firewall-cmd --reload
        success "firewalld: 端口 443/tcp 已开放"
    elif command -v ufw &>/dev/null; then
        run ufw allow 443/tcp
        success "ufw: 端口 443/tcp 已开放"
    else
        warn "未检测到 firewalld/ufw，请手动开放安全组端口 443"
        warn "阿里云 ECS 还需在控制台「安全组」中放行 443 入方向"
    fi
}

open_firewall

# ── 验证并启动 Nginx ───────────────────────────────────────────────────────────
step "验证配置并启动 Nginx"

if $DRY_RUN; then
    info "[dry-run] nginx -t && systemctl enable --now nginx"
else
    nginx -t
    systemctl enable --now nginx
    systemctl reload nginx || systemctl restart nginx
    success "Nginx 启动/重载完成"
fi

# ── Docker Registry Mirror（可选）────────────────────────────────────────────
if $WITH_DOCKER_MIRROR; then
    step "部署 Docker Hub 镜像站（registry pull-through cache）"

    MIRROR_PORT=5000
    MIRROR_DATA="/data/docker-mirror"

    if ! command -v docker &>/dev/null; then
        warn "服务端未安装 Docker，正在安装..."
            case $OS in
                rhel)
                    run yum install -y yum-utils
                    # 阿里云 Linux 3 兼容 CentOS 8 仓库
                    DOCKER_REPO_URL="https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo"
                    run yum-config-manager --add-repo "$DOCKER_REPO_URL"
                    run yum install -y docker-ce docker-ce-cli containerd.io
                ;;
            debian)
                run apt-get install -y ca-certificates curl gnupg
                run install -m 0755 -d /etc/apt/keyrings
                run curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
                    -o /etc/apt/keyrings/docker.asc
                run chmod a+r /etc/apt/keyrings/docker.asc
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
                    https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
                    > /etc/apt/sources.list.d/docker.list
                run apt-get update -qq
                run apt-get install -y docker-ce docker-ce-cli containerd.io
                ;;
        esac
        run systemctl enable --now docker
    fi

    run mkdir -p "$MIRROR_DATA"

    # 写入 registry 配置
    if ! $DRY_RUN; then
        mkdir -p /etc/docker-mirror
        cat > /etc/docker-mirror/config.yml <<EOF
version: 0.1
log:
  level: warn
storage:
  filesystem:
    rootdirectory: /var/lib/registry
  delete:
    enabled: true
http:
  addr: :${MIRROR_PORT}
  headers:
    X-Content-Type-Options: [nosniff]
proxy:
  remoteurl: https://registry-1.docker.io
EOF
    fi

    # 启动 registry 容器
    run docker rm -f docker-mirror 2>/dev/null || true
    run docker run -d \
        --name docker-mirror \
        --restart always \
        -p "${MIRROR_PORT}:${MIRROR_PORT}" \
        -v "${MIRROR_DATA}:/var/lib/registry" \
        -v "/etc/docker-mirror/config.yml:/etc/docker/registry/config.yml" \
        registry:2

    success "Docker Hub 镜像站已启动，监听端口 ${MIRROR_PORT}"
    info "客户端配置（/etc/docker/daemon.json 追加）:"
    echo ""
    echo '  { "registry-mirrors": ["http://'"${SERVER_IP}"':'"${MIRROR_PORT}"'"] }'
    echo ""
fi

# ── 打印客户端配置指引 ────────────────────────────────────────────────────────
step "部署完成！客户端配置指引"

cat <<EOF

${BOLD}━━━ 服务端信息 ━━━${RESET}
  服务器 IP : ${SERVER_IP}
  监听端口  : 443 (SNI 透明代理)
  日志文件  : /var/log/nginx/sni_proxy.log

${BOLD}━━━ 国内客户端：修改 hosts 文件 ━━━${RESET}

  在 /etc/hosts（Linux/macOS）或
  C:\Windows\System32\drivers\etc\hosts（Windows）
  末尾追加以下内容（将 ${SERVER_IP} 替换为实际 IP）:

  # ── GitHub ──────────────────────────────────────────
  ${SERVER_IP}  github.com
  ${SERVER_IP}  www.github.com
  ${SERVER_IP}  api.github.com
  ${SERVER_IP}  gist.github.com
  ${SERVER_IP}  codeload.github.com
  ${SERVER_IP}  assets-cdn.github.com
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
  ${SERVER_IP}  github.githubassets.com
  # ── Docker Hub ───────────────────────────────────────
  ${SERVER_IP}  registry-1.docker.io
  ${SERVER_IP}  auth.docker.io
  ${SERVER_IP}  index.docker.io
  ${SERVER_IP}  production.cloudflare.docker.com

${BOLD}━━━ Docker 加速（推荐替代方案）━━━${RESET}

  编辑 /etc/docker/daemon.json 添加 registry-mirrors：
  {
    "registry-mirrors": ["https://mirror.gcr.io"]
  }

EOF

if $WITH_DOCKER_MIRROR; then
    echo -e "${BOLD}  或使用本机 Docker 镜像站：${RESET}"
    echo "  { \"registry-mirrors\": [\"http://${SERVER_IP}:${MIRROR_PORT}\"] }"
    echo ""
fi

echo -e "${GREEN}${BOLD}部署完成！${RESET} 使用 'tail -f /var/log/nginx/sni_proxy.log' 查看实时流量"
