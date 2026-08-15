# Alibaba Cloud Linux 3 开发镜像设计

## 当前范围（2026-08-15）

先只交付 `devbox` target（linux/amd64，镜像 `alinux3-devbox:<YYYYMMDD-HHMM>`）：构建期复用 `tools/git`、`editors/vim`、`editors/nvim`、`terminal/tmux`、`shell/bash` 的 `setup.sh`，并带上 `rg` / `jq` / `bat` / `tree`，得到开箱可用的 Alinux 3 / OS 8 开发镜像。默认用户 `admin`，工作目录 `/home/admin`。Dev Container、`full` / `ssh` target、运行时 UID 同步和自动注入宿主机 `~/.ssh` 已从实现中拿掉，留到后续阶段。Bake 定义在 `containers/alinux3/docker-bake.hcl`。

下文是最初的完整目标，其中过时的路径（`terminal/vim`、`vcs/git`、`agent/`）以当前仓库目录为准。

## 目标

在本仓库中新增一个基于 Alibaba Cloud Linux 3 的通用开发镜像，开箱提供 bash、zsh、Starship、Vim、Neovim、Git 工具以及 Claude Code、Codex CLI、Cursor Agent CLI，并同时支持 Dev Container、普通 `docker run` 和 SSH 场景。

## 已确认决策

- 基础镜像使用 Alibaba Cloud Linux 3 官方容器镜像。
- 镜像预置 `root` 和 `admin`；`admin` 默认 UID/GID 为 1000。
- Dockerfile 默认保持 root 作为入口用户，由 root entrypoint 在启动时根据 `DEV_UID` / `DEV_GID` 调整 `admin`。
- 直接 `docker run --user admin` 不负责动态 UID/GID 同步；推荐使用 root entrypoint 或仓库包装命令。
- `/workspace` bind mount 不由容器默认 `chown`，避免意外修改宿主机文件所有权。
- API Key、OAuth 状态、SSH 私钥和 Git 身份不写入镜像。
- Dev Container 使用 `remoteUser: admin` 和 `updateRemoteUserUID: true`；普通 Docker/SSH 使用运行时用户同步。

## 组件边界

`containers/alinux3/` 负责镜像构建、入口初始化、SSH 配置和容器测试；现有 `terminal/`、`vcs/git/` 和 `agent/` 目录继续作为配置源。构建阶段只执行非交互安装和静态配置复制；运行阶段负责用户 UID/GID 同步、Home 初始化和凭据挂载。

## 用户同步

启动时的目标用户默认为 `admin`。入口脚本按以下优先级取得 UID/GID：显式 `DEV_UID` / `DEV_GID`、宿主机侧包装器传入值、`/workspace` 属主作为兜底、镜像默认 1000:1000。目标 UID/GID 被其他系统用户占用时不修改无关用户，入口脚本失败并给出可操作提示。

用户 Home 可安全修正；`/workspace` 不默认修正所有权。用户配置使用带标记的托管块合并，保留用户自定义内容。

## 构建与运行

`docker-bake.hcl` 提供 `alinux3-minimal`、`alinux3-full` 和 `alinux3-ssh` targets。`.devcontainer/devcontainer.json` 使用 `full` target。`scripts/devtools-container-run` 自动传递当前宿主机 UID/GID，并保证入口脚本以 root 运行后再切换到 `admin`。

SSH 模式只运行 `sshd -D -e`，不启动 systemd 或 Docker daemon；SSH host keys 在运行时生成。

## 验证标准

- shell 脚本通过 `bash -n`。
- 镜像可构建并包含三个 Agent CLI、bash、zsh、vim、nvim、git 和 starship。
- 以非 1000 UID/GID 运行时，`whoami` 为 `admin`，`id` 显示目标 UID/GID。
- 写入 `/workspace` 的新文件在宿主机侧属于对应 UID/GID。
- 用户配置初始化可重复执行且不覆盖托管块之外的自定义内容。
- SSH target 可启动 sshd，默认禁止 root 远程登录。
