# 测试

跨模块 Shell 回归测试与 Bazel 矩阵测试入口说明。

## Bazel OS × 模块矩阵（推荐）

第一期已覆盖 `tools/git` 与 `terminal/tmux`，在 Linux 主机上可测
`linux_ubuntu` / `linux_centos` / `macos`（macos 为 profile 模拟）。

```bash
# L1：主机 profile 模拟（默认，不需要 Docker）
bazel test //tools/git/... //terminal/tmux/...

# 仅 macOS profile
bazel test //tools/git:git_macos_test //terminal/tmux:tmux_macos_test

# L2：可选 Linux 容器（需要本机 Docker）
bazel test --config=docker //tools/git/... //terminal/tmux/...
```

设计说明见 `docs/superpowers/specs/2026-07-25-bazel-matrix-tests-design.md`。

## 旧版 bash 脚本

- `repository_structure_test.sh`：路径引用和功能模块 README 覆盖检查。
- `git_setup_test.sh`：薄包装，转发到 Bazel / `tools/git/tests/git_suite.sh`。
- `linux_setup_scripts_test.sh`：Linux 缓存、仓库和重试逻辑回归测试（尚未迁入 Bazel）。

```bash
bash tests/repository_structure_test.sh
bash tests/git_setup_test.sh
bash tests/linux_setup_scripts_test.sh
```
