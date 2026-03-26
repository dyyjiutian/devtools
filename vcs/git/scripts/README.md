# Git Scripts

本目录提供两个独立的 shell 脚本，用于快速初始化 Git 环境。

## 目录

- [脚本说明](#脚本说明)
- [alias.sh — 安装 Git 快捷命令](#aliassh--安装-git-快捷命令)
- [git_config.sh — 初始化 Git 全局配置](#git_configsh--初始化-git-全局配置)
- [github.gitconfig — Git 别名配置](#githubgitconfig--git-别名配置)
- [在新机器上快速上手](#在新机器上快速上手)

---

## 脚本说明

| 脚本 | 功能 |
|------|------|
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
| `gitalias` | 打印以上所有命令的说明 |

> `gitrebase` 和 `gitprune` 通过 `git symbolic-ref refs/remotes/origin/HEAD`
> 自动识别默认分支（main / master 等），无需硬编码。

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
| Pull/Rebase | `pull.rebase = true` | pull 默认 rebase |
| Pull/Rebase | `rebase.autoStash = true` | rebase 前自动 stash |
| Pull/Rebase | `merge.conflictstyle = diff3` | 冲突标记显示 base 版本 |
| Push | `push.default = current` | 推送到同名远端分支 |
| Push | `push.autoSetupRemote = true` | 首次推送自动 `--set-upstream` |
| Fetch | `fetch.prune = true` | 自动清理过期远端追踪分支 |
| Diff | `diff.algorithm = histogram` | 更精准的代码 diff |
| Branch | `branch.sort = -committerdate` | 分支按最近提交时间排序 |
| Branch | `init.defaultBranch = main` | 新仓库默认分支名 |
| Security | `credential.helper = osxkeychain` | 凭据存入 macOS Keychain |

执行完毕后可运行以下命令核验：

```bash
git config --global --list
```

---

## github.gitconfig — Git 别名配置

位于 `../config/github.gitconfig`，提供与 GitHub 工作流相关的 Git 别名。

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
| `git review` | 推送当前分支到 origin 并使用 `gh` 命令行创建 PR（`--fill` 自动填充标题和描述） |

> **前提**: 需要安装 [GitHub CLI](https://cli.github.com/) (`gh`) 并已认证。

---

## 在新机器上快速上手

```bash
# 1. 克隆 devtools
git clone <repo-url> ~/devtools

# 2. 初始化 Git 全局配置
bash ~/devtools/vcs/git/scripts/git_config.sh

# 3. 安装 Git 快捷命令
bash ~/devtools/vcs/git/scripts/alias.sh
source ~/.zshrc   # 或 source ~/.bashrc
```
