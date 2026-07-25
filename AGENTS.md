# AGENTS.md

## 项目定位

`devtools` 是一个用于快速搭建和初始化开发环境的工具库，主要通过 Bash 脚本安装软件、配置终端与编辑器、初始化语言运行时、部署网络工具，并提供 Git 与 AI Agent 的辅助配置。

这是一个“脚本编排 + 配置资产 + 可选 Bazel 验证”的仓库。修改时优先保持模块边界清晰、脚本可重复执行，并避免把某台机器的临时状态写进仓库。

## 指令优先级

遵循以下优先级：

1. 用户当前请求。
2. 本文件中的仓库级约定。
3. 修改目标目录下更具体的 `AGENTS.md`、`CLAUDE.md` 或 README。
4. `README.md`、`BAZEL.md` 及脚本自身的 `--help` 输出。

`agents/codex/config/AGENTS.md` 当前只规定交互语言：用户使用中文时仅用中文回复，使用英文时仅用英文回复。不要让根目录文档覆盖该语言约定。

## 仓库结构

| 路径 | 职责 | 修改提示 |
|---|---|---|
| `setup.sh` | 根入口：交互式、全量或按模块编排初始化 | 新增模块时同步更新帮助、菜单、模块分派与 dry-run 行为 |
| `os/` | macOS、Ubuntu/Debian、CentOS/RHEL 的系统初始化 | 可能安装系统包、写入系统配置或启用服务 |
| `lang/` | Python、Go、Java、Rust 等语言运行时 | 保持各语言安装器独立，不把语言特有逻辑塞进根入口 |
| `shell/` | Bash、Zsh、Oh My Zsh、Starship 等 Shell 配置 | 注意 shell 启动文件的幂等修改 |
| `terminal/` | Ghostty、iTerm2、tmux、Yazi 等终端工具 | 配置文件与安装脚本分离 |
| `editors/` | Neovim、Vim、Cursor、VS Code 等编辑器 | 修改配置格式时同步检查对应 README |
| `network/` | FRP、代理、VPN 等网络与基础设施脚本 | 网络、服务、防火墙和远程节点操作必须显式说明风险 |
| `tools/` | Bazel、Git、SSH 等暂未继续细分的独立工具 | 有明确领域边界后再迁移到专门目录 |
| `tools/git/` | Git 全局配置、可移植子命令和 shell alias | 关注 `git rb`、`git review` 与 worktree 的交互 |
| `tools/ssh/` | SSH 客户端优化与 fssh 远程会话选择器 | 修改 SSH 配置前保留备份并说明远程影响 |
| `agents/` | Claude、Codex、Cursor Agent 配置与最佳实践 | 配置同步必须保留用户未托管的内容和敏感信息 |
| `cache/` | 安装脚本与二进制缓存，用于离线或加速安装 | 更新缓存版本时同步校验下载脚本、架构和测试 |
| `os/macos/` | macOS 初始化、电源、Agent 通知和远程桌面 | 涉及系统设置、屏幕共享和 SSH，变更前先读局部 README |
| `tests/`、`os/macos/*.bats` | Shell 回归测试 | 优先用临时目录和 fake 命令验证，不执行真实安装 |
| `docs/superpowers/` | 设计文档和实现计划 | 设计与实现保持一致，不用计划文档替代代码验证 |

根入口并不覆盖所有目录：`network/`、`tools/`、`agents/`、`os/macos/remote-desktop/` 等通常需要直接运行各自的 `setup.sh` 或阅读对应 README。不要因为目录存在就假设它会被 `./setup.sh --all` 自动安装。

## 设计与实现原则

### 优先采用清晰的架构边界

新增功能时优先使用 Clean Architecture 等思想，按以下方向组织 Shell 代码：

`CLI 参数/交互界面` → `用例编排` → `系统、包管理器、网络和服务适配器`

- 根入口只负责参数解析、模块选择和流程编排。
- 一个子目录的 `setup.sh` 聚焦一个工具或一个环境能力；复杂脚本继续拆成职责单一的函数或辅助脚本。
- 配置模板、缓存二进制和外部资源属于数据/基础设施，不要与业务决策混在一起。
- 高层流程不要依赖某个具体发行版、包管理器或远程服务的细节；把差异收敛在适配函数中。
- 修改行为时优先复用已有接口和 marker，避免引入全局状态、隐式副作用或跨模块复制粘贴。
- 如果新增抽象不能降低耦合或提升可测试性，就不要为了“架构完整”而增加层次。

### Shell 脚本约定

除非目标脚本已有明确例外，遵循仓库现有模式：

- 使用 `set -euo pipefail`，正确引用变量并处理空值、失败状态和临时文件。
- 提供 `--help`；有副作用的脚本尽量提供 `--dry-run`、`--info-only` 或等价的预览模式。
- 重复执行应安全：写入 shell 配置、服务配置和编辑器配置前使用 marker、备份或幂等更新。
- 破坏性操作、系统服务、代理/VPN、iptables、防火墙和远程节点操作必须明确权限、目标和回滚方式。
- 保持现有 Bash 兼容性；不要无必要地引入仅新版本 Bash 支持的语法。
- 下载外部脚本或二进制时优先使用 `cache/` 中已有资产；变更下载源、版本、校验和或架构时补充测试。
- 不提交 API Key、密码、UUID、私钥、个人机器路径或临时生成的配置。
- 命令和帮助文本使用简洁、易懂、接近业界惯用表达的名称；选项命名保持一致，例如 `--help`、`--dry-run`、`--skip-*`。

### 文档约定

- 根目录 `README.md` 面向使用者，子目录 README 面向该模块的使用与运维；本文件面向开发代理和贡献者。
- 文档中的命令必须尽量可复制；路径从仓库根目录书写，并注明需要 `sudo`、网络、特定系统或额外工具的场景。
- 事实以当前脚本和测试为准。若 README 与实现不一致，先确认是否需要同步修正文档，不要在新文档中扩大未验证的承诺。

## 常用开发流程

### 开始工作

使用 Superpowers 工作流时，必须先在独立 Git worktree 中工作：

```bash
git worktree add .worktrees/<topic> -b <topic>
cd .worktrees/<topic>
git status --short
```

先阅读目标目录的 README、脚本帮助和相关测试，再确定修改范围。不要覆盖用户已有改动，也不要用破坏性 Git 命令清理未确认的文件。

### 安全预览

安装器通常会修改 `$HOME`、系统包、服务或网络配置。开发和调试优先使用：

```bash
bash setup.sh --help
bash setup.sh --modules python --dry-run
bash lang/python/setup.sh --help
bash lang/python/setup.sh --dry-run
```

不要为了验证语法而运行真实安装，不要在没有明确目标主机、端口和回滚方案时执行 VPN、代理、FRP 或远程部署脚本。

### 验证修改

按修改范围选择最小但充分的验证：

```bash
# Shell 语法
bash -n setup.sh
bash -n lang/python/setup.sh

# Linux 回归测试
bash tests/linux_setup_scripts_test.sh

# macOS Bats 测试（本地需要 bats；也可使用 Bazel）
bash os/macos/run_bats.sh

# Bazel 可用时
bazel build //...
bazel test //...
bazel test //os/macos:macos_setup_bats_test
```

若环境没有 `bazel` 或 `bats`，明确记录未执行原因；不要把工具缺失误报为代码通过。对安装逻辑优先测试 `--help`、`--dry-run`、已有缓存路径、重复执行和失败回滚路径。

## Git 提交与 PR

提交前至少检查：

```bash
git status --short
git diff --check
git diff
```

提交信息使用简洁的业界常见格式，例如 `docs: add repository agent guide`、`fix: make installer idempotent`。完成验证并提交后，优先使用仓库提供的工作流：

```bash
git rb && git review
```

其中 `git rb` 用于将当前分支 rebase 到远端默认分支，`git review` 根据 `origin` 自动选择 GitHub PR、GitLab MR 或其他 review 入口。

如果上述提交流程报错，按以下顺序回退，不要直接绕过 rebase：

```bash
git fetch origin
git rebase origin/main
git push -u origin HEAD
gh pr create --fill --base main
```

若主分支不是 `main`，先通过 `git remote show origin` 或仓库默认分支配置确认目标分支。发生 rebase 冲突时先解决并验证，再继续推送；除非用户明确授权，不使用强制推送覆盖他人提交。

## 完成检查清单

- [ ] 变更只涉及任务范围，且没有覆盖用户已有改动。
- [ ] 新增行为遵循清晰边界，根入口没有承载不属于它的具体实现细节。
- [ ] 相关脚本有 `--help`，有副作用时有安全预览或明确限制。
- [ ] Shell 语法、相关回归测试和可用的 Bazel/Bats 检查已执行。
- [ ] 文档、缓存版本、测试和脚本行为保持一致。
- [ ] `git diff --check` 通过，提交前已确认没有敏感信息。
- [ ] 提交前已执行 `git rb && git review`；如失败，已先 rebase 主分支再使用常规 PR 流程。
