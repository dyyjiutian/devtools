# SSH 工具

优化 SSH 客户端连接复用、KeepAlive，并提供 fzf 驱动的 fssh 远程会话选择器。

~~~bash
bash tools/ssh/setup.sh --help
bash tools/ssh/setup.sh --dry-run
bash tools/ssh/fssh.sh --help
~~~

依赖 ssh 和 fzf；脚本会备份并更新 ~/.ssh/config。

## fssh 主机 / session 查询

`fssh` 无参数时打开全量 Host 选择器。带参数时对 SSH **Host 别名**（不含 `*?` 通配）做解析；会递归跟随 `~/.ssh/config` 中的 `Include`（相对路径按 OpenSSH 规则解析到 `~/.ssh/`，支持 `~` 与通配）：

1. 不区分大小写的精确匹配
2. 否则不区分大小写的子串匹配
3. 唯一命中直接连接；多个命中对候选开 fzf；零命中报错退出

`-t/--tmux <session>` 对远端 tmux session 名使用相同匹配规则（唯一命中跳过 fzf）；**必须同时给出 host 查询**，且与 `-n/--no-tmux` 互斥。

~~~bash
fssh dev              # 唯一 host → 再弹 session 菜单；多个 host → fzf
fssh prod -n          # 解析后 plain SSH（跳过 tmux）
fssh prod -t main     # 解析 host 后 attach session（唯一命中直连）
fssh prod -t ma       # session 子串唯一 → 直连；多个 → fzf；零命中报错
~~~

## Issues

### 2026-07-30 — fssh session 列表混入 nvm/npmrc 警告

远端通过 `bash -lc` 跑 `tmux list-sessions` 以补齐 PATH；登录式 Bash 会初始化
nvm，而与 `~/.npmrc` prefix 冲突时警告写在 stderr。原先 `2>&1` 把警告并进
stdout，fzf 菜单里出现 nvm 文案。现仅用 stdout 作为 session 名；失败时才把
stderr 拼进 warning。

### 2026-07-30 — Include 解析对每行 fork `tr`，list_hosts 变慢数秒

跟随 Include 后，`list_hosts` 对配置每一行 `printf | tr` 做关键字小写化；约 250
行时外部进程开销可达数秒，拖慢交互选主路径。现改为 Bash case 模式匹配
`Host`/`Include`（零 fork），并用 ~50 Host + 延迟 `tr` 夹具做 ≤1.5s 回归。

### 2026-07-30 — fssh 未跟随 Include，漏掉分文件里的 Host

`list_hosts` 原先只 grep 主配置 `~/.ssh/config`，`Include config.d/work` 等文件中的 Host 不会出现在 fzf / 查询匹配里。现已递归展开 Include（相对路径、`~`、glob），并继续排除带 `*?` 的通配别名。

### 2026-07-28 — fssh 无法发现用户本地路径中的远端 tmux

通过 fssh 登录远端 Linux 时，若 tmux 安装在 `~/.local/bin`，非登录 shell
找不到 tmux，导致会话列表为空。fssh 现在通过 `bash -lc` 执行远端 tmux
命令；会话列表获取失败时输出一行 warning，并继续进入创建或直接登录流程。

### 2026-07-28 — macOS Bash 3.2 无法展开空 SSH 参数数组

macOS 自带 Bash 3.2 在 `set -u` 下展开空的 `"${array[@]}"` 会报
`unbound variable`，导致不使用 PTY 的会话列表和 tmux 版本探测在调用 SSH
前失败。fssh 使用 Bash 3.2 兼容的条件数组展开；会话列表失败时保留 stderr，
并将原因合并到单行 warning 中。
