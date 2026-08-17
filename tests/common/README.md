# tests/common

这里存放多个模块共享的 Bazel Shell 测试脚手架，不存放模块私有测试用例。

- `lib/run_unit_test.sh`：L1 Unit runner。
- `lib/run_module_test.sh`：L1 Integration runner（隔离 `HOME`、注入 fake）。
- `lib/run_e2e_test.sh`：L3 host runner；真跑 `setup.sh`。`DEVTOOLS_E2E_REQUIRE_DARWIN=1` 时仅 Darwin（GitHub `macos-26`）。
- `lib/profile.sh`：Ubuntu、ALinux 3/4、macOS 和内部 CentOS profile。
- `rules/devtools_tests.bzl`：`devtools_unit_test()`、`devtools_module_tests()`、`devtools_e2e_tests()`、`devtools_host_e2e_tests()`、`devtools_compose_e2e_tests()`。
- `docker/run_in_docker.sh`：L2 容器 runner；内部仍使用 fake。
- `docker/run_e2e_in_docker.sh`：L3 Linux 官方镜像 runner。
- `docker/run_compose_e2e.sh`：L3 Compose pair（特权 systemd，server/client）。
- `docker/ipv4.sh`：拉 Docker Hub 基础镜像时 IPv4 优先，避免 AAAA 黑洞。
- `docker/compose/vpn-pair.yml`：VPN exit（alinux3）+ client。
- `docker/compose/proxy-pair.yml`：proxy SNI（alinux3）+ client。
- `ci/select_layers.sh`：按 commit / PR 文案里的 `[test#…]` 选择 L1/L2/L3（`ut`/`it`/`e2e` 为别名，`skip` 全跳过）。
- `docker/Dockerfile.*`：L2 夹具。`linux_ubuntu` → `ubuntu:24.04`，`linux_centos` → `almalinux:9`，`linux_alinux3` / `linux_alinux4` → 杭州 ACR 官方 ALinux 镜像。macOS 无容器。
- `docker/Dockerfile.e2e.*`：E2E 夹具，同一套官方基础镜像，额外提供 sudo / 编译依赖 / nodejs。

测试分层、标签、兼容矩阵和真实 E2E 准入规则见 `tests/README.md`。
