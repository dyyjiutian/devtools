# DevTools 测试方案

本仓库是“脚本编排 + 配置资产 + 可选 Bazel 验证”的开发环境工具库。测试的首要目标是：在不修改真实主机的前提下，尽早发现脚本语法、参数契约、发行版分支、缓存回退和幂等性问题；只有 L3 才允许在可销毁环境里执行真实安装。

## 三层模型（L1 / L2 / L3）

| 层 | 环境 | 包管理器 | 证明什么 | 本地 | CI |
|---|---|---|---|---|---|
| **L1** | 宿主机 OS profile | fake `uname` / `apt` / `dnf` / `brew` | 分支、CLI、dry-run、幂等写入 | **默认回归** | `.github/workflows/ut.yml` |
| **L2** | Linux Docker（`Dockerfile.*`） | 仍是 fake | 同一套 suite 在 GNU/Linux 用户态 | 可选 | `.github/workflows/it.yml` |
| **L3** | Linux 官方镜像真装 + GitHub `macos-26` 真装 | 真 apt/dnf/brew | 装完后用户可观察结果 | 可选，勿当日常 | `.github/workflows/e2e.yml` |

L2 进了容器也不等于真装。macOS 没有 Linux Docker 等价物；macOS L3 只跑在 Darwin / GitHub `macos-26`。

修改代码后，**AI 与开发者默认只跑 L1**；涉及 GNU/BSD 或 Linux 用户态时加 L2；只有安装器真装路径或操作断言变化时才考虑 L3。

### 哪些模块必须到哪一层

| 模块 | 最低足够层 | 说明 |
|---|---|---|
| `tools/git`、`shell/bash`、`tools/ssh`、`agents/*` | L1；git/bash 另有 L2 | 契约与配置写入用 fake 即可 |
| `os/linux` | L1 + L2 | L2 抓 Linux 用户态；全量系统安装不进默认 L3 |
| `languages/go` `python` `java` `rust` | L1 + L2；真装看 L3 | L1/L2 测 CLI/dry-run；L3 测运行时真的出现 |
| `terminal/tmux`、`editors/vim`、`editors/nvim` | L3 才能证明操作 | L1/L2 测安装器契约；prefix / blame / telescope 必须真装 |
| `os/macos` setup CLI | L1（bats） | 全量 cask 不进矩阵 |
| VPN / proxy / FRP / remote-desktop | VPN 与 proxy 有 L3 Compose pair；FRP / remote-desktop 仍不进矩阵 | VPN：alinux3 exit + 多发行版 client。proxy：alinux3 SNI + 多发行版 client。均特权 systemd |

Python L3 使用 `--skip-pyenv --skip-ai-packages`，验证 `uv` 真装，不在 CI 里编译 CPython。

## 本地怎么跑

```bash
# L1（默认，无 Docker、无真装）—— 每次改脚本后应跑
bazel test //...
bazel test --config=l1 //...

# 只跑改动模块的 L1
bazel test //languages/go/... //tools/git/...
bash -n languages/go/setup.sh

# L2（需要本机 Docker daemon）
bazel test --config=l2 //...
bazel test --config=docker //tools/git/...   # docker 是 l2 的别名

# L3（真装，慢，会改容器或本机 brew 前缀）
bazel test --config=l3 --test_tag_filters=l3,-requires-macos //...   # Linux Docker E2E
bazel test --config=l3 --test_tag_filters=l3,requires-macos //...    # 仅 Darwin
bazel test --config=l3 //network/vpn:vpn_pair_linux_ubuntu_e2e_test    # VPN Compose pair
bazel test --config=l3 //network/proxy:proxy_pair_linux_alinux3_e2e_test  # proxy SNI pair
```

没有 `bazel` 时不要把“没跑”写成通过。不要为了验证语法而跑真实安装器。

## GitHub CI 与 commit 关键词

三条独立流水线：`UT`（`.github/workflows/ut.yml`）、`IT`（`it.yml`）、`E2E`（`e2e.yml`）。`E2E` 含 Ubuntu Docker job 与 `runs-on: macos-26` job。

在 **HEAD commit message 或 PR 标题/正文** 里写 `[test#…]` 选择器（大小写不敏感）：

| 写法 | 行为 |
|---|---|
| 不写 `[test#…]` | 三层都跑 |
| `[test#L1]` 或 `[test#ut]` | 只跑 L1 |
| `[test#L1,L2]` 或 `[test#ut,it]` | 只跑写出的层 |
| `[test#L3]` 或 `[test#e2e]` | 只跑 L3 |
| `[test#skip]` | 三层都不跑 |

别名：`ut` = L1，`it` = L2，`e2e` = L3。多个 tag 取并集；任一处出现 `skip` 则全跳过。正文里的裸 `L1` / `L2` / `L3` 不再当作选择器。

解析脚本：`tests/common/ci/select_layers.sh`。

## 设计原则

- **测试靠近被测模块**：模块私有用例放在模块目录内。
- **分层表示验证范围**：`l1` / `l2` / `l3` 是执行层；`unit` / `integration` / `e2e` 仍表示测试边界。
- **默认安全且快速**：普通 `bazel test //...` 不依赖 Docker，也不执行真实安装。
- **兼容性以真实目标为准**：profile fake 不能证明真实 OS 兼容；L3 才能回答“该系统上是否真的安装成功”。
- **幂等性是一等行为**：安装/配置类脚本至少验证 dry-run。

## 目录结构

```text
tests/
├── README.md
├── BUILD.bazel
├── repository_structure_test.sh
└── common/
    ├── lib/          # profile、断言、L1/L3 host runner
    ├── rules/        # Bazel 宏
    ├── profiles/
    ├── docker/       # L2 fake、L3 单容器 E2E、Compose pair（vpn-pair.yml / proxy-pair.yml）
    └── ci/           # GitHub 层选择

<module>/tests/
├── unit/
├── integration/      # L1，可选 L2
└── e2e/              # L3
```

## 标签

| tag | 含义 |
|---|---|
| `l1` / `l2` / `l3` | 执行层 |
| `unit` / `integration` / `e2e` | 测试边界 |
| `requires-docker` | 需要 Docker（L2 与 Linux L3） |
| `requires-macos` | 需要 Darwin（macOS L3 host E2E） |
| `compatibility` / `smoke` / `cli` / `contract` / `check` | 目的筛选 |

## 兼容性矩阵

| OS family | L1 profile | L2 Docker | L3 |
|---|---|---|---|
| macOS | `macos`（fake brew） | 无 | GitHub `macos-26` host E2E |
| Ubuntu | `linux_ubuntu` | `ubuntu:24.04` | 官方镜像真装 |
| ALinux 3 / 4 | `linux_alinux3` / `linux_alinux4` | 杭州 ACR 官方镜像 | 同上 |

基线仍是 x86_64 Linux。`macos-26` runner 当前是 arm64，**不能**代替 x86_64 macOS 结论。`linux_centos` 只作内部回归。

目标名：

```text
//<module>:<name>_<profile>_test          # L1
//<module>:<name>_<profile>_docker_test   # L2
//<module>:<name>_<profile>_e2e_test      # L3 Linux
//<module>:<name>_macos_e2e_test          # L3 macOS
```

## 新增测试

1. 先判断：纯解析放 unit（L1）；入口协作放 integration（L1，Linux 用户态敏感则加 `docker_profiles`）；真装才放 e2e（L3）。
2. 复用 `devtools_unit_test` / `devtools_module_tests` / `devtools_e2e_tests` / `devtools_host_e2e_tests` / `devtools_compose_e2e_tests`。
3. 禁止在 L1/L2 里 `sudo`、改真实 shell rc、或联网安装。

更详细的设计见 `docs/superpowers/specs/2026-08-17-l1-l2-l3-test-layers-design.md`。
