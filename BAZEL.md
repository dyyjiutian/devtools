# Bazel Build System for DevTools

本仓库使用 Bazel 9 与 bzlmod。自动化测试以 Shell `sh_test` 为主，测试分层、兼容矩阵和 E2E 准入标准见 `tests/README.md`。

## 快速开始

```bash
# macOS
brew install bazelisk

# L1（默认）：本机 profile + fake，排除 Docker / 真装 / macOS host E2E
bazel test //...
bazel test --config=l1 //...

# L2：Docker + fake（需要 Docker daemon）
bazel test --config=l2 //...

# L3：真装（Linux Docker E2E 和/或本机 Darwin）
bazel test --config=l3 --test_tag_filters=l3,-requires-macos //...
bazel test --config=l3 --test_tag_filters=l3,requires-macos //...
```

## 公共测试设施

| 路径 | 职责 |
|---|---|
| `tests/common/lib/` | 断言、OS profile、L1 / L3 host runner |
| `tests/common/rules/devtools_tests.bzl` | 生成 L1 / L2 / L3 Bazel 目标 |
| `tests/common/profiles/` | Ubuntu、ALinux 3/4、macOS profile 元数据 |
| `tests/common/docker/` | L2 fake、L3 单容器 E2E、Compose pair |
| `tests/common/ci/` | GitHub 层选择（commit 关键词 L1/L2/L3） |
| `<module>/tests/unit/` | 模块单元测试 |
| `<module>/tests/integration/` | 模块集成测试 |

`devtools_module_tests` 默认生成无 Docker 的 L1 profile 目标。当前兼容基线是 macOS、Ubuntu、Alibaba Cloud Linux 3/4 的 x86_64；`linux_centos` 仅作为部分历史适配器的内部回归 profile。

L2 Docker 夹具（仍是 Integration，容器内使用 fake 命令）：`ubuntu:24.04`、`almalinux:9`，以及杭州 ACR 的官方 ALinux 3/4 镜像。

示例：

- `//os/linux:linux_setup_linux_ubuntu_test`
- `//os/linux:linux_setup_linux_alinux3_test`
- `//os/linux:linux_setup_linux_alinux4_test`
- `//shell/bash:bash_macos_test`
- `//tools/git:git_linux_ubuntu_docker_test`（tag `requires-docker`）
- `//tools/git:git_linux_alinux3_docker_test`（tag `requires-docker`）
- `//tools/git:git_linux_alinux4_docker_test`（tag `requires-docker`）
- `//shell/bash:bash_linux_ubuntu_docker_test`（tag `requires-docker`）
- `//terminal/tmux:tmux_ops_linux_ubuntu_e2e_test`（L3 Linux）
- `//terminal/tmux:tmux_ops_macos_e2e_test`（L3 macOS，GitHub `macos-26`）
- `//languages/go:go_linux_ubuntu_test`（L1）
- `//network/vpn:vpn_pair_linux_ubuntu_e2e_test`（L3 VPN Compose pair，特权 systemd）
- `//network/proxy:proxy_pair_linux_alinux3_e2e_test`（L3 proxy SNI Compose pair）

## 常用目标

```bash
bazel test //tests:repository_structure_check
bazel test //os/lib:packages_list_unit_test
bazel test //os/linux/... //shell/bash/...
bazel test //tools/git/... //terminal/tmux/...
bazel test //os/macos:macos_setup_bats_test

# L2 / L3
bazel test --config=l2 //tools/git/... //terminal/tmux/...
bazel test --config=l3 --test_tag_filters=l3,-requires-macos //languages/go/...
bazel test --config=l3 //network/vpn:vpn_pair_linux_ubuntu_e2e_test
bazel test --config=l3 //network/proxy:proxy_pair_linux_alinux3_e2e_test

bazel query 'tests(//...)'
```

## 关键文件

| 文件 | 用途 |
|---|---|
| `.bazelversion` | Bazel 版本 |
| `MODULE.bazel` | bzlmod 依赖 |
| `.bazelrc` | 测试输出和 Docker tag 过滤 |
| `tests/BUILD.bazel` | 仓库级检查 |
| `tests/common/BUILD.bazel` | 公共测试资产 |

`MODULE.bazel` 中的主要依赖包括 `rules_shell`、`platforms`、`bazel_skylib`、`rules_pkg`、`buildifier_prebuilt`，以及 macOS Bats 测试使用的 `bats_core`。

设计文档：

- `docs/superpowers/specs/2026-07-30-bazel-test-layout-design.md`
- `docs/superpowers/specs/2026-07-25-bazel-matrix-tests-design.md`
