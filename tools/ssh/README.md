# SSH 工具

优化 SSH 客户端连接复用、KeepAlive，并提供 fzf 驱动的 fssh 远程会话选择器。

~~~bash
bash tools/ssh/setup.sh --help
bash tools/ssh/setup.sh --dry-run
bash tools/ssh/fssh.sh --help
~~~

依赖 ssh 和 fzf；脚本会备份并更新 ~/.ssh/config。
