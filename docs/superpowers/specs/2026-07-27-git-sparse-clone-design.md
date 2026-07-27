# git sparse-clone 设计

## 目标

在 `tools/git` 中沉淀可移植子命令 `git sparse-clone`，把「大型仓库只拉指定目录」的多步 Git 稀疏克隆流程收成一条命令；首版覆盖 cone 模式目录稀疏 + 追加路径，不引入 glob / 否定模式。

## 决策摘要

| 项 | 选择 |
|---|---|
| 命令形态 | `git sparse-clone <url> [paths...]`（位置参数为主） |
| 实现形态 | 单文件可移植脚本 `tools/git/bin/git-sparse-clone` |
| 稀疏模式 | cone only |
| 无路径默认 | 只检出根目录文件（不含子目录） |
| 追加 | `git sparse-clone --append [--dir DIR] <paths...>` |
| 延后 | `--no-cone`、glob、`!` 排除 |

## 命令接口

### 新建稀疏克隆

```bash
git sparse-clone <url> [paths...] [options]
```

| 选项 | 含义 | 默认 |
|------|------|------|
| `--dir <DIR>` | 本地目标目录 | 从 URL 解析仓库名（去掉 `.git`） |
| `--branch <BRANCH>` | 克隆分支 | 远程默认分支（由 `git clone` 决定） |
| `--commit <SHA>` | 检出到指定 commit | 无 |
| `--depth <N>` | 浅克隆深度；`0` = 完整历史 | `1` |
| `--no-filter` | 禁用 `--filter=blob:none` | 默认启用 blob filter |
| `--force` | 目标目录已存在则删除后重建 | 默认：TTY 交互确认；非 TTY 失败 |
| `--dry-run` | 只打印将执行的步骤，不改动磁盘 | off |
| `-h, --help` | 帮助 | — |

### 追加模式

```bash
git sparse-clone --append [--dir <DIR>] <paths...>
```

- 必须至少提供一个 path。
- 默认在当前仓库（`git rev-parse --show-toplevel`）追加；`--dir` 可指向其他已有稀疏仓。
- 不接受 `<url>`。

### 路径校验（首版）

路径按字面目录处理。若任一 path 含 `*`、`?`、`[`、`]` 或以前导 `!` 表示排除，则报错并提示首版不支持 glob / 否定模式。

## 内部流程

### 新建克隆

1. 解析参数；校验 URL 必填；校验路径字面量。
2. 解析目标目录；若已存在：
   - `--force` → 删除后继续
   - TTY → 确认后删除
   - 非 TTY → 失败退出
3. 组装 `git clone`：
   - 默认：`--filter=blob:none --sparse`
   - `--depth N`（`N>0`）；`N=0` 不传 `--depth`
   - 可选 `--branch`
   - `--no-filter` 时省略 filter
4. 进入目标目录。
5. 若提供了 paths：`git sparse-checkout set --cone -- <paths...>`  
   若未提供：保持 `git clone --sparse` 的默认（仅根目录文件）。
6. 若提供了 `--commit`：在仓库内 `git fetch`（保留 depth/filter 语义）后 `git checkout <commit>`。浅克隆下若对象不可达，给出明确错误。
7. 打印成功摘要（目录、分支/commit、稀疏路径）。

### 追加

1. 解析仓库根（`--dir` 或当前仓）。
2. 确认是 git 工作树，且已启用 sparse-checkout（否则报错提示先用新建模式或手动开启）。
3. `git sparse-checkout add -- <paths...>`（cone 模式）。
4. 打印更新后的稀疏路径列表（`git sparse-checkout list`）。

### dry-run

打印将执行的 `git clone` / `sparse-checkout` / `checkout` 命令，不创建目录、不改仓库。

## 错误处理

- 缺少 URL（非 append）或 append 缺少 paths → usage + exit 1
- 目标目录冲突且未强制/未确认 → exit 1
- 路径含 glob/否定字符 → exit 1，提示后续能力
- append 目标不是 git 仓或未开 sparse-checkout → exit 1
- 要求 Git ≥ 2.25（`clone --sparse` / `sparse-checkout` cone）

## 集成与文档

- `scripts/sub-command.sh`：安装 `git-sparse-clone` 与 `man/man1/git-sparse-clone.1`
- `tools/git/README.md`：补充命令表与示例
- `setup.sh` 帮助文案中的子命令列表同步更新（若有枚举）

## 测试

在 `tools/git/tests/git_suite.sh`（或同模块专用用例）中用**本地 bare 仓库**验证，不依赖外网：

1. `--help` 含用法关键字
2. 非法 glob / `!` 路径被拒绝
3. 无路径克隆：仅根文件存在，子目录不在工作树
4. 指定 paths 克隆：目标目录在、未请求目录不在
5. `--append` 增加路径后新目录出现
6. `--dry-run` 不创建目标目录
7. `sub-command.sh` 安装后存在 `~/.local/bin/git-sparse-clone`
8. 覆盖 `macos` 与 `linux_centos` profile（沿用现有 `devtools_module_tests`）

## 非目标（首版不做）

- non-cone / 文件 glob / `!**/*.jar` 类排除
- 从稀疏仓移除路径的子命令
- 交互式路径选择器
- 包装为 shell alias（必须是可移植 git 子命令）
