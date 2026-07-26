# Bazel OS × 模块组合测试设计

## 目标

为 `devtools` 各模块的 `setup.sh` 建立可在 `bazel test` 下运行的组合测试矩阵：

`OS profile × 功能模块`

第一期覆盖 `tools/git` 与 `terminal/tmux`，并支持在 Linux 主机上验证 macOS 分支逻辑。

## 双层执行模型

### L1：主机 profile 模拟（默认）

- 通过 `testing/lib/profile.sh` 注入 fake `uname` / `brew` / `apt-get` / `dnf` 等。
- 使用隔离的临时 `HOME` 与 hermetic `PATH`（不泄漏宿主机 `gh`/`delta`）。
- 只跑安全路径：`--help`、`--dry-run`、幂等安装到临时 HOME、分支选择。
- 在 Linux 上可跑 `linux_ubuntu` / `linux_centos` / `macos`。

### L2：可选 Docker（Linux only）

- 镜像：`testing/docker/Dockerfile.ubuntu`、`Dockerfile.centos`（AlmaLinux 9）。
- 容器内执行与 L1 相同的 suite。
- Bazel tag：`requires-docker`；默认 `.bazelrc` 过滤掉该 tag。
- macOS 不做真容器。

## 目录

| 路径 | 职责 |
|---|---|
| `testing/lib/` | assert、profile、run_module_test |
| `testing/docker/` | Dockerfile 与 `run_in_docker.sh` |
| `testing/rules/devtools_tests.bzl` | 展开 profile×module → `sh_test` |
| `tools/git/tests/git_suite.sh` | git 用例 |
| `terminal/tmux/tests/tmux_suite.sh` | tmux 用例 |

## 宏接口

```starlark
devtools_module_tests(
    name = "git",
    suite = ":tests/git_suite.sh",
    module_root = ":setup.sh",
    module_data = [":git_srcs"],
    profiles = ["linux_ubuntu", "linux_centos", "macos"],
    docker_profiles = ["linux_ubuntu", "linux_centos"],
)
```

## 本地命令

```bash
# L1（默认）
bazel test //tools/git/... //terminal/tmux/...

# L2（需要 Docker）
bazel test --config=docker //tools/git/... //terminal/tmux/...
```

## 与旧 `tests/` 的关系

- `tests/git_setup_test.sh` 逻辑已迁入 `tools/git/tests/git_suite.sh`；旧脚本保留为薄包装。
- `tests/linux_setup_scripts_test.sh`、`repository_structure_test.sh` 暂不迁移。
