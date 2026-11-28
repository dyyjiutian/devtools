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

## 添加 SSH 主机

~~~bash
fssh -a deploy@192.0.2.10
fssh --add deploy@example.com:2222
fssh -a deploy@example.com:2222 --dry-run
~~~

目标支持 `user@hostname`、`user@IPv4` 和可选的 `:port`（1–65535，默认 22）；
暂不支持 IPv6。别名为 `user-hostname`，非默认端口追加 `-port`，例如
`deploy-example.com-2222`；已存在的别名（包括 Include 中的别名）不会覆盖。
添加后使用 `fssh deploy-example.com-2222` 连接。`--dry-run` 不修改本地或远程。

此操作需要 `ssh`、`ssh-keygen` 和 `ssh-copy-id`，不需要 fzf。它直接连接指定
地址，不使用现有 SSH config 中的代理配置；新增的 Host 也禁用继承的代理设置。
请确认目标、用户名及首次连接时的
主机指纹。`ssh-copy-id` 会提示输入远端账号密码，并把公钥写入远端账号的
`~/.ssh/authorized_keys`；密码不会保存到本地配置。默认复用
`~/.ssh/id_ed25519`，不存在时生成**无口令**私钥，请妥善保护该文件。部署后
验证密钥登录，通过后才更新 `~/.ssh/config`，并备份已有配置到
`~/.ssh/config.bak.*`。修改的配置目录权限为 700，配置文件权限为 600。

回滚时可将备份恢复到 `~/.ssh/config`（或删除新增的 Host 块）；如需撤销远端
授权，登录目标账号，从 `~/.ssh/authorized_keys` 中删除对应公钥。部署成功但
登录验证或本地写入失败时，远端公钥可能已存在，需按上述方式手动撤销。

## 真实 SSH 容器测试

L3 测试使用 Docker 构建临时 Ubuntu 客户端和两个 SSH 服务端，在隔离网络中
使用随机密码进行真实公钥部署及登录。覆盖首次添加、重复添加、多 IP、不同端口、
已有公钥和错误密码；不映射宿主端口，退出时清理容器、网络与测试镜像。
需要 Docker daemon、网络（构建时下载镜像和软件包）、Bazel 和宿主机 `openssl`：

~~~bash
bazel test --config=l3 //tools/ssh:fssh_real_ssh_e2e_test
~~~

也可在仓库根目录直接运行（无需 Bazel）：

~~~bash
bash tools/ssh/tests/fssh_docker_test.sh tools/ssh/tests/Dockerfile.ssh \
  tools/ssh/tests/fssh_docker_client.sh tools/ssh/fssh.sh
~~~

## Issues

### 2026-11-27 — fssh 不能新增 SSH 主机和配置免密登录

**表象**：只能选择已有 Host，无法从账号与地址直接建立免密连接。
**根因**：fssh 没有公钥部署和 Host 配置入口。
**解法**：使用 `fssh -a user@host[:port]` 部署并验证公钥后写入配置；详见上文的安全与回滚说明。

### 2026-08-23 — fssh 连 Mac 时找不到 Homebrew tmux

**表象**：远端 Mac 已安装 `/opt/homebrew/bin/tmux`，fssh 仍报 `tmux not available` / `command not found`。

**根因**：远端通过 `bash -lc` 跑 tmux。macOS 默认登录壳是 zsh，Homebrew 的 PATH 写在 `~/.zprofile`，`bash -lc` 不会读它。

**解法**：在远程执行 tmux 前把 `/opt/homebrew/bin`、`/usr/local/bin`、`$HOME/.local/bin` 追加到 PATH；`$PATH` / `$HOME` 在远端展开，不写入本机路径。

### 2026-08-17 — `fssh --help` 在 `set -e` 下以 1 退出

**表象**：L1 `//tools/ssh:ssh_*_test` 在 `setup --help` 之后立刻失败，`fssh --help` 无输出错误。

**根因**：EXIT trap 里 `reset_terminal` 用 `[[ ... ]] || return`。未进入交互会话时 `[[` 失败，`return` 带着状态 1，覆盖了 `show_help` 的 `exit 0`。

**解法**：改为 `return 0`。

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
