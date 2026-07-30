# Bazel Build System for DevTools

本仓库使用 Bazel 9 与 bzlmod。自动化测试以 Shell `sh_test` 为主，测试分层、兼容矩阵和 E2E 准入标准见 `tests/README.md`。

## 快速开始

```bash
# macOS
brew install bazelisk

# 默认测试会排除 requires-docker
bazel test //...

# 常用分层
bazel test //... --test_tag_filters=unit
bazel test //... --test_tag_filters=integration
bazel test //... --test_tag_filters=smoke
```

## 公共测试设施

| 路径 | 职责 |
|---|---|
| `tests/common/lib/` | 断言、OS profile、Unit/Integration runner |
| `tests/common/rules/devtools_tests.bzl` | 生成 Unit 和 OS profile × module 测试 |
| `tests/common/profiles/` | Ubuntu、ALinux 3/4、macOS profile 元数据 |
| `tests/common/docker/` | 可选容器 Integration runner |
| `<module>/tests/unit/` | 模块单元测试 |
| `<module>/tests/integration/` | 模块集成测试 |

`devtools_module_tests` 默认生成无 Docker 的 L1 profile 目标。当前兼容基线是 macOS、Ubuntu、Alibaba Cloud Linux 3/4 的 x86_64；`linux_centos` 仅作为部分历史适配器的内部回归 profile。

示例：

- `//os/linux:linux_setup_linux_ubuntu_test`
- `//os/linux:linux_setup_linux_alinux3_test`
- `//os/linux:linux_setup_linux_alinux4_test`
- `//shell/bash:bash_macos_test`
- `//tools/git:git_linux_ubuntu_docker_test`（tag `requires-docker`）

## 常用目标

```bash
bazel test //tests:repository_structure_check
bazel test //os/lib:packages_list_unit_test
bazel test //os/linux/... //shell/bash/...
bazel test //tools/git/... //terminal/tmux/...
bazel test //os/macos:macos_setup_bats_test

# 可选容器 Integration，需要 Docker daemon
bazel test --config=docker //tools/git/... //terminal/tmux/...

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
