# L1 / L2 / L3 测试分层与 CI

## 目标

把现有 Unit / Integration / E2E 明确映射为三层执行模型，并让本地与 GitHub 用同一套标签筛选：

- **L1**：本机 OS profile + fake 命令（默认回归）
- **L2**：Linux Docker + 同一套 fake suite（可选，抓 GNU/BSD 与 Linux 用户态）
- **L3**：真实安装。Linux 用官方镜像 Docker E2E；macOS 用 GitHub `macos-26` 托管 runner 跑 host E2E

本地开发默认只跑 L1，需要时加 L2；L3 可选。GitHub 建三条流水线，commit / PR 文案里的 `L1` / `L2` / `L3` 可只跑对应层。

## 决策摘要

- Bazel tag：`l1` / `l2` / `l3`。默认 `bazel test //...` 排除 `l2`、`l3`、`requires-docker`、`requires-macos`。
- `--config=l2`（兼容 `--config=docker`）只跑 L2；`--config=l3` 跑 L3。
- Commit / PR 标题或正文出现 `\bL1\b` / `\bL2\b` / `\bL3\b` 时，只调度对应流水线；都没写则三条都跑。
- macOS L3：`runs-on: macos-26`（GitHub 当前 macOS 26 镜像），复用 `run_e2e_test.sh`，不经 Docker。
- 本轮补测：语言模块 L1（CLI / dry-run）+ L2（Linux fake）；L3 补 Go / Python / Java / Rust 真装，以及 tmux / vim / nvim 的 macOS host E2E。Python L3 跳过 pyenv 编译，验证 `uv` 真装。
- `os/linux` 补 L2。ssh / agents 只保留 L1。

## 方案 / 边界

| 层 | 环境 | 包管理器 | 证明什么 |
|---|---|---|---|
| L1 | 宿主机，`setup_os_profile` | fake | 分支、CLI、dry-run、幂等写入 |
| L2 | `Dockerfile.*` | 仍是 fake | 同一 suite 在 GNU/Linux 用户态 |
| L3 Linux | `Dockerfile.e2e.*` | 真 apt/dnf | 真装且用户可观察结果 |
| L3 macOS | GitHub `macos-26` | 真 brew | 同上，Darwin 不能用 Linux 容器代替 |

宏：

- `devtools_unit_test` / 主机 `devtools_module_tests` → `l1`
- `docker_profiles` → `l2`
- `devtools_e2e_tests` → `l3` + `requires-docker`
- 新增 `devtools_host_e2e_tests` → `l3` + `requires-macos`

CI：`.github/workflows/l1.yml`、`l2.yml`、`l3.yml`。`l3.yml` 含 Ubuntu Docker job 与 `macos-26` job。

## 测试要点

- **层级：** 改宏与 tag 后，用现有 git/tmux/bash 目标回归 L1；语言模块补新 L1 suite；L2/L3 以 `--help` / 映射单测和 dry-run 为主，不在本机真装。
- **方法：** `tests/common/ci/select_layers.sh` 解析关键词；语言 suite 断言 `--help`、未知参数、`--dry-run`；L3 ops 断言 `go version` / `uv --version` / `java -version` / `rustc --version`。
- **环境：** L1 无 Docker；L2/L3 Linux 需要 Docker；macOS L3 只在 Darwin / GitHub `macos-26`。默认禁止本机真实安装。
- **特别注意：** Bash 3.2；x86_64 Linux E2E 固定 `--platform linux/amd64`；`macos-26` 是 arm64，不宣称替代 x86_64 基线；Python L3 不编译 pyenv。
- **完成证据：** `bash -n` 新脚本；`bazel test //tests:repository_structure_check //tests/common:docker_runner_unit_test //tests/common:e2e_runner_unit_test //tests/common:select_layers_unit_test`；至少 `//languages/go:go_linux_ubuntu_test` 与默认 `bazel test //languages/...`（L1）。

## 非目标

- 不在 GitHub 上从 IPSW 自建多版本 macOS VM。
- 不把 `os/macos/setup.sh` 全量 cask / Docker Desktop 纳入 L3。
- FRP / remote-desktop 不纳入矩阵。VPN client↔exit 与 proxy SNI client↔server 用 L3 Compose pair（特权 systemd），不进默认 L1。
- 不把 Python pyenv 源码编译或 nvim `gd`/`gr` 纳入本轮 L3。
