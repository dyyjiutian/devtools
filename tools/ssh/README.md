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
