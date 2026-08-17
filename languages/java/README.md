# Java 环境

通过 SDKMAN 安装 JDK 21、Maven 和 Gradle，并幂等更新 Shell 初始化配置。

~~~bash
bash languages/java/setup.sh --help
bash languages/java/setup.sh --dry-run
~~~

## Issues

### 2026-08-17 — `set -u` 下 source sdkman-init.sh 立刻失败

**表象**：`alinux3-devbox` 构建在 `java` 步骤退出：`sdkman-init.sh: line 20: SDKMAN_CANDIDATES_API: unbound variable`，或 `sdkman-install.sh: line 24: $3: unbound variable`。

**根因**：本仓库脚本启用 `set -u`。SDKMAN 的 init / install 脚本会读未设置的环境变量和可选位置参数。

**解法**：`source_sdkman_init` 与 `run_sdk` 在调用 SDKMAN 时暂时 `set +u`。`maven` / `gradle` 的 `latest` 改为不带版本号安装 SDKMAN 默认版（5.x 不再接受字面量 `latest`）。验证：

```bash
bash -n languages/java/setup.sh
bazel test //languages/java:java_unit_test
```
