# SSH 工具

优化 SSH 客户端连接复用、KeepAlive，并提供 fzf 驱动的 fssh 远程会话选择器。

~~~bash
bash tools/ssh/setup.sh --help
bash tools/ssh/setup.sh --dry-run
bash tools/ssh/fssh.sh --help
~~~

依赖 ssh 和 fzf；脚本会备份并更新 ~/.ssh/config。

## fssh 主机查询

`fssh` 无参数时打开全量 Host 选择器。带参数时对 `~/.ssh/config` 的 **Host 别名**（不含 `*?` 通配）做解析：

1. 不区分大小写的精确匹配
2. 否则不区分大小写的子串匹配
3. 唯一命中直接连接；多个命中对候选开 fzf；零命中报错退出

~~~bash
fssh dev          # 唯一匹配 → 直连；多个 → fzf
fssh prod -n      # 解析后 plain SSH（跳过 tmux）
~~~

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
