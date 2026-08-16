# tests/common

这里存放多个模块共享的 Bazel Shell 测试脚手架，不存放模块私有测试用例。

- `lib/run_unit_test.sh`：无 OS profile 的 Unit runner。
- `lib/run_module_test.sh`：隔离 `HOME`、注入 fake 命令的 Integration runner。
- `lib/run_e2e_test.sh`：隔离 `HOME`，真跑模块 `setup.sh` 再跑操作 suite；不注入 fake。
- `lib/profile.sh`：Ubuntu、ALinux 3/4、macOS 和内部 CentOS profile。
- `rules/devtools_tests.bzl`：`devtools_unit_test()`、`devtools_module_tests()` 与 `devtools_e2e_tests()` 宏。
- `docker/run_in_docker.sh`：可选容器 Integration runner；内部仍使用 fake 命令，因此不是 E2E。
- `docker/run_e2e_in_docker.sh`：官方镜像 E2E runner；真装后测常规操作。
- `docker/Dockerfile.*`：L2 夹具。`linux_ubuntu` → `ubuntu:24.04`，`linux_centos` → `almalinux:9`，`linux_alinux3` / `linux_alinux4` → 杭州 ACR 官方 ALinux 镜像。macOS 无容器。
- `docker/Dockerfile.e2e.*`：E2E 夹具，同一套官方基础镜像，额外提供 sudo / 编译依赖 / nodejs。

测试分层、标签、兼容矩阵和真实 E2E 准入规则见 `tests/README.md`。
