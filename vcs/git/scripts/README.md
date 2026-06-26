# Git Scripts

本目录提供 Git 环境初始化脚本。推荐优先使用上一层的 `../setup.sh` 一键完成配置；本目录脚本也可以单独运行。

## 目录

- [脚本说明](#脚本说明)
- [alias.sh — 安装 Git 快捷命令](#aliassh--安装-git-快捷命令)
- [git_config.sh — 初始化 Git 全局配置](#git_configsh--初始化-git-全局配置)
- [github.gitconfig — Git review 别名配置](#githubgitconfig--git-review-别名配置)
- [Delta — 增强 diff 显示](#delta--增强-diff-显示)
- [在新机器上快速上手](#在新机器上快速上手)

---

## 脚本说明

| 脚本 | 功能 |
|------|------|
| `../setup.sh` | 一键安装 delta、安装 `git rb` / `git bc`、写入 git config、安装 shell aliases、应用 status/pull/fetch 优化 |
| `alias.sh` | 向 `~/.zshrc` 或 `~/.bashrc` 注入 Git 快捷函数 |
| `git_config.sh` | 交互式设置 Git 全局配置（`~/.gitconfig`） |

---

## alias.sh — 安装 Git 快捷命令

脚本自动识别 `$SHELL`，将 alias 块写入对应的 rc 文件（`~/.zshrc` 或 `~/.bashrc`），
并用注释标记包裹，支持幂等安装与精准卸载。

### 用法

```bash
# 查看帮助
bash alias.sh --help

# 安装 alias（写入 rc 文件）
bash alias.sh

# 激活（当前终端立即生效）
source ~/.zshrc        # 或 source ~/.bashrc

# 卸载（需手动确认）
bash alias.sh --clean
```

### 安装后可用的命令

| 命令 | 功能 |
|------|------|
| `gitroot` | 从仓库任意子目录跳转到根目录 |
| `gitrebase` | 拉取远端默认分支最新代码并 rebase 当前分支 |
| `gitprune` | 列出已合入默认分支的本地分支，确认后批量删除 |
| `gitreview` | 为当前分支创建 PR / MR / Gerrit Review，自动识别平台 |
| `gitalias` | 打印以上所有命令的说明 |

> 所有命令均通过 `git symbolic-ref refs/remotes/origin/HEAD` 自动识别默认分支（main / master 等），无需硬编码。

### gitreview 平台识别规则

`gitreview` 根据 `origin` remote URL 自动选择提交方式，目标分支统一为仓库主干分支：

| 平台 | 识别条件 | 执行操作 |
|------|---------|---------|
| GitHub | URL 含 `github.com` | `gh pr create --fill --base <主干>` |
| GitLab | URL 含 `gitlab` | `git push -o merge_request.create -o merge_request.target=<主干>` |
| Gerrit | 其余情况 | `git push origin HEAD:refs/for/<主干>` |

GitLab 使用服务端 push options，无需额外 CLI。GitHub 需要安装 [`gh`](https://cli.github.com/) 并已登录认证。

---

## git_config.sh — 初始化 Git 全局配置

交互式提示输入姓名和邮箱（自动读取已有值作为默认），随后一次性写入所有推荐的全局配置。

### 用法

```bash
# 查看帮助
bash git_config.sh --help

# 交互式执行（推荐首次使用）
bash git_config.sh

# 预览模式：只打印、不修改任何配置
bash git_config.sh --dry-run
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
| Delta | `delta.navigate = true` | `n` / `N` 在 diff 段间跳转 |
| Branch | `branch.sort = -committerdate` | 分支按最近提交时间排序 |
| Branch | `init.defaultBranch = main` | 新仓库默认分支名 |
| Security | `credential.helper = osxkeychain` | 凭据存入 macOS Keychain |

执行完毕后可运行以下命令核验：

```bash
git config --global --list
```

---

## github.gitconfig — Git review 别名配置

位于 `../config/github.gitconfig`，提供跨 GitHub / GitLab / Gerrit 的 `git review` 别名。

### 用法

```bash
# 引入到全局配置
git config --global include.path ~/devtools/vcs/git/config/github.gitconfig

# 或在 ~/.gitconfig 中添加：
# [include]
#   path = ~/devtools/vcs/git/config/github.gitconfig
```

### 可用别名

| 别名 | 功能 |
|------|------|
| `git rb [branch]` | 拉取远端默认分支并 rebase 当前分支；传参时使用指定目标分支 |
| `git rb --help` | 显示用法和示例 |
| `git bc [branch] [--dry-run]` | 删除已合入目标远端分支的本地分支，支持试运行 |
| `git bc --help` | 显示用法、安全规则和示例 |
| `git review` | 自动识别 origin 平台，向远端主干分支创建 GitHub PR / GitLab MR / Gerrit review |
| `git review <branch>` | 指定目标分支创建 review |

平台识别规则与 `alias.sh` 安装的 `gitreview` 保持一致：GitHub 使用 `gh pr create --fill --base <主干>`，GitLab 使用 push options 创建 MR，其他 remote 默认按 Gerrit 推送到 `refs/for/<主干>`。

`git rb` / `git bc` 是安装到 `~/.local/bin` 的 Git 子命令，因此支持 `git rb --help` / `git bc --help`。`gitroot` 仍保留为 shell alias，因为 `cd` 必须发生在当前 shell 进程中；Git alias 不能改变父 shell 的当前目录。

---

## Delta — 增强 diff 显示

[git-delta](https://github.com/dandavison/delta) 是 git diff / log / show 的增强 pager，提供语法高亮和左右对比视图。

### 安装

```bash
brew install git-delta          # macOS（或通过 os/macos/setup.sh 一并安装）
```

### 配置

`git_config.sh` 会自动检测 delta 是否已安装并写入以下配置：

```ini
[core]
    pager = delta
[interactive]
    diffFilter = delta --color-only
[delta]
    navigate = true        # n/N 在 diff 段间跳转
    side-by-side = true    # 左右对比布局
    line-numbers = true    # 显示行号
    syntax-theme = Dracula # 语法高亮主题
    diff-highlight = true  # 行内变更词高亮
```

### 常用键位（delta pager 中）

| 按键 | 功能 |
|------|------|
| `n` / `N` | 跳到下 / 上一个 diff 段 |
| `q` | 退出 |
| `Space` / `b` | 向下 / 向上翻页 |

---

## 在新机器上快速上手

```bash
# 1. 克隆 devtools
git clone <repo-url> ~/devtools

# 2. 一键配置 Git（delta + git config + aliases + status/pull 优化）
bash ~/devtools/vcs/git/setup.sh
source ~/.zshrc   # 或 source ~/.bashrc，按当前 shell 选择

# 验证
git config --global --list
gitalias
```
