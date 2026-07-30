# shell/bash setup 插件 CLI 设计

## 目标

调整 `shell/bash/setup.sh`，在保留现有完整安装能力的前提下，支持子命令式调用：完整安装、安装指定插件、列举插件及本机安装状态。安装与 `.bashrc` 配置保持幂等。

## 决策摘要

| 项 | 选择 |
|---|---|
| CLI 形态 | 子命令式（无子命令默认 `install`） |
| 单插件时 `.bashrc` | 始终写入完整配置块（未装插件用存在性判断，不报错） |
| `list` 输出 | 名称 + 说明 + `[installed]` / `[missing]` |
| dry-run 短选项 | `-n, --dry-run`（不再使用 `-d`） |
| 实现形态 | 单文件内插件注册表 + 子命令分派（不拆 `lib/`） |
| Starship 配置文件 | 仅完整安装，或本次 `install` 包含 `starship` 时写入 |

## 命令接口

```bash
./setup.sh                      # 等价 install（完整安装）
./setup.sh install              # 完整安装全部插件
./setup.sh install fzf          # 只装指定插件
./setup.sh install fzf zoxide   # 可一次指定多个
./setup.sh list                 # 列举插件 + 本机状态
./setup.sh -h | --help
./setup.sh -n | --dry-run       # 可与 install 组合，位置不限
./setup.sh install -n
./setup.sh install fzf --dry-run
```

### 插件 ID

| ID | 别名 | 说明 |
|---|---|---|
| `blesh` | `ble.sh` | 命令历史自动建议 + 实时语法高亮 |
| `zoxide` | — | 智能目录跳转 |
| `fzf` | — | 模糊搜索（历史/文件/目录） |
| `starship` | — | 跨 shell 提示符 |

未知插件名：非零退出，提示运行 `list`。

### `list` 示例输出

```text
blesh     命令历史自动建议 + 实时语法高亮   [installed]
zoxide    智能目录跳转                     [missing]
fzf       模糊搜索                         [installed]
starship  跨 shell 提示符                  [missing]
```

安装状态检测与安装函数中的「已安装则跳过」条件一致。

## 行为

### `install`（无插件参数）

1. 按平台安装全部插件（macOS: Homebrew；Linux: 现有 git/curl/cache 路径）。
2. 幂等写入完整 `~/.bashrc` 配置块（marker 替换）。
3. 写入 Starship tokyo 配置到 `~/.config/starship.toml`（已存在则先备份）。
4. 打印后续操作与快捷键提示。

### `install <plugins...>`

1. 仅调用指定插件的安装函数。
2. 仍写入**完整** `.bashrc` 配置块（与完整安装相同内容）。
3. 仅当本次参数包含 `starship` 时执行 `configure_starship_config`。
4. 打印与本次相关的简要后续提示。

### `list`

只读：不改系统、不改配置。输出四插件行与状态。

### dry-run

与现有一致：打印将执行的操作，不实际安装、不改 `.bashrc` / `starship.toml`。

### 兼容与解析

- 全局选项：`-h` / `--help`、`-n` / `--dry-run`，可出现在子命令前或后。
- 无子命令且无未知参数 → 默认 `install`。
- 保留 macOS / Linux 分支与 cache 回退逻辑；本设计不改变各插件的安装实现细节，只改变入口编排。

## 内部结构

在 `setup.sh` 内增加：

1. **插件注册表**：ID → 说明、安装函数名、状态检测函数。
2. **参数解析**：先收集全局选项与子命令，再分派。
3. **分派**：
   - `cmd_install`：解析插件列表（空 = 全部）→ 安装 → 配置 bashrc → 按需配置 starship。
   - `cmd_list`：遍历注册表打印状态。
4. 现有 `_install_linux_*` / `install_macos` 拆成可按插件调用的入口（macOS 可按 brew 包名逐个安装；Linux 复用现有单插件函数）。

## 测试与文档

- 更新 `shell/bash/README.md`：子命令用法、`list`、单插件安装、`-n`。
- 扩展 `tests/linux_setup_scripts_test.sh`（或新增同目录回归）：
  - `list` 输出含四个插件 ID 与状态标记
  - `install fzf`（dry-run 或 fake PATH）不触发其它插件安装路径
  - 未知插件名非零退出
  - `-n` / `--dry-run` 被识别
- 若有对应 Bazel 目标，同步覆盖；否则至少保证 shell 回归与 `bash -n`。

## 非目标

- 不拆分 `lib/` 多文件。
- 不按已装插件裁剪 `.bashrc` 配置块。
- 不新增卸载子命令。
- 不同步改造 `shell/zsh/setup.sh`（可后续对齐）。
- 不改变 ble.sh `--noinputrc` 等既有修复行为。
