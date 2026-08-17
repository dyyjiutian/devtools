# 海外加速代理站点

基于新加坡 ECS 搭建的透明代理，让国内机器无需任何代理软件，仅通过修改 `hosts` 文件即可稳定访问 GitHub、Docker Hub 等海外站点。

## 工作原理

```
国内用户                          新加坡 ECS                      目标站点
   │                                   │                              │
   │  hosts: github.com → ECS_IP       │                              │
   │                                   │                              │
   ├──── HTTPS (TLS SNI: github.com) ──►│                              │
   │                                   │── 读取 SNI ──────────────────►│
   │                                   │   转发 TCP 流                 │
   │                                   │◄─────────────── GitHub 证书 ──│
   │◄──── GitHub 真实 SSL 证书 ─────────│                              │
```

**SNI 透明代理**：Nginx 读取 HTTPS 握手中的 SNI（服务器名称指示），将 TCP 流原样转发给真实目标服务器，无需 SSL 证书，客户端收到的是 GitHub/Docker 的真实证书。

## 目录结构

```
proxy/
├── server/
│   ├── setup.sh                  # 服务端一键部署脚本
│   ├── nginx/
│   │   └── sni_proxy.conf        # Nginx stream SNI 代理配置（参考）
│   └── docker/
│       └── registry_mirror.sh    # Docker Hub 镜像站（可选）
├── client/
│   ├── configure.sh              # 客户端自动配置脚本
│   ├── hosts.txt                 # hosts 条目模板
│   └── docker/
│       └── daemon.json           # Docker daemon 配置模板
└── README.md
```

## L3 Compose pair（可选）

用两台特权 systemd 容器验证 **SNI 服务端 ↔ 客户端 hosts**。server 固定 ALinux 3，client 为 Ubuntu / ALinux 3 / ALinux 4。成功标准：client 把 `github.com` 指到 server，并能经 443 SNI 访问本机 `e2e.devtools.test` 源站。

```bash
bazel test --config=l3 //network/proxy:proxy_pair_linux_ubuntu_e2e_test
bazel test --config=l3 //network/proxy:proxy_pair_linux_alinux3_e2e_test
bazel test --config=l3 //network/proxy:proxy_pair_linux_alinux4_e2e_test
```

需要本机 Docker 与 `docker compose`。容器以 `/sbin/init` 为 PID 1，并加 `privileged` + `cgroup: host`。默认 `bazel test //...` 不会跑这一层。

## 快速部署

### 第一步：服务端（新加坡 ECS）

```bash
# 基础部署（SNI 代理，适用 GitHub + Docker Hub hosts 方案）
sudo ./server/setup.sh

# 同时部署 Docker Hub 镜像站（pull-through cache，推荐）
sudo ./server/setup.sh --with-docker-mirror

# 预览不执行
sudo ./server/setup.sh --dry-run
```

**阿里云 ECS 控制台**：安全组入方向放行 `TCP 443`（SNI 代理必须）。

### 第二步：客户端（国内机器）

#### 方案 A：自动配置（推荐）

```bash
# Linux / macOS
sudo ./client/configure.sh <ECS_IP>

# 恢复（删除 hosts 条目）
sudo ./client/configure.sh <ECS_IP> --clean
```

#### 方案 B：手动修改 hosts

编辑 `/etc/hosts`（Linux/macOS）或 `C:\Windows\System32\drivers\etc\hosts`（Windows），追加以下内容：

```
# 将 ECS_IP 替换为实际 IP
ECS_IP  github.com
ECS_IP  www.github.com
ECS_IP  api.github.com
ECS_IP  gist.github.com
ECS_IP  codeload.github.com
ECS_IP  raw.githubusercontent.com
ECS_IP  gist.githubusercontent.com
ECS_IP  cloud.githubusercontent.com
ECS_IP  camo.githubusercontent.com
ECS_IP  avatars.githubusercontent.com
ECS_IP  avatars0.githubusercontent.com
ECS_IP  avatars1.githubusercontent.com
ECS_IP  avatars2.githubusercontent.com
ECS_IP  avatars3.githubusercontent.com
ECS_IP  user-images.githubusercontent.com
ECS_IP  objects.githubusercontent.com
ECS_IP  github-releases.githubusercontent.com
ECS_IP  media.githubusercontent.com
ECS_IP  github.githubassets.com
ECS_IP  registry-1.docker.io
ECS_IP  auth.docker.io
ECS_IP  index.docker.io
ECS_IP  production.cloudflare.docker.com
```

也可直接使用 `client/hosts.txt` 模板，替换 `SERVER_IP` 后追加。

#### Docker Hub 加速（推荐额外配置）

编辑 `/etc/docker/daemon.json`：

```json
{
  "registry-mirrors": ["https://mirror.gcr.io"]
}
```

如果部署了 Docker registry mirror，使用自己的镜像站：

```json
{
  "registry-mirrors": ["http://ECS_IP:5000"]
}
```

重启 Docker 生效：

```bash
sudo systemctl daemon-reload && sudo systemctl restart docker
```

## 验证

```bash
# 验证 GitHub 访问
curl -I https://github.com

# 验证原始文件下载
curl -I https://raw.githubusercontent.com/torvalds/linux/master/README

# 验证 Docker pull
docker pull hello-world
```

## 服务管理

```bash
# 查看代理实时日志
sudo tail -f /var/log/nginx/sni_proxy.log

# 重载 Nginx 配置（修改域名白名单后）
sudo nginx -t && sudo systemctl reload nginx

# Docker 镜像站管理
docker logs -f docker-mirror         # 查看日志
docker exec docker-mirror registry garbage-collect \
    /etc/docker/registry/config.yml  # 清理过期层
du -sh /data/docker-mirror           # 查看缓存大小
```

## 扩展更多域名

编辑 `/etc/nginx/stream.d/sni_proxy.conf`，在 `map` 块中添加：

```nginx
# 示例：添加 npm registry
~^(.+\.)?npmjs\.com$    $ssl_preread_server_name:443;
# 示例：添加 PyPI
~^(.+\.)?pypi\.org$     $ssl_preread_server_name:443;
```

然后 `sudo nginx -t && sudo systemctl reload nginx`，并在客户端 `hosts` 中对应添加。

## 安全说明

- SNI 代理通过**白名单**限制转发域名，未匹配域名直接断开连接，不会成为开放代理
- 建议在 ECS 安全组限制 443 端口来源 IP（仅允许自己公司/家庭 IP 段）
- Docker registry mirror 仅监听 `127.0.0.1`，通过 Nginx 反代对外暴露时建议配置认证

## Issues

2026-08-17 — 容器 / Ubuntu 24 上 configure.sh 刷新 DNS 失败

**表象**：`systemd-resolve --flush-caches` 在 Ubuntu 24 或无 resolved 的容器里非 0 退出，`set -e` 中断配置。

**根因**：命令已改名为 `resolvectl`，且 flush 失败不应阻断 hosts 写入。

**解法**：`systemd-resolve` / `resolvectl` 失败后继续。Compose pair：`bazel test --config=l3 //network/proxy:proxy_pair_linux_alinux3_e2e_test`。
