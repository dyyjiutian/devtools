# Bash L2 与编辑器/终端操作 E2E（第一刀）

## 目标

- 把 `shell/bash` 纳入现有 L2 Docker Integration（仍走 fake PATH，与 git/tmux 相同）。
- 为 `terminal/tmux`、`editors/vim`、`editors/nvim` 增加第一刀 **E2E**：在官方 Linux 镜像里真装模块后，验证用户可观察的常规操作。
- `gd` / `gr`（LSP）留到下一刀。

## 决策摘要

- bash 只加 `docker_profiles`，不改 suite 语义。
- 操作测试是新的 `e2e` 层：不调用 `setup_os_profile`，不注入 fake `apt`/`dnf`/`uname`。
- 基础镜像与 L2 相同（`ubuntu:24.04`、官方 ALinux 3/4）。E2E Dockerfile 额外装 `sudo`、编译依赖、`curl`、`nodejs`、`ripgrep`，以便 `setup.sh` 能真装。构建和运行固定 `--platform linux/amd64`，与仓库 x86_64 基线一致（避免 Apple Silicon 上 ALinux 3 误用需要新 glibc 的 arm64 Neovim）。
- 每个模块先跑该模块 `setup.sh`（tmux/vim 带 `--upgrade`；nvim 设 `NVIM_SETUP_STRICT=1`），再跑操作 suite。
- 默认 `bazel test //...` 仍排除 `requires-docker`。用 `--config=docker` 显式跑。
- 不把 `alinux3-devbox` 拉进 Bazel 矩阵。不测 macOS E2E。

## 方案 / 边界

L2（bash）：

- `shell/bash` 增加 `linux_ubuntu` / `linux_alinux3` / `linux_alinux4` 的 `docker_profiles`。
- 继续使用 `run_in_docker.sh` + 现有 `bash_suite.sh`。

E2E 入口：

- `tests/common/lib/run_e2e_test.sh`：隔离 `HOME`，保留真实 `PATH`，先执行 `setup.sh`，再 `source` 操作 suite。
- `tests/common/docker/run_e2e_in_docker.sh`：按 profile 选 E2E Dockerfile，容器内调用上面的 runner。
- `devtools_e2e_tests()` 生成 `//<module>:<name>_<profile>_e2e_test`，tag 为 `e2e`、`requires-docker`、`requires-network`、`no-sandbox`、`local`。

第一刀操作断言：

| 模块 | 真装后检查 |
|---|---|
| tmux | `prefix=C-Space`、`mouse on`；`new-window` / `split-window` 后 window/pane 数量；`list-keys` 含 copy-mode-vi 的 `v`/`y`。不测真实鼠标拖选用。 |
| vim | 打开仓库内真实 `.sh`；`:Git blame` 在临时 git 仓库产生 fugitive blame 缓冲。不测 `gd`/`gr`。 |
| nvim | 打开真实文件；`:Git blame`；`telescope.builtin.grep_string` / current_buffer_fuzzy_find 对已知标记无报错且能看到结果。不测 `gd`/`gr`。 |

E2E 只用 `linux_ubuntu`、`linux_alinux3`、`linux_alinux4`。

## 测试要点

- **层级：** bash 用现有 Integration suite 做 L2 回归。操作测试是新的 E2E 场景用例，另补 runner 映射单测（不启 Docker）。
- **方法：** `tests/common/tests/unit/e2e_runner_suite.sh` 断言 profile→Dockerfile、且 runner 不调用 `setup_os_profile`。模块 `tests/e2e/*_ops_suite.sh` 在真装后的临时 `HOME` 里跑 tmux/vim/nvim 命令。夹具：临时 git 仓库、带唯一标记的真实脚本文件。
- **环境：** 官方 Docker 镜像；允许真实 `apt`/`dnf`、编译、拉插件；需要网络。禁止改宿主机 `HOME`。默认 presubmit 不跑。
- **特别注意：** 镜像内 `sudo` 必须可用（vim/nvim 安装器写死 `sudo`）。ALinux 仍改写云内网 yum 源。nvim Lazy sync 慢且依赖 GitHub，target size 用 `enormous`。Bash 3.2 语法。不宣称 x86_64 以外的兼容。
- **完成证据：** `bash -n` 新脚本；`//tests/common:docker_runner_unit_test` 与 `//tests/common:e2e_runner_unit_test`；`//shell/bash:bash_linux_ubuntu_docker_test`（及 ALinux 若本机 Docker 可用）；至少一条 tmux/vim/nvim E2E 在 `--config=docker` 下跑通或如实记录失败原因。

## 非目标

- 不实现 `gd` / `gr` / Mason LSP attach。
- 不测真实鼠标拖选用，不用 `alinux3-devbox`，不做 macOS 容器 E2E。
- 不把 E2E 标成 L2，不在默认 `bazel test //...` 里跑 E2E。
- 不改安装器的用户可见行为（除非 E2E 暴露必须修的阻塞缺陷）。
