# Alibaba Cloud Linux 3 开发镜像

基于 Alibaba Cloud Linux 3（RHEL 8 系）的 x86_64 开发镜像。构建时调用仓库里现有的模块安装器，开箱提供：

- Git：`git`、`lazygit`、`delta`、`git rb/bc/wc/review/sparse-clone`，以及推荐 git 配置（**不**写入 `user.name` / `user.email`）
- Vim / Neovim：`editors/vim/setup.sh --upgrade`（Alinux 3 自带 Vim 8.0，升级到 9.2 后才装得了 coc / `gd` `gr`）与 `editors/nvim/setup.sh`（Linux Neovim 固定 0.10.4；构建期同步安装 `bashls` 等常用 LSP）
- tmux 3.7b 与本仓库 `tmux.conf` / TPM 插件
- Bash：ble.sh、fzf、zoxide、Starship（`shell/bash/setup.sh`）
- 常见 CLI：`jq`、`tree`、`rg`、`bat`、`yazi`（与 `os/linux/packages.centos.list` 对齐；`cloc` 有包则装）
- Docker CE + 特权 DinD：构建期安装 `docker-ce` / `cli` / `containerd` / `buildx` / `compose`，`admin` 在 `docker` 组。`docker run --privileged` 时入口拉起里层 `dockerd`
- Bazel（bazelisk / buildifier / starpls）、Go 1.23 + 工具链、Java 21（SDKMan + Maven / Gradle）
- Agent CLI：Claude Code、Codex、Cursor Agent（含通用配置 / 插件 / cookbook skills；**不**写入 API key）
- DNF：Alinux 自带源改写到 `mirrors.aliyun.com`，并加入 Aliyun EPEL 8 与 Docker CE el8（官方 + Aliyun companion）

当前只提供 `devbox` target，镜像名为 `alinux3-devbox:<YYYYMMDD-HHMM>`。Dev Container、运行时 UID 同步、自动挂载宿主机 `~/.ssh` 尚未实现。

## 构建

需要 Docker，并建议使用 Buildx。默认锁定 `linux/amd64`：

推荐用包装脚本，把本机 `127.0.0.1` 代理改写成构建容器能访问的 `host.docker.internal`，并把 Alinux dnf 源切到公网 `mirrors.aliyun.com`（国内源直连，GitHub 走代理）：

```bash
bash docker/alinux3/bake.sh
```

也可以直接 bake（定义在本目录 `docker-bake.hcl`）。`bake` 是 Buildx 插件的能力，不绑定某个 docker-ce 小版本；Linux 上要有 `docker-buildx-plugin`（或 Docker Desktop）。Buildx 0.8+ 即可读这份 HCL。若本机开了代理，需要显式改成 Docker 主机地址：

```bash
docker buildx bake -f docker/alinux3/docker-bake.hcl devbox --load \
  --set '*.args.HTTP_PROXY=http://host.docker.internal:8001' \
  --set '*.args.HTTPS_PROXY=http://host.docker.internal:8001'
```

没有 Buildx 时可使用：

```bash
docker build --platform linux/amd64 \
  --file docker/alinux3/Dockerfile \
  --tag alinux3-devbox:$(date +%Y%m%d-%H%M) \
  --tag alinux3-devbox:latest \
  .
```

默认基础镜像是阿里云杭州地域的 Alibaba Cloud Linux 3 官方容器镜像，可用 `BASE_IMAGE` 覆盖。

构建会联网下载 Neovim、ble.sh、fzf、插件和 TPM 依赖，耗时较长。二进制优先使用仓库 `cache/binaries/`（可先跑 `bash cache/download.sh linux`）。

## 运行

镜像以 root 入口启动，就绪后 drop 到 `admin`（UID 1000），工作目录 `/home/admin`。里层 Docker 需要特权：

```bash
docker run --privileged --rm -it alinux3-devbox:latest
```

不加 `--privileged` 仍能进 `admin` shell，但会提示 dockerd 不可用。里层 `dockerd` 优先 `overlay2`；在 Apple Silicon 的 qemu `linux/amd64` 上会回退 `vfs`。进入后可直接使用 `git`、`lazygit`、`vim`、`nvim`、`tmux`、`rg`、`jq`、`bat`、`tree`、`yazi`、`docker`、`bazel`、`go`、`java`，以及 `claude` / `codex` / `agent`（需自行 `login` 或挂入 key）。Bash 已配置 ble / fzf / zoxide / starship。Neovim 插件、treesitter parser 和常用 LSP（含 `bashls`）已在构建期装好。需要把当前目录挂进去时：

```bash
docker run --privileged --rm -it -v "$PWD:/workspace" -w /workspace alinux3-devbox:latest
```

Git 身份请在容器内自行设置，或把宿主机 `~/.gitconfig` 挂进去（下一阶段会处理 `~/.ssh` 与权限）：

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

## 验证

宿主机契约测试（不需要 Docker）：

```bash
bash -n docker/alinux3/bootstrap.sh
bazel test //docker/alinux3:image_unit_test
```

已构建镜像后的冒烟测试：

```bash
DEVTOOLS_TEST_IMAGE=alinux3-devbox:latest \
  bash docker/alinux3/tests/run-docker-tests.sh
```

## Issues

### 2026-08-17 — 镜像里 `bash -lc` 找不到 go / java

**表象**：`command -v go` / `java` 在 `docker run ... bash -lc` 下失败，二进制其实已装在 `/usr/local/go` 和 `~/.sdkman/candidates`。

**根因**：`tools/bazel/setup.sh` 会创建 `~/.zshrc`。Go / Java 安装器只往第一个存在的 rc 写，结果 PATH 只在 zshrc。镜像默认 bash。

**解法**：Dockerfile 把 Go 与 SDKMAN `current/bin` 写进 `ENV PATH`。Go / Java 安装器同时写入 `~/.bashrc` 和已有的 `~/.zshrc`。

### 2026-08-17 — 构建期 Java/SDKMAN 在 `set -u` 下失败

**表象**：bootstrap 跑到 `java` 后：`sdkman-init.sh: line 20: SDKMAN_CANDIDATES_API: unbound variable`，或 `sdkman-install.sh: line 24: $3: unbound variable`。

**根因**：镜像 bootstrap 与 `languages/java/setup.sh` 都开了 `set -u`，SDKMAN 脚本会读未设置的变量和可选 `$3`。

**解法**：`languages/java/setup.sh` 用 `source_sdkman_init` / `run_sdk` 在调用 SDKMAN 时暂时 `set +u`；`maven` / `gradle` 不再把字面量 `latest` 传给 `sdk install`。

### 2026-08-17 — bake 在 nvim Lazy sync 时被 1MiB 日志上限掐断

**表象**：构建跑到 `Installing plugins` 后退出码 1，日志停在某个插件的 `clone` 进度，没有 `failed to solve`。

**根因**：lazy.nvim 的 git 进度刷满 BuildKit 默认约 1MiB 的步进日志。

**解法**：构建期加 `NVIM_SETUP_QUIET=1`，headless sync 不再把进度打到 stdout。

### 2026-08-17 — Apple Silicon 上特权 DinD 的 overlay2 起不来

**表象**：`docker run --privileged --platform linux/amd64 alinux3-devbox:latest` 后 `docker info` 连不上里层 daemon。日志里是 `failed to mount overlay: invalid argument` / `driver not supported: overlay2`。

**根因**：镜像锁定 `linux/amd64`，在 arm64 Docker Desktop 上走 qemu。嵌套容器里 overlayfs 经常不可用，官方 `overlay2` 图驱动会立刻退出。

**解法**：入口先试 `overlay2`，失败则清掉 `/var/lib/docker` 再回退 `vfs`。真机 Linux/amd64 仍走 overlay2。验证：

```bash
docker run --privileged --rm --platform linux/amd64 alinux3-devbox:latest \
  bash -lc 'docker info'
```

### 2026-08-16 — 镜像里 vim / nvim 打开 setup.sh 时 gd/gr 没反应

**表象**：`alinux3-devbox` 里 `vim setup.sh` / `nvim setup.sh` 按 `gd`、`gr` 完全没反应。

**根因**：两者都依赖 Shell LSP。系统 Vim 是 8.0.1763，低于 coc.nvim 的 8.1.1719，bootstrap 又没加 `--upgrade`，coc 和 `gd`/`gr` 映射整段被跳过。nvim 的 `MasonToolsInstallSync` 只等 `mason-tool-installer`；`bashls` 写在 `mason-lspconfig` 的异步 `ensure_installed` 里，headless `qa!` 时还没下完就退出，打开 `.sh` 时没有 client attach，`LspAttach` 里的 `gd`/`gr` 也就不会绑定。

**解法**：bootstrap 改为 `editors/vim/setup.sh --upgrade`。把 `bashls` / `lua_ls` / `pyright` / `jsonls` / `yamlls` / `ts_ls` 放进 `mason-tool-installer`，`NVIM_SETUP_STRICT=1` 时校验 mason 包目录。`gopls` / `clangd` 仍只在 `mason-lspconfig` 里按需装。重新构建：

```bash
bash docker/alinux3/bake.sh
```

### 2026-08-15 — 镜像 COPY 路径与仓库重组脱节，且误钉 Neovim 0.11

**表象**：按旧 Dockerfile 构建会在复制已搬迁的 Vim / Git / Agent 配置时失败；即便改路径，Alinux 3 上也跑不了官方 Neovim 0.11 tarball。

**根因**：这些配置已分别迁到 `editors`、`tools/git`、`shell`、`agents`；Alinux 3 的 glibc 是 2.32，Neovim 0.11+ 官方包需要 2.34+。

**解法**：`alinux3-mini` 改为 COPY 当前模块目录，并在构建期以 `admin` 用户跑各模块 `setup.sh`。Neovim 继续走 `editors/nvim/setup.sh` 的 0.10.4 tarball。

### 2026-08-15 — 构建期 dnf 走云内网源，且 groupadd 不在 PATH

**表象**：`dnf install` 对 `mirrors.cloud.aliyuncs.com` 超时或只有几百 KB/s；装完包后 `groupadd: command not found`。

**根因**：官方 Alinux 3 容器镜像的 yum 源指向云上内网镜像，本机 Docker 构建（即使开了 `127.0.0.1` 代理）也到不了。另外 Dockerfile 的 `PATH` 漏了 `/usr/sbin`。宿主机代理里的 `127.0.0.1` 在 build 容器里也不是 Docker 宿主机。

**解法**：构建时把源改写成 `mirrors.aliyun.com`；`PATH` 补上 `/usr/sbin`；用 `docker/alinux3/bake.sh` 把 `127.0.0.1` 代理改写成 `host.docker.internal`，国内阿里云域名放进 `NO_PROXY`。

### 2026-08-15 — docker run 后 ble.sh 报 USER 为空，starship 写不了 ~/.cache

**表象**：`docker run -it IMAGE /bin/bash` 出现 `ble.sh: insane environment: $USER is empty`，以及 `Unable to create log dir "/home/admin/.cache/starship": Permission denied`。Apple Silicon 上还会有 amd64/arm64 platform warning。

**根因**：非 login 的 `/bin/bash` 不会自动设置 `USER`。构建时 `ENV HOME=/home/admin` 让 root 的 `dnf` 在用户创建前写下了 `/home/admin/.cache`，属主是 root。platform warning 是因为镜像锁定 `linux/amd64`，在 arm64 Mac 上走 qemu。

**解法**：镜像写入 `ENV USER=admin LOGNAME=admin`；bootstrap 结束后 `chown -R admin:admin /home/admin`。platform warning 可忽略，或显式加 `--platform linux/amd64`。

### 2026-08-15 — 打开 nvim 文件时触发全量插件安装

**表象**：镜像里 `nvim file` 会跑一遍 lazy.nvim 全量 clone（约 50 个插件），启动很慢。

**根因**：`ENV HOME=/home/admin` 让 root 在用户创建前占用 `~/.cache`，`admin` 跑 nvim 时无法写 `~/.cache/nvim`，lazy.setup 失败；同步失败原先只告警。

**解法**：useradd 之后立刻 `chown -R admin:admin /home/admin`；bootstrap 以 `NVIM_SETUP_STRICT=1` 跑 `Lazy! sync` 并校验插件目录；`sudo env` 透传 `HTTP(S)_PROXY`。重新构建：

```bash
bash docker/alinux3/bake.sh
```

### 2026-08-15 — 默认工作目录、常用 CLI 与镜像命名

**表象**：`docker run` 落在 `/workspace`；缺少 `rg` / `jq` / `bat` / `tree`；bake target 仍叫 `alinux3-mini`。

**根因**：早期 mini 镜像把工作区固定成 `/workspace`，系统包只覆盖构建依赖。

**解法**：`WORKDIR /home/admin`；dnf 安装 `jq`/`tree`（`cloc`/`ripgrep`/`bat` 有包则装），bootstrap 再从 cache/GitHub 补 `bat`/`rg`；bake target 改为 `devbox`，标签 `alinux3-devbox:<YYYYMMDD-HHMM>` 与 `alinux3-devbox:latest`。

### 2026-08-16 — 第三方 DNF 源缺少 Aliyun companion，且 EPEL 未带上

**表象**：构建或在 Alinux 3 上加 Docker CE / 额外包时，只有官方源；`$releasever=3` 对不上 Docker CE / EPEL 的 el8 树。

**根因**：Dockerfile 只改写了 Alinux 自带源；`setup_centos.sh` 给 Alinux 3 保留了 `$releasever`。Aliyun 有 Docker CE 与 EPEL 8，但没有 GitHub CLI / NodeSource RPM。

**解法**：镜像 COPY `os/lib/repos/epel-8-aliyun.repo`。`setup_centos.sh` 保留官方 Docker CE，并写 `docker-ce-aliyun.repo`；Alinux 3 钉 `centos/8`，基础阶段加 EPEL 8。gh / NodeSource 仍走官方源。
