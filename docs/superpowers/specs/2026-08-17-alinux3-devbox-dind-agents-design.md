# Alinux3 Devbox：DinD、Bazel、Yazi、Go/Java、Agents

## 目标

把 `alinux3-devbox` 扩成开箱可用的 AI coding 环境：特权 DinD（`docker run --privileged` 时入口拉起里层 `dockerd`）、Bazel、Yazi、Go/Java 全量模块，以及三个 Agent CLI 的安装与通用配置（不写 API key）。

## 决策摘要

- **DinD**：构建期用静态 el8 Docker CE 源（官方 + Aliyun companion，钉 `centos/8`）装 `docker-ce` / `cli` / `containerd` / `buildx` / `compose`，`admin` 进 `docker` 组。不跑 `systemctl`，不调用 `os/linux/setup_centos.sh`。
- **入口**：镜像默认 `USER root` + `ENTRYPOINT`。root 且具备特权时后台起 `dockerd`（unix socket，优先 `overlay2`，qemu/嵌套环境回退 `vfs`，cgroupfs），就绪后 `runuser` 到 `admin` 再执行 `CMD`（默认 `bash`）。无特权或非 root：警告后仍进 `admin` shell，不失败。
- **模块**：bootstrap 复用 `tools/bazel`、`terminal/yazi`、`languages/go`、`languages/java` 的 `setup.sh`。Yazi 二进制优先 `cache/` musl zip。
- **Agents**：`claude` / `codex` / `cursor-agent` 的 `install`（含插件）+ `sync`，再 `cookbook sync --copy --target all`。不写 `.profile-keys`，不跑 `switch` / `configure`。插件失败只告警，不让镜像构建失败。
- **边界**：DinD 逻辑只放在 `docker/alinux3/`；包源文件放 `os/lib/repos/`，与 EPEL 8 同模式。

## 方案 / 边界

### 构建

1. Dockerfile 作为 root：COPY `os/lib/repos/docker-ce-8.repo` 与 `docker-ce-8-aliyun.repo`，`dnf` 安装 Docker CE 与 `iptables`；`usermod -aG docker admin`。
2. COPY 新增模块目录：`tools/bazel`、`terminal/yazi`、`languages/go`、`languages/java`、`agents/{claude,codex,cursor-agent,cookbook}`。`.dockerignore` 为这些路径开例外（含 cookbook 的 `SKILL.md`）。
3. bootstrap（`admin`）顺序：现有 git/vim/nvim/tmux/bash 之后，装 yazi（cache 优先）→ bazel → go → java → 三个 agent `install`+`sync` → cookbook `--copy --target all`。
4. Java 构建期导出 `SDKMAN_AUTO_ANSWER=true`（及 SDKMan 非交互等价变量）。Go 用已有 sudo 装到 `/usr/local/go`。

### 运行

```text
docker run --privileged --rm -it alinux3-devbox:latest
```

入口脚本职责：探测 root、尝试 `dockerd`、等待 `docker info`、drop 到 `admin`、`exec` 用户命令。不暴露未加密的 TCP 2375。不挂宿主机 `docker.sock`，不做 rootless、不做 UID 同步。

### 不做的模块改动

不把 DinD 或 agent 逻辑塞进根 `setup.sh`。不改 Agent 的 key/switch 流程。Yazi/Bazel/Go/Java 安装器只在镜像侧调用，除非 cache 回退必须的最小修补。

## 测试要点

- **层级：** 契约 UT 足够覆盖构建合同与入口行为声明；特权 DinD 冒烟不进默认 Bazel。
- **方法：** 扩 `docker/alinux3/tests/unit/image_suite.sh`（及入口脚本 `bash -n` / `--help`）：断言 Dockerfile COPY/ENTRYPOINT、bootstrap 调用新模块、dockerignore 例外、无 `.profile-keys` / 无 `switch`。夹具为只读脚本，不用假 daemon。
- **环境：** 宿主机 `bash -n` + `bazel test //docker/alinux3:image_unit_test`。不跑真实 `dnf` / 模块安装。可选 `run-docker-tests.sh` 查 `command -v`；`DEVTOOLS_TEST_DIND=1` 时才 `--privileged` 测 `docker info`。
- **特别注意：** 脚本 Bash 3.2；入口无特权不得 `exit 1`；构建上下文不得带入密钥文件；Alinux 3 钉 el8，禁止 `$releasever`。
- **完成证据：** `bash -n` 通过新/改脚本；`git diff --check` 通过；`bazel test //docker/alinux3:image_unit_test` 通过（或明确记录 Bazel 不可用）。

## 非目标

- Python / Rust、Oh My Zsh、Cursor/VS Code 桌面、Yazi 以外的终端 GUI
- Dev Container、运行时 UID 同步、自动挂 `~/.ssh`
- 宿主机 socket 复用、rootless Docker、SSH target
- 写入 API key、git `user.name` / `user.email`
- 默认 CI 里跑特权容器或真实安装器
