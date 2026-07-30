# tests/common

这里存放多个模块共享的 Bazel Shell 测试脚手架，不存放模块私有测试用例。

- `lib/run_unit_test.sh`：无 OS profile 的 Unit runner。
- `lib/run_module_test.sh`：隔离 `HOME`、注入 fake 命令的 Integration runner。
- `lib/profile.sh`：Ubuntu、ALinux 3/4、macOS 和内部 CentOS profile。
- `rules/devtools_tests.bzl`：`devtools_unit_test()` 与 `devtools_module_tests()` 宏。
- `docker/run_in_docker.sh`：可选容器 Integration runner；内部仍使用 fake 命令，因此不是 E2E。

测试分层、标签、兼容矩阵和真实 E2E 准入规则见 `tests/README.md`。
