# Linux 初始化

提供 Ubuntu/Debian、CentOS/RHEL 以及阿里云 ECS 的初始化脚本。

## 脚本

- `setup_ubuntu.sh`：Ubuntu/Debian 开发环境。
- `setup_centos.sh`：CentOS/RHEL 开发环境。
- `aliyun_ecs_init.sh`：阿里云 ECS 用户、磁盘、SSH 和 Swap 初始化。

## 两段流程

1. **OS 基础配置**：系统信息、权限检查、基础依赖（curl/wget/ca-certificates/build tools 等）。
2. **常见软件**：按清单安装 Docker、Git、Node、终端工具等。

| 脚本 | 清单 |
|------|------|
| `setup_ubuntu.sh` | [`packages.ubuntu.list`](packages.ubuntu.list) |
| `setup_centos.sh` | [`packages.centos.list`](packages.centos.list) |

清单格式（空白分隔五列，`#` 为注释）：

```text
# name            version     source       kind  tags
git               latest      apt          cli   dev
docker            latest      docker-ce    cli   ops,dev
yazi              0.3.3       github       tui   productivity
tmux              3.7b        module       tui   productivity,shell
```

- **kind**：`cli` / `tui` / `gui`
- **tags**：`productivity`（效率）、`diagnostic`（诊断）、`dev`（开发）、`ops`（运维）、`shell`（终端体验），可逗号组合

```bash
bash os/linux/setup_ubuntu.sh --help
bash os/linux/setup_ubuntu.sh --check
bash os/linux/setup_ubuntu.sh --check --kind tui
bash os/linux/setup_ubuntu.sh --check --tag diagnostic
bash os/linux/setup_ubuntu.sh --install bat
bash os/linux/setup_ubuntu.sh --tag productivity --packages-only --dry-run
bash os/linux/setup_centos.sh --check --kind cli --tag dev
bash os/linux/aliyun_ecs_init.sh --help
```

离线缓存版本（yazi/lazygit/glow/fzf 等）以 `packages.centos.list` 为准，由 `cache/download.sh linux` 读取。

## DNF 源（官方 + Aliyun）

`setup_centos.sh` 加第三方 DNF 源时保留官方地址，并在 Aliyun 有对应镜像时再写一份 companion：

- **Docker CE**：官方 `download.docker.com` 与 `docker-ce-aliyun.repo`（`mirrors.aliyun.com/docker-ce`）并存。Alinux 3 钉 `centos/8`（自身 `$releasever` 是 3，不能直接用）。Alinux 4 仍走云内网 `mirrors.cloud.aliyuncs.com`，并钉 `centos/9`。
- **NodeSource / GitHub CLI**：Aliyun 没有对应 RPM 镜像，只加官方源。
- **EPEL 8**：仅 Alinux 3 在 OS 基础阶段写入 `devtools-epel-8-aliyun.repo`（`mirrors.aliyun.com/epel/8/Everything`）。

## Issues

### 2026-08-16 — Alinux 3 加 Docker CE 时 `$releasever=3` 无效

**表象**：Alinux 3 的 `$releasever` 是 3，官方 / Aliyun Docker CE 都没有 `centos/3`。

**根因**：原先只给 Alinux 4 钉了 `centos/9`，Alinux 3 原样保留 `$releasever`。

**解法**：Alinux 3 钉 `centos/8`；官方 `docker-ce.repo` 与 Aliyun companion 一起写入。EPEL 同样钉 el8，不使用 `$releasever`。
