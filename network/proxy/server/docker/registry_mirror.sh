#!/usr/bin/env bash
# =============================================================================
# Docker Hub 镜像站部署脚本（pull-through cache）
# 独立使用：sudo ./registry_mirror.sh
# 也可通过 ../setup.sh --with-docker-mirror 调用
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
step()    { echo -e "\n${BOLD}==> $*${RESET}"; }

MIRROR_PORT="${MIRROR_PORT:-5000}"
MIRROR_DATA="${MIRROR_DATA:-/data/docker-mirror}"
CONFIG_DIR="/etc/docker-mirror"
CONTAINER_NAME="docker-mirror"

if [[ $EUID -ne 0 ]]; then
    error "请以 root 权限运行: sudo $0"
    exit 1
fi

if ! command -v docker &>/dev/null; then
    error "未安装 Docker，请先运行 ../../os/linux/setup_centos.sh 或安装 Docker"
    exit 1
fi

step "创建 Registry 配置"

mkdir -p "$CONFIG_DIR" "$MIRROR_DATA"

cat > "${CONFIG_DIR}/config.yml" <<EOF
version: 0.1
log:
  level: warn
  formatter: text
storage:
  filesystem:
    rootdirectory: /var/lib/registry
  cache:
    blobdescriptor: inmemory
  maintenance:
    uploadpurging:
      enabled: true
      age: 168h
      interval: 24h
      dryrun: false
  delete:
    enabled: true
http:
  addr: :${MIRROR_PORT}
  headers:
    X-Content-Type-Options: [nosniff]
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
proxy:
  remoteurl: https://registry-1.docker.io
EOF

success "Registry 配置写入: ${CONFIG_DIR}/config.yml"

step "启动 Docker Hub 镜像容器"

docker rm -f "$CONTAINER_NAME" 2>/dev/null && info "已停止旧容器" || true

docker run -d \
    --name "$CONTAINER_NAME" \
    --restart always \
    -p "127.0.0.1:${MIRROR_PORT}:${MIRROR_PORT}" \
    -v "${MIRROR_DATA}:/var/lib/registry" \
    -v "${CONFIG_DIR}/config.yml:/etc/docker/registry/config.yml:ro" \
    registry:2

success "Docker Hub 镜像站启动完成（端口 ${MIRROR_PORT}）"

# 检查容器状态
sleep 2
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    success "容器运行正常"
else
    error "容器启动失败，请检查: docker logs ${CONTAINER_NAME}"
    exit 1
fi

# 获取服务器公网 IP
SERVER_IP=$(curl -sf --connect-timeout 5 https://api4.ipify.org || hostname -I | awk '{print $1}')

step "配置说明"

cat <<EOF

${BOLD}━━━ Docker Hub 镜像站信息 ━━━${RESET}
  容器名称 : ${CONTAINER_NAME}
  监听地址 : 127.0.0.1:${MIRROR_PORT}（本机）
  数据目录 : ${MIRROR_DATA}
  上游来源 : registry-1.docker.io

${BOLD}  注意：容器仅监听本机 127.0.0.1，需通过 Nginx 反代对外暴露${RESET}

${BOLD}━━━ 需要在 Nginx 中添加反向代理（HTTPS） ━━━${RESET}

  建议在 /etc/nginx/conf.d/docker-mirror.conf 添加:

  server {
      listen 443 ssl;
      server_name mirror.your-domain.com;

      ssl_certificate     /path/to/cert.pem;
      ssl_certificate_key /path/to/key.pem;

      location / {
          proxy_pass http://127.0.0.1:${MIRROR_PORT};
          proxy_set_header Host \$host;
          proxy_read_timeout 900;
          proxy_connect_timeout 30;
      }
  }

${BOLD}━━━ 客户端配置（/etc/docker/daemon.json）━━━${RESET}

  {
    "registry-mirrors": ["https://mirror.your-domain.com"]
  }

  配置后重启 Docker:
    sudo systemctl daemon-reload && sudo systemctl restart docker

${BOLD}━━━ 管理命令 ━━━${RESET}
  查看日志: docker logs -f ${CONTAINER_NAME}
  停止镜像: docker stop ${CONTAINER_NAME}
  清理缓存: docker exec ${CONTAINER_NAME} registry garbage-collect /etc/docker/registry/config.yml
  查看大小: du -sh ${MIRROR_DATA}

EOF
