# Git setup 中安装 GitHub CLI 的设计

## 目标

`tools/git/setup.sh` 在安装 `git review` 子命令的同一套 Git 开发环境中安装 GitHub CLI（`gh`），使 GitHub 仓库可直接使用 `git review` 创建 PR。安装完成后，脚本明确提醒用户自行执行 `gh auth login` 完成认证。

## 方案

在现有 `install_delta` 后新增独立的 `install_gh` 步骤：

- 已存在 `gh` 时仅报告其版本，不重复安装。
- macOS 使用 Homebrew 安装 `gh`。
- Linux 复用现有发行版包管理器分支：`apt-get`、`dnf`、`yum`、`pacman`、`zypper`。
- 没有可用包管理器、系统不受支持或安装失败时，输出警告并继续执行后续 Git 配置；这与 `git-delta` 的容错行为一致。
- `--dry-run` 只打印将执行的安装命令，不修改系统。

该步骤不增加新的命令行选项，保证执行 `setup.sh` 即可为 GitHub `git review` 工作流准备所需 CLI。

## 用户提示与文档

安装流程结束时，如果 `gh` 已可用，输出 `gh auth login`，提醒用户认证 GitHub 账号。更新 `tools/git/README.md` 和仓库根 `README.md`，说明一键 Git 配置也会安装 `gh`，以及 GitHub 创建 PR 前必须完成登录。

## 错误处理与验证

安装失败不能中断 `git-delta`、子命令、Git 配置和 shell alias 等其他步骤。验证覆盖：

- `bash tools/git/setup.sh --dry-run` 显示 `gh` 安装计划及登录提示；
- `bash -n tools/git/setup.sh` 通过 shell 语法检查；
- 文档与实际安装、认证行为一致。
