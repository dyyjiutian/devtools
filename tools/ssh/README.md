# SSH 工具

优化 SSH 客户端连接复用、KeepAlive，并提供 fzf 驱动的 fssh 远程会话选择器。

~~~bash
bash tools/ssh/setup.sh --help
bash tools/ssh/setup.sh --dry-run
bash tools/ssh/fssh.sh --help
~~~

依赖 ssh 和 fzf；脚本会备份并更新 ~/.ssh/config。

## Issues

### 2026-07-28 — fssh 无法发现用户本地路径中的远端 tmux

通过 fssh 登录远端 Linux 时，若 tmux 安装在 `~/.local/bin`，非登录 shell
找不到 tmux，导致会话列表为空。fssh 现在通过 `bash -lc` 执行远端 tmux
命令；会话列表获取失败时输出一行 warning，并继续进入创建或直接登录流程。

### 2026-07-28 — macOS Bash 3.2 无法展开空 SSH 参数数组

macOS 自带 Bash 3.2 在 `set -u` 下展开空的 `"${array[@]}"` 会报
`unbound variable`，导致不使用 PTY 的会话列表和 tmux 版本探测在调用 SSH
前失败。fssh 使用 Bash 3.2 兼容的条件数组展开；会话列表失败时保留 stderr，
并将原因合并到单行 warning 中。
