# Git 工具集

Git 开发环境的一键配置与可移植子命令。推荐用 `setup.sh` 一键完成；各脚本也可单独运行。

## 目录结构

```
tools/git/
├── setup.sh            # 一键配置入口
├── bin/                # 可移植的 git 子命令（安装到 ~/.local/bin）
│   ├── git-rb          #   git rb           — fetch + rebase 到远端目标分支
│   ├── git-bc          #   git bc           — 清理已合入的本地分支
│   ├── git-wc          #   git wc           — 清理已合入的 linked worktree 及分支
│   ├── git-review      #   git review       — 自动识别平台创建 PR / MR / Gerrit review
│   └── git-sparse-clone #  git sparse-clone — 稀疏克隆指定目录（cone） / 追加路径
├── man/man1/           # 上述子命令的 man 手册
└── scripts/            # setup.sh 各步骤对应的可单独运行脚本
    ├── sub-command.sh  # 安装 git rb / bc / wc / review / sparse-clone 子命令及 man 手册
    ├── config.sh       # 交互式写入推荐的 git 全局配置与性能优化
    └── alias.sh        # 安装 shell alias（仅 gitroot）
```

> 设计约定：所有工作流命令都做成**可移植的 git 子命令**（复制到 `~/.local/bin`），
> 即使删除本代码库也不会失效；只有 `gitroot` 保留为 shell alias，因为 `cd` 必须发生在
> 当前 shell 进程内，git 子命令运行在子进程中无法改变父 shell 的目录。

---

## setup.sh — 一键配置

```bash
bash setup.sh              # 完整配置
bash setup.sh --dry-run    # 预览，不做任何改动
bash setup.sh --skip-delta # 跳过 git-delta 安装
bash setup.sh --skip-gh    # 跳过 GitHub CLI (gh) 安装
bash setup.sh --skip-alias # 跳过 shell alias
bash setup.sh --skip-config # 跳过 git config
```

执行内容（每步对应 `scripts/` 下一个可单独运行的脚本）：

1. 安装 [git-delta](https://github.com/dandavison/delta) 并配置为 diff/log/show pager
2. 安装 [GitHub CLI (`gh`)](https://cli.github.com/)；DNF 系统自动添加 GitHub 官方 RPM 源，并提示执行 `gh auth login` 完成 GitHub 认证
3. `scripts/sub-command.sh`：安装 `git rb` / `git bc` / `git wc` / `git review` / `git sparse-clone` 子命令及 man 手册到 `~/.local/bin`
4. `scripts/config.sh`：写入推荐的 git 全局配置与 status / pull / fetch / checkout 性能优化
5. `scripts/alias.sh`：安装 `gitroot`

`setup.sh` 支持 `--skip-delta` / `--skip-gh` / `--skip-subcmd` / `--skip-config` / `--skip-alias` 分别跳过对应步骤，并会自动把 `~/.local/bin` 写入 rc 文件的 `PATH`。

Linux 只识别 `apt`、`dnf`、`yum` 三类包管理器。安装 git-delta 时会优先使用临时镜像配置，不会改写系统仓库文件：

- Ubuntu / Debian：临时使用阿里云 APT source，失败后回退当前系统 APT 仓库。
- RHEL / CentOS / Rocky / AlmaLinux 8/9：临时使用阿里云 EPEL 仓库，失败后回退当前系统 DNF/YUM 仓库。
- CentOS 7 x86_64：优先校验并使用仓库缓存的 git-delta 0.19.2 musl 静态包；缓存缺失或损坏时从固定上游 URL 下载并校验，最后再回退 YUM/DNF 仓库。

临时 source、repo、下载和解压目录会在成功或失败后清理。静态包固定使用 SHA-256 `f1ea01ca7728ce3462debc359f39dfc7cbbc1a63224b71fefabf92042864aa1b`，安装目标为 `/usr/local/bin/delta`。

---

## git 子命令（scripts/sub-command.sh）

由 `scripts/sub-command.sh` 安装到 `~/.local/bin`（可单独运行，支持 `--dry-run` / `--help`）：

```bash
bash scripts/sub-command.sh            # 安装子命令 + man 手册
bash scripts/sub-command.sh --dry-run  # 预览
```

| 命令 | 功能 |
|------|------|
| `git rb [branch]` | fetch 远端默认分支（或指定分支）并 rebase 当前分支 |
| `git bc [branch] [--dry-run]` | 删除已合入目标远端分支的本地分支（含 merged / rebase）；worktree 中的分支请用 `git wc` |
| `git wc [branch] [--dry-run]` | 删除已合入的 linked worktree 及其本地分支（含 merged / rebase） |
| `git review [branch]` | 自动识别 origin 平台，向远端主干分支创建 review |
| `git sparse-clone <url> [paths...]` | 稀疏克隆指定目录（cone）；无路径时仅根目录文件 |
| `git sparse-clone --append [paths...]` | 在已有稀疏仓中追加路径（可用 `--dir`） |

所有子命令均支持 `--help`，并通过 `git symbolic-ref refs/remotes/origin/HEAD` 自动识别默认分支（main / master 等）。`git bc` / `git wc` 默认保护 `main` / `master` / `develop` / `dev` 及目标分支。

### git sparse-clone

从大型仓库只检出需要的目录（默认启用 `--filter=blob:none` 与浅克隆 `--depth 1`）：

```bash
git sparse-clone <url>                         # 仅根目录文件
git sparse-clone <url> devtools scripts        # 指定多个目录
git sparse-clone --dir my-sparse --branch main <url> src
git sparse-clone --append scripts              # 在当前稀疏仓追加
git sparse-clone --append --dir /path/to/repo deploy
```

常用选项：`--dir`、`--branch`、`--commit`、`--depth`（`0` = 完整历史）、`--no-filter`、`--force`、`--dry-run`。首版为 cone 模式字面路径；glob / `!` 排除尚未支持。

### git review 平台识别规则

`git review` 根据 `origin` remote URL 自动选择提交方式，目标分支默认取仓库主干（可用 `git review <branch>` 覆盖），识别按下表优先级进行：

| 平台 | 识别条件 | 执行操作 |
|------|---------|---------|
| GitHub | URL 含 `github.com` | `git push -u origin HEAD` + `gh pr create --fill --base <主干>` |
| Alibaba GitLab | URL 含 `alibaba` | `git push origin HEAD:refs/for/<主干>/<当前分支>` |
| GitLab | URL 含 `gitlab` | `git push -o merge_request.create -o merge_request.target=<主干>` |
| Gerrit | 其余情况 | `git push origin HEAD:refs/for/<主干>` |

Alibaba GitLab 采用 Gerrit 风格的 `refs/for/<主干>/<当前分支>` 提交，识别优先级高于通用 GitLab。`setup.sh` 会安装 [GitHub CLI (`gh`)](https://cli.github.com/)；安装后请自行执行 `gh auth login` 完成认证。GitLab 使用服务端 push options，无需额外 CLI。

---

## scripts/config.sh — 初始化 Git 全局配置

交互式提示输入姓名和邮箱（自动读取已有值作为默认），随后一次性写入所有推荐的全局配置，以及 status / pull / fetch / checkout 性能与工作流优化。

```bash
bash scripts/config.sh           # 交互式执行
bash scripts/config.sh --dry-run # 预览，不修改任何配置
bash scripts/config.sh --help
```

### 配置项速览

| 分类 | 关键配置 | 说明 |
|------|---------|------|
| Identity | `user.name` / `user.email` | 提交署名，交互输入 |
| Core | `core.autocrlf = input` | 提交时 CRLF → LF |
| Core | `core.ignorecase = false` | 文件名大小写敏感 |
| Core | `core.pager = delta` | 使用 delta 渲染 diff（需安装 delta） |
| Pull/Rebase | `pull.rebase = true` | pull 默认 rebase |
| Pull/Rebase | `rebase.autoStash = true` | rebase 前自动 stash |
| Pull/Rebase | `merge.conflictstyle = diff3` | 冲突标记显示 base 版本 |
| Push | `push.default = current` | 推送到同名远端分支 |
| Push | `push.autoSetupRemote = true` | 首次推送自动 `--set-upstream` |
| Fetch | `fetch.prune = true` | 自动清理过期远端追踪分支 |
| Diff | `diff.algorithm = histogram` | 更精准的代码 diff |
| Delta | `delta.side-by-side = true` | 左右对比显示 diff |
| Branch | `branch.sort = -committerdate` | 分支按最近提交时间排序 |
| Branch | `init.defaultBranch = main` | 新仓库默认分支名 |
| Security | `credential.helper = osxkeychain` | 凭据存入 macOS Keychain（Linux 用 cache） |
| Performance | `pull.ff = only` / `status.renames` / `fetch.parallel = 8` | status/pull/fetch/checkout 优化 |
| Performance | `protocol.version = 2` / `checkout.workers = 0` | 协议 v2 + 并行 checkout |

---

## scripts/alias.sh — 安装 shell alias

只安装 `gitroot`（从仓库任意子目录跳转到根目录），写入对应 rc 文件（`~/.zshrc` 或 `~/.bashrc`），并用注释标记包裹，支持幂等安装与精准卸载。

```bash
bash scripts/alias.sh          # 安装
bash scripts/alias.sh --clean  # 卸载（需手动确认）
source ~/.zshrc                # 激活（或 source ~/.bashrc）
```

| 命令 | 功能 |
|------|------|
| `gitroot` | 从仓库任意子目录跳转到根目录 |

---

## Delta — 增强 diff 显示

[git-delta](https://github.com/dandavison/delta) 是 git diff / log / show 的增强 pager，提供语法高亮和左右对比视图。`setup.sh` 会在 macOS 使用 Homebrew，在 Linux 使用 APT/DNF/YUM 或 CentOS 7 x86_64 静态缓存安装；`config.sh` 检测到 delta 后写入相关配置。

```bash
brew install git-delta          # macOS（或通过 os/macos/setup.sh 一并安装）
```

常用键位（delta pager 中）：`n` / `N` 跳到下 / 上一个 diff 段，`Space` / `b` 翻页，`q` 退出。

---

## 在新机器上快速上手

```bash
# 1. 克隆 devtools
git clone <repo-url> ~/devtools

# 2. 一键配置 Git（delta + git config + 子命令 + gitroot + status/pull 优化）
bash ~/devtools/tools/git/setup.sh
source ~/.zshrc   # 或 source ~/.bashrc

# 3. 验证
git config --global --list
git rb --help
git review --help
git sparse-clone --help
```

## Issues

### 2026-08-10 — macOS 上 `git bc` 报 `declare: -A: invalid option`

**表象**：macOS 运行 `git bc` 立即报错退出：
```
/Users/devuser/.local/bin/git-bc: line 111: declare: -A: invalid option
declare: usage: declare [-afFirtx] [-p] [name[=value] ...]
```

**根因**：`git bc` 用 `declare -A`（关联数组）记录 worktree 分支路径，该语法要求 Bash 4.0+；macOS 默认 `/bin/bash` 为 3.2，shebang `#!/usr/bin/env bash` 解析到 3.2 即失败，违反仓库「macOS Bash 3.2+」兼容基线。

**解法**：改用 Bash 3.2 兼容的并行索引数组 `wt_branches`/`wt_paths` + 线性查找替换关联数组。已同步重装 `~/.local/bin/git-bc`，并在 `tools/git/tests/git_suite.sh` 增加回归测试 `test_bc_skips_worktree_and_flags_merged`（旧代码在 bash 3.2 下必失败）。

### 2026-07-30 — Linux 安装 git-delta 提示找不到软件

**表象**：在部分 Ubuntu/Debian、RHEL/CentOS 系统运行 `bash tools/git/setup.sh` 时，系统仓库提示找不到 `git-delta`；首次包管理器安装失败后脚本直接跳过，CentOS 7 即使仓库内有离线资产也无法继续安装。

**根因**：原安装流程只调用当前系统仓库，失败后立即返回；没有临时镜像、已校验静态包或后续仓库回退。CentOS 7 的常用仓库也不提供所需版本。

**解法**：Ubuntu/Debian 临时使用阿里云 APT source，RHEL 系 8/9 临时使用阿里云 EPEL；CentOS 7 x86_64 优先使用仓库内固定版本的 musl 静态包，缓存缺失或校验失败时从上游固定 URL 重下并校验 SHA-256。所有方式失败后再尝试当前 APT/DNF/YUM 仓库。

### 2026-07-27 — 大型仓库稀疏克隆步骤多、易配错

原生 `git clone --sparse` + `sparse-checkout` 需要多步参数组合，且 cone / filter / depth 容易漏配。新增可移植子命令 `git sparse-clone`：默认 `--filter=blob:none`、`--depth 1`、cone 模式；支持多路径与 `--append` 追加。安装：`bash tools/git/scripts/sub-command.sh`。
