# nvim 对标 VSCode / IDEA 的能力补齐

## 目标

在 `editors/nvim` 现有配置上补齐三块 IDE 核心能力：断点调试、测试运行、保存时格式化与
lint，并补上导航类短板（结构大纲、粘性上下文、全局搜索替换、内置终端）。所有插件必须在
Linux 侧固定的 **Neovim 0.10.4** 上可用，同时不牺牲 macOS 上较新 Neovim 的体验。

调试与测试本轮只覆盖 **Python 和 Go**；Java 保持现有 LSP 能力不变。

## 决策摘要

| 决策 | 结论 | 理由 |
|---|---|---|
| Java 调试/测试 | 本轮不做 | 需 `nvim-jdtls` 接管 jdtls 并引入 debug/test bundle，改动量约等于 Python + Go 之和 |
| 0.11+ 插件适配 | 条件 pin：低版本走兼容分支/tag，高版本跟随上游 | 与 `lazygit.nvim` 既有做法一致；避免 macOS 被永久冻结在旧版 |
| 调试适配器安装 | 不引入 `mason-nvim-dap.nvim` | 它依赖 `mason-core` 内部 API，与已 pin 的 mason v1 耦合脆弱；`mason-tool-installer` 直接装 `debugpy` / `delve` 即可，语言插件自己配置适配器 |
| Go 测试适配器 | `neotest-golang` | `neotest-go` 已近一年未更新 |
| 格式化时机 | 保存时自动格式化 + 手动快捷键 | 对齐 VSCode format on save |
| Python 格式化器 | 由 black/isort 改为 `ruff` | 一个二进制同时提供 lint 与 format，减少 mason 安装项 |

各插件在 0.10.4 上的落点（已逐个核对上游版本门禁）：

| 插件 | 0.10.4 上的取法 | 依据 |
|---|---|---|
| `conform.nvim` | 默认分支 | README 要求 0.10+ |
| `nvim-lint` | 默认分支 | README 要求 0.9.5+ |
| `nvim-dap` / `nvim-dap-ui` | 默认分支 | 源码内对 0.11/0.12 均为运行时分支判断，低版本回退 `termopen` |
| `neotest` | 默认分支 | 同上；watch 功能要求 0.10.1，已满足 |
| `toggleterm.nvim`、`nvim-treesitter-context` | 默认分支 | 无版本门禁；context 依赖 treesitter master，已 pin |
| `aerial.nvim` | 三段式：≥0.12 用 master，≥0.11 用 `nvim-0.11`，否则 `nvim-0.9` | master 的 `setup()` 在 <0.12 时直接报错返回 |
| `grug-far.nvim` | <0.11 用 tag `1.6.6`，否则默认分支 | `plugin/grug-far.lua` 首行硬门禁 0.11；`1.6.6` 是门禁引入前最后一个 tag，其自身门禁为 0.10 |

## 方案 / 边界

**新增插件规格文件**，每个插件一个文件，延续 `lua/plugins/*.lua` 现有风格：

- `format.lua`：conform.nvim，`BufWritePre` 自动格式化 + `<leader>cf` 手动触发 + `:FormatToggle` 开关
- `lint.lua`：nvim-lint，`BufWritePost` / `InsertLeave` 触发
- `dap.lua`：nvim-dap + nvim-dap-ui + nvim-nio + nvim-dap-virtual-text，含 `nvim-dap-python`、`nvim-dap-go`
- `neotest.lua`：neotest + neotest-python + neotest-golang
- `aerial.lua`、`treesitter-context.lua`、`grug-far.lua`、`toggleterm.lua`

**改动已有文件**：

- `completion.lua`：补 `cmp-buffer`、`cmp-cmdline` 两个来源
- `lsp.lua`：`mason-tool-installer` 的 `ensure_installed` 增加 `debugpy`、`delve`、`ruff`、`shellcheck`
- `config/keymaps.lua`：删除 `<leader>d`（delete without yanking）——它已经与 `<leader>ds`
  形成前缀遮蔽，且要给 Debug 组让位；该行为用内置 `"_d` 即可
- `which-key.lua`：新增 `<leader>d` = Debug、`<leader>t` = Test 两个组名
- `setup.sh`：`_reset_pinned_plugins` 增加本轮条件 pin 的 `aerial.nvim`、`grug-far.nvim`
- `README.md`：键位表、插件列表、Issues 记录

**键位分配**（避开现有 `b c d e f g h n p q r s t w x D` 的占用情况）：

| 功能 | 键位 |
|---|---|
| 调试主循环 | `<F5>` 继续 / `<F9>` 断点 / `<F10>` 单步跳过 / `<F11>` 步入 / `<S-F11>` 步出（与 VSCode 一致） |
| 调试其余 | `<leader>d` 组：`db` 断点、`dB` 条件断点、`dc` 继续、`du` UI 开关、`dt` 终止、`dr` REPL |
| 测试 | `<leader>t` 组：`tt` 当前用例、`tf` 当前文件、`ts` 概览、`to` 输出、`tl` 上次 |
| 格式化 | `<leader>cf` |
| 大纲 | `<leader>o` |
| 搜索替换 | `<leader>sr` |
| 终端 | `<C-\>` |

`<leader>ds`（LSP document symbols）保留原位，与 Debug 组共存；which-key 组名标注为
`[D]ebug / [D]ocument`。

**边界**：不改 LSP 服务器清单与 mason/lspconfig 的既有 pin；不引入 AI 补全；不做 Java
调试测试；不改 `os/` 与 `cache/` 下的安装流程（新插件由 lazy.nvim 在 `--update` 时拉取，
不进 `cache/`，因为它们是 git 仓库而非二进制）。

## 测试要点

**层级**：以结构断言为主（沿用 `editors/nvim/tests/nvim_suite.sh` 的既有风格），
加一条 `setup.sh` 行为测试，外加一次一次性的本机真实冒烟。

**方法**：

- 结构断言：条件 pin 的写法正确（`aerial` 三段式、`grug-far` tag `1.6.6`、均使用显式
  `if` 而非 `cond and nil or x` 这一 Lua 陷阱）；mason 工具清单含 `debugpy`/`delve`/`ruff`/`shellcheck`；
  conform 绑定 `BufWritePre`；`neotest-go` 未被误用；`mason-nvim-dap` 未被引入
- 键位唯一性：把现有 `test_leader_keys_are_unique` 扩成对全部一级 leader 键做重复检测，
  并断言 `<leader>d` 的 delete 映射已移除、Debug/Test 组名已登记
- `setup.sh` 行为：沿用假 `nvim` + 沙盒 `HOME` 的既有夹具，断言 `_reset_pinned_plugins`
  覆盖新增的条件 pin 插件，且 `--update` 仍幂等
- 真实冒烟（一次性，本机手动）：用 `cache/binaries/nvim-linux-x86_64-v0.10.4.tar.gz`
  解到临时前缀，配合独立的 `XDG_CONFIG_HOME` / `XDG_DATA_HOME`，跑
  `nvim --headless -c "Lazy! sync" -c "qa!"`，再 headless `require()` 各新插件，
  确认无加载错误、无 0.11 API 报错

**环境**：bazel 测试全部离线、无副作用，覆盖 `linux_ubuntu` / `linux_alinux3` /
`linux_alinux4` / `macos` 四个 profile。冒烟需要网络（拉插件仓库）与临时目录，
不进 bazel、不写入真实 `~/.config/nvim`，跑完即删。

**特别注意**：Bash 3.2 兼容与 `set -euo pipefail`；bazel 沙盒里 `lua/` 是符号链接，
测试中递归 grep 必须用 `-R` 并规避 `pipefail`（已有踩坑记录）；配置同步保持幂等。

**完成证据**：`bash -n`、Lua `loadfile` 语法检查、`bazel test //editors/nvim/...` 四
profile 全过、新增断言在改动回退后确实失败（非空测试）、以及冒烟脚本输出无错误。

## 非目标

- Java 的调试与测试（含 `nvim-jdtls` 重构）
- TypeScript / Rust / C++ 的调试与测试适配器
- AI 补全（Copilot / Codeium）
- 数据库客户端、HTTP client、Markdown 预览等 IDE 周边
- 把新插件纳入 `cache/` 离线安装
