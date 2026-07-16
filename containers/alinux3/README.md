# Alibaba Cloud Linux 3 开发镜像

该目录提供基于 Alibaba Cloud Linux 3 的通用开发镜像，包含 bash、zsh、Starship、Vim、Neovim、Git 工具以及三个 Agent CLI。

## 构建

```bash
docker buildx bake alinux3-minimal --load
docker buildx bake alinux3-full --load
docker buildx bake alinux3-ssh --load
```

如果本机只有 Docker CLI 而没有 Buildx，可直接构建 full 目标：

```bash
docker build \
  --file containers/alinux3/Dockerfile \
  --target full \
  --tag devtools-alinux3:full-dev \
  .
```

默认镜像使用阿里云杭州地域的 Alibaba Cloud Linux 3 官方容器镜像。可通过 `BASE_IMAGE` 覆盖：

```bash
docker buildx bake alinux3-full \
  --set '*.args.BASE_IMAGE=alibaba-cloud-linux-3-registry.cn-hangzhou.cr.aliyuncs.com/alinux3/alinux3:latest' \
  --load
```

## 运行

推荐使用仓库包装器，让容器内的 `admin` UID/GID 与宿主机一致：

```bash
scripts/devtools-container-run devtools-alinux3:full-dev
scripts/devtools-container-run --user developer --uid 1001 --gid 1001 IMAGE
```

包装器会以 root 启动入口脚本，由入口脚本同步 `admin`，然后再以非 root 用户执行 zsh 或指定命令。

也可以直接运行：

```bash
docker run --rm -it \
  --user root \
  -e DEV_UID="$(id -u)" \
  -e DEV_GID="$(id -g)" \
  -v "$PWD:/workspace" \
  IMAGE
```

不要将 `docker run --user admin` 当作动态 UID/GID 同步方式；该写法会让入口脚本直接以镜像内置 UID 启动。

## Dev Container

项目中的 `.devcontainer/devcontainer.json` 使用 `admin` 作为远程用户，并允许 Dev Container 在创建或重建时同步 UID/GID。

## SSH

构建 SSH 变体后：

```bash
scripts/devtools-container-run --ssh IMAGE
ssh -p 2222 admin@127.0.0.1
```

SSH 公钥应通过 `/home/admin/.ssh/authorized_keys` volume 或 bind mount 提供。镜像默认禁止 root SSH 登录和密码登录。

## 凭据

镜像不包含任何 API Key 或登录状态。建议持久化或挂载：

```text
/home/admin/.claude
/home/admin/.codex
/home/admin/.cursor
/home/admin/.ssh
```
