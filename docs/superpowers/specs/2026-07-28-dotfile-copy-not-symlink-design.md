# Dotfile 部署改用真实复制（非软链）设计

## 目标

将 vim / tmux 的用户配置部署从 `ln -sf` 改为真实 `cp`，避免本机配置依赖仓库路径；覆盖语义保持与现网一致。

## 决策摘要

| 项 | 选择 |
|---|---|
| 范围 | `editors/vim`、`terminal/tmux` 的配置文件部署 |
| 不改 | 工具二进制软链（bazel/fzf/fd/bat/frps）、`agents/cookbook`（默认链 + `--copy`） |
| 覆盖策略 | 每次用仓库配置覆盖目标；普通文件先备份 |
| 已有软链 | 先删除软链再 `cp`，避免写穿到源文件 |
| 对齐参考 | `editors/nvim` 的 copy 路径、`vim --restore` 已有 `cp` |

## 部署语义

对目标路径 `DST`、源文件 `SRC`：

1. 若 `DST` 为普通文件（非软链）：备份为 `DST.bak.<timestamp>`，再 `cp SRC DST`
2. 若 `DST` 为软链：`rm -f DST`，再 `cp SRC DST`（不备份；与旧 `ln -sf` 行为一致）
3. 若 `DST` 不存在：直接 `cp SRC DST`
4. 重复执行可重入：始终以仓库内容覆盖；已有普通文件每次都会再备份

## 文档与测试

- 更新 vim/tmux `setup.sh --help` 与 README；在模块 Issues 记录「软链改为复制」
- 更新 `terminal/tmux/tests/tmux_suite.sh`：断言目标为普通文件且内容等于源文件

## 非目标

- 不抽公共 `deploy_dotfile` 库
- 不为 cookbook / 二进制入口改默认链接策略
