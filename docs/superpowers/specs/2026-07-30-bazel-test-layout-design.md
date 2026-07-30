# Bazel 测试目录与分层设计

## 目标

- 删除已废弃的 `tests/git_setup_test.sh` 兼容入口。
- 将 `tests/linux_setup_scripts_test.sh` 按模块职责和测试层级拆分。
- 让仍有价值的仓库约束与模块测试统一由 `bazel test` 触发。
- 将共享 Bazel/Shell 测试脚手架从 `testing/` 迁到 `tests/common/`。
- 建立适合脚本仓库的最小测试分层与兼容性矩阵，不为了分类完整而创建没有
  真实用例的目录。

## 决策摘要

- Unit 测试归属具体模块，只为复杂、可独立调用的函数建立。
- 模块 Integration 是本仓库的测试主体：在临时 HOME、fake PATH 和 OS profile
  下执行完整模块脚本。
- 根 `tests/` 只承载共享脚手架、仓库级约束和真正从根入口开始的 E2E；当前
  不创建跨模块 `tests/integration/`。
- API、contract、compatibility、smoke 是与测试层级正交的 Bazel tag，不建立
  同名目录。本仓库的公共 API 主要是 Shell CLI、配置格式和模块调用约定。
- 暂不建立 performance 测试；安装耗时主要由网络和包管理器决定，当前没有
  稳定、可执行的性能 SLO。
- 主要兼容基线为 macOS、Ubuntu、Alibaba Cloud Linux 3/4，仅覆盖 x86_64；
  arm 架构不在本期范围。
- E2E 必须运行在对应平台的真实 Docker 镜像、VM 或专用 runner 中，并使用原生
  系统工具；profile fake 不得标记为 E2E。
- `tests/common/` 只存放跨模块共享的测试能力，不存放具体模块用例。

## 方案 / 边界

目标布局：

```text
tests/
├── BUILD.bazel
├── README.md
├── repository_structure_test.sh
└── common/
    ├── BUILD.bazel
    ├── README.md
    ├── docker/
    ├── lib/
    ├── profiles/
    └── rules/

<module>/tests/
├── unit/
└── integration/
```

没有实际用例时不创建空的 `tests/e2e/`、模块 `unit/` 或 `integration/` 目录。

测试归属规则：

1. 单个函数或解析器行为归被测模块的 `tests/unit/`。
2. 完整模块脚本行为归该模块的 `tests/integration/`。
3. 模块调用其他模块时，由调用方 Integration 使用 fake/fixture 验证调用契约。
4. 只有无法指定单一所有者的真实多模块场景才进入根级 Integration；当前没有
   这种用例。
5. 从根 `setup.sh` 进入、经过真实子模块边界，并运行在真实目标 OS 中的场景
   才算 E2E；本期不以仅验证 dry-run 路由或 fake profile 的测试冒充完整 E2E。
6. 仓库结构、语法和格式约束使用 `check` tag，不属于 Unit/Integration/E2E。

测试层级 tag 每个功能测试只能选择一个：

```text
unit | integration | e2e
```

可叠加目的和执行属性：

```text
cli | contract | compatibility | smoke
requires-docker | requires-network | external | manual
```

兼容性 profile：

| Profile | 行为分支 | 默认执行 |
|---|---|---|
| `macos` | Darwin、Homebrew、Bash 3.2 兼容语法 | presubmit L1 |
| `linux_ubuntu` | Linux、APT | presubmit L1 |
| `linux_alinux3` | Linux、ALinux 3、dnf/yum | presubmit L1 |
| `linux_alinux4` | Linux、ALinux 4、新仓库结构、dnf/yum | presubmit L1 |

所有 profile 本期只验证 x86_64。架构相关函数显式固定为 x86_64；不生成 arm
target，也不把未执行的 arm 映射宣称为兼容覆盖。

L1 profile 测试不得访问真实网络或修改宿主 HOME。现有 Docker runner 仍会在
容器中注入 fake PATH，因此只算容器可移植性验证，不宣称为原生发行版兼容
E2E。

E2E 环境必须遵循：

| 平台 | E2E 环境 |
|---|---|
| Ubuntu | 对应版本的官方 x86_64 Docker 镜像或 VM |
| Alibaba Cloud Linux 3 | 官方 ALinux 3 x86_64 容器镜像或 ECS VM |
| Alibaba Cloud Linux 4 | 官方 ALinux 4 x86_64 镜像；无合适容器镜像时使用 ECS VM |
| macOS | 真实 x86_64 macOS VM 或专用 CI runner，不能使用 Docker 模拟 |

AlmaLinux、CentOS 或修改 `/etc/os-release` 的容器不能冒充 ALinux 3/4 E2E；
Linux 容器也不能冒充 macOS E2E。E2E 内不得调用 `setup_os_profile` 或将 fake
包管理器放入 PATH，必须观察原生 `uname`、`apt`、`dnf`、`yum` 或 `brew`。

E2E 应使用一次性环境，从根 `setup.sh` 调用真实子模块，验证用户可观察产物，
并至少再次执行一次验证幂等性。涉及镜像拉取、网络、Docker socket 或 VM 的
target 使用 `e2e`、`compatibility`、`external` 以及
`requires-docker`/`requires-vm` 标签，默认 presubmit 不执行，通过专用配置或
CI job 显式触发。

原 `linux_setup_scripts_test.sh` 覆盖映射：

| 原检查 | 新归属 / 层级 |
|---|---|
| Starship 缓存优先、fzf 中断恢复、Bash 插件 CLI | `shell/bash/tests/integration/` |
| CentOS/ALinux Docker repo 渲染 | `os/linux/tests/unit/` |
| Ubuntu dry-run/check/filter | `os/linux/tests/integration/` |
| ALinux 3/4 dry-run/check/filter | `os/linux/tests/integration/` |
| packages list 解析和映射 | `os/lib/tests/unit/` |
| NodeSource 缓存脚本、cache 下载逻辑 | `cache/tests/unit/` |
| macOS setup 语法与 packages list 约束 | `os/macos` 现有 Bazel 测试 |

仓库中确有少量跨模块依赖，但测试仍由调用方拥有：

- `os/linux` 调用 `terminal/tmux`：归 `os/linux` Integration。
- `cache/download.sh` 读取 `os/linux/packages.centos.list`：归 `cache`
  contract/Integration。
- Cursor Agent 调用 cookbook：归 Cursor Agent Integration。
- 根 `setup.sh` 编排各模块：未来由根 E2E 覆盖。

迁移时统一更新：

- 所有 `load("//testing/rules:...")`、`//testing:*` Bazel label。
- runner 与 Docker 脚本中的 `testing/...` marker。
- README、`BAZEL.md`、`AGENTS.md`、`CLAUDE.md` 和仍有效设计文档中的运行路径。

`repository_structure_test.sh` 检查真实 Git 工作区。Bazel target 使用脚本真实
路径解析源码根目录并标记为本地检查；其他模块测试必须声明完整 `data`，不得
依赖未声明文件。

## 测试要点

- 对所有新增或迁移 Shell 脚本执行 `bash -n`。
- `bazel test //tests:repository_structure_check` 可直接触发仓库约束。
- Unit target 使用 `unit` tag，保持无网络、无真实 HOME、small。
- 模块 suite 使用 `integration` tag；涉及 OS 分支时同时使用
  `compatibility` 和对应 profile tag。
- Bash、Git、tmux 等适用模块至少通过 `macos`、`linux_ubuntu`、
  `linux_alinux3`、`linux_alinux4` 中与自身分支相关的 target。
- ALinux 3 与 ALinux 4 必须是独立 target，分别提供 `ID=alinux`、
  `VERSION_ID=3/4` fixture。
- 兼容性场景至少覆盖全新 HOME、重复执行、已有正确状态、中断残留、有效缓存、
  损坏缓存和网络禁用中与模块有关的情况。
- 运行所有受迁移影响的 Bazel target，确认 `tests/common` 新 label 和 runner
  路径有效；Docker L2 若环境不可用则明确记录。
- 未来 E2E target 必须证明实际 OS 与声明平台一致，未注入 fake profile，并从
  根入口执行到真实子模块；仅执行模块 suite 的容器测试仍标记为 Integration。
- `git diff --check` 通过，仓库中不存在生效的 `//testing` 或 `testing/` 引用。

## 非目标

- 不主动重设计安装器的用户可见行为；测试隔离所需的可覆写系统信息来源，以及
  迁移验证直接暴露的幂等缺陷，可以做最小修复并补回归测试。
- 不支持或验证 arm/aarch64。
- 不宣称支持未列入基线的 Linux 发行版；已有 CentOS 特例可作为局部回归保留。
- 不新增根级跨模块 Integration 目录。
- 不新增 HTTP API、performance、security 或完整在线安装测试。
- 不把 profile 模拟、替代发行版镜像、模块 suite 容器运行或仅根路由 dry-run
  命名为真实 E2E。
- 不为了目录迁移重写整个测试框架或引入新的测试依赖。

## 实施中发现

- Bazel 全仓目标会递归扫描仓库内 `.worktrees/`，因此增加 `.bazelignore`，避免
  旧 worktree 中的 BUILD 文件污染当前工作树。
- Claude 插件幂等测试在并行矩阵中暴露了 `pipefail` 与 `grep -q` 的 SIGPIPE
  竞态；通过长列表用例稳定复现后，改为完整读取列表再匹配。
