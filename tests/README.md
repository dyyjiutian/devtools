# DevTools 测试方案

本仓库是“脚本编排 + 配置资产 + 可选 Bazel 验证”的开发环境工具库。测试的首要目标是：在不修改真实主机的前提下，尽早发现脚本语法、参数契约、发行版分支、缓存回退和幂等性问题；只有真正的端到端测试才允许进入隔离的真实系统执行安装。

## 设计原则

- **测试靠近被测模块**：模块私有的单元测试和集成测试放在模块目录内，根目录 `tests/` 不收纳模块实现细节。
- **分层表示验证范围**：`unit`、`integration`、`e2e` 表示测试边界，不用 `api`、`contract`、`compatibility`、`smoke` 等维度替代分层。
- **标签表示测试目的**：契约、兼容性、冒烟和 CLI 验证通过 Bazel tag 组合筛选。
- **默认安全且快速**：普通 `bazel test //...` 不依赖 Docker，也不执行真实软件安装、系统服务或网络配置。
- **兼容性以真实目标为准**：profile fake 能验证分支选择和命令契约，但不能证明真实 OS 兼容；真实兼容结论必须来自对应镜像、VM 或原生 runner。
- **幂等性是一等行为**：安装/配置类脚本至少验证 dry-run；适合真实执行的 E2E 还应连续运行两次并检查没有重复配置或失败。

## 目录结构

```text
tests/
├── README.md                       # 整体测试策略与入口
├── BUILD.bazel                     # 仓库级检查
├── repository_structure_test.sh    # 目录、README 和废弃路径约束
└── common/                         # Bazel Shell 测试公共脚手架
    ├── lib/                        # profile、断言、测试 runner
    ├── rules/                      # devtools_unit_test / devtools_module_tests
    ├── profiles/                   # OS profile 元数据
    └── docker/                     # 可选的容器化 Integration runner

<module>/
├── BUILD.bazel
└── tests/
    ├── unit/                       # 纯函数、解析器、渲染器、静态契约
    ├── integration/                # 模块入口与其适配器的协作验证
    └── e2e/                        # 仅在确有真实环境场景时创建
```

根目录 `tests/` 只承担三类职责：

1. `tests/common/`：多个模块共享的测试基础设施。
2. 仓库级检查：目录边界、废弃路径、文档覆盖等约束。
3. 真正跨模块且从根入口发起的 E2E；当前模块相互独立，暂不创建虚假的跨模块 Integration 层。

## 测试分层

### Unit

验证不依赖真实 OS 状态的最小行为，例如：

- package list 解析与字段契约；
- 仓库配置模板渲染；
- 缓存下载路径、静态安装脚本语法；
- 参数映射和纯函数。

Unit 测试放在 `<module>/tests/unit/`，使用 `devtools_unit_test`，tag 为 `unit`。它们应快速、确定、无网络、无 Docker。

### Integration

验证一个模块入口脚本与本模块配置、缓存、命令适配器之间的协作，例如：

- `setup.sh --help`、`--check`、`--dry-run` 和筛选参数；
- 不同 OS profile 下选择 apt、dnf 或 brew；
- 缓存命中、缺失回退、失败重试；
- 使用 fake 命令和临时 `HOME` 验证配置写入。

Integration 测试放在 `<module>/tests/integration/`，使用 `devtools_module_tests` 生成 OS profile × module 的 Bazel 目标。profile 测试和当前 `tests/common/docker/` 容器 runner 即使运行在容器里，只要内部仍使用 fake 命令，也属于 Integration，不称为 E2E。

### E2E

E2E 从仓库根 `setup.sh` 或模块公开入口开始，在真实目标系统中调用原生包管理器并验证最终产物。最低要求是：

1. 使用目标 OS 的真实 Docker 镜像、VM 或原生 CI runner；
2. 不用 fake `apt`、`dnf`、`brew`、`uname` 伪造成功；
3. 执行真实模块安装路径；
4. 验证命令、配置文件或服务等用户可观察结果；
5. 第二次运行验证幂等性；
6. 测试环境可销毁，不污染开发机。

E2E 成本较高，按需放在 `<module>/tests/e2e/`；只有确实跨多个模块的用户旅程才放在根 `tests/e2e/`。当前仓库尚未把 profile/container Integration 冒充为 E2E。

## 横向测试标签

分层 tag 与目的 tag 可以组合：

| tag | 含义 | 典型内容 |
|---|---|---|
| `unit` | 单元层 | 解析、渲染、静态契约 |
| `integration` | 模块集成层 | 入口脚本、配置和 fake adapter 协作 |
| `e2e` | 真实端到端层 | 真实镜像/VM、真实包管理器、最终产物 |
| `contract` | 稳定接口约束 | CLI、清单格式、配置模板结构 |
| `compatibility` | OS/版本兼容维度 | macOS、Ubuntu、ALinux profile 或真实环境 |
| `smoke` | 小而关键的快速集合 | 语法、help、dry-run、关键分支 |
| `cli` | 命令行接口行为 | 参数、退出码、帮助文本 |
| `check` | 仓库静态约束 | 目录结构、README、废弃引用 |
| `requires-docker` | 需要 Docker daemon | 可选容器 Integration 或真实 Linux E2E |

`api` 测试只在仓库出现 HTTP/RPC API 后引入；当前 Shell CLI 使用 `cli` + `contract` 即可。性能测试也只在有明确性能预算、稳定负载和回归阈值时增加，不预建空目录。

## 兼容性矩阵

当前支持基线：

| OS family | 版本/方式 | 架构 | L1 profile | 真实 E2E 方式 |
|---|---|---|---|---|
| macOS | 当前受支持版本 | x86_64 | `macos` | macOS VM 或原生 CI runner |
| Ubuntu | 当前 LTS | x86_64 | `linux_ubuntu` | 官方 Ubuntu Docker 镜像或 VM |
| Alibaba Cloud Linux | 3 | x86_64 | `linux_alinux3` | ALinux 3 官方镜像或 VM |
| Alibaba Cloud Linux | 4 | x86_64 | `linux_alinux4` | ALinux 4 官方镜像或 VM |

暂不覆盖 ARM。`linux_centos` 只保留为部分底层适配器的内部回归 profile，不代表对外兼容性基线，也不能代替 ALinux 3/4。尤其 ALinux 4 的仓库结构和兼容策略必须独立验证。

profile 兼容测试负责快速回答“脚本是否走到正确分支、生成正确命令”；真实 E2E 才能回答“该系统上是否真的安装成功”。macOS 不能用 Linux 容器替代，ALinux 也不能用 AlmaLinux/CentOS 镜像代替后宣称兼容。

可选 L2 容器 Integration（`bazel test --config=docker`）在下列镜像里重跑同一套 suite，容器内仍注入 fake 命令：

| L2 profile | 基础镜像 | 本地 tag |
|---|---|---|
| `linux_ubuntu` | `ubuntu:24.04` | `devtools-test:ubuntu` |
| `linux_centos` | `almalinux:9` | `devtools-test:centos` |
| `linux_alinux3` | `alibaba-cloud-linux-3-registry.cn-hangzhou.cr.aliyuncs.com/alinux3/alinux3:latest` | `devtools-test:alinux3` |
| `linux_alinux4` | `alibaba-cloud-linux-4-registry.cn-hangzhou.cr.aliyuncs.com/alinux4/alinux4:latest` | `devtools-test:alinux4` |

当前声明了 `docker_profiles` 的模块是 `tools/git`、`terminal/tmux`、`editors/vim`（Ubuntu / AlmaLinux 9 / ALinux 3/4）、`editors/nvim` 和 `shell/bash`（Ubuntu / ALinux 3/4）。

可选 E2E（真装，无 fake）用同一套官方 Ubuntu / ALinux 镜像，目标名 `//<module>:<name>_<profile>_e2e_test`：

```bash
bazel test --config=docker //terminal/tmux:tmux_ops_linux_ubuntu_e2e_test
bazel test --config=docker //editors/vim:vim_ops_linux_ubuntu_e2e_test
bazel test --config=docker //editors/nvim:nvim_ops_linux_ubuntu_e2e_test
```

第一刀覆盖 tmux prefix/mouse/window/pane、vim/nvim 打开真实文件与 Git blame、nvim telescope 查找。`gd` / `gr` 尚未纳入。

## 常用命令

```bash
# 默认安全测试：.bazelrc 会排除 requires-docker
bazel test //...

# 分层或目的筛选
bazel test //... --test_tag_filters=unit
bazel test //... --test_tag_filters=integration
bazel test //... --test_tag_filters=contract
bazel test //... --test_tag_filters=compatibility
bazel test //... --test_tag_filters=smoke

# 本次迁移出的仓库与模块测试
bazel test //tests:repository_structure_check
bazel test //os/lib:packages_list_unit_test
bazel test //os/linux:...
bazel test //shell/bash:...
bazel test //cache:download_unit_test

# 可选容器 Integration，需要本机 Docker
bazel test --config=docker //tools/git/... //terminal/tmux/...
```

生成目标的命名约定：

```text
//<module>:<name>_<profile>_test
//<module>:<name>_<profile>_docker_test
```

例如：

- `//os/linux:linux_setup_linux_alinux3_test`
- `//shell/bash:bash_macos_test`
- `//tools/git:git_linux_ubuntu_test`

## 新增测试

1. 先判断边界：纯解析/渲染放 `unit`；一个模块内部的入口协作放 `integration`；真实系统安装才放 `e2e`。
2. 测试文件放在模块内，不把模块私有脚本堆回根 `tests/`。
3. 复用 `//tests/common/rules:devtools_tests.bzl`，并只声明实际需要的数据。
4. 安装器 Integration 优先覆盖 `macos`、`linux_ubuntu`、`linux_alinux3`、`linux_alinux4` 中适用的 profile。
5. 使用临时 `HOME`、fake 命令和本地缓存；禁止在普通测试里 `sudo`、修改真实 shell rc、服务、防火墙或联网安装。
6. 至少验证语法、帮助/参数契约、dry-run、关键成功路径和失败路径；配置写入还要验证重复运行。
7. 对只在真实环境才有意义的结论，明确留给 E2E，不扩大 profile 测试的保证范围。

## 当前落地范围

- 公共 Bazel 脚手架统一放在 `tests/common/`。
- 原根目录 Linux 回归内容已按职责拆到 `os/lib`、`os/linux`、`shell/bash` 和 `cache` 模块。
- Git 测试不再经过转发包装，直接由 `//tools/git:...` 触发。
- 根目录保留 `repository_structure_test.sh`，并由 Bazel 目标 `//tests:repository_structure_check` 统一运行。

更详细的设计取舍见
`docs/superpowers/specs/2026-07-30-bazel-test-layout-design.md`。
