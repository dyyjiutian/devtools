# tmux

安装 tmux 3.7b、部署 tmux.conf 并配置 TPM 插件。

~~~bash
bash terminal/tmux/setup.sh --help
bash terminal/tmux/setup.sh --dry-run
bash terminal/tmux/setup.sh --install-bin-only
bash terminal/tmux/setup.sh --upgrade
bash terminal/tmux/setup.sh --upgrade --dry-run
bash terminal/tmux/setup.sh --upgrade --install-bin-only
~~~

Linux 可能从源码构建；macOS 使用 Homebrew。配置以复制方式写入 `~/.tmux.conf`（覆盖前备份已有普通文件）。

复制模式 `y`：macOS 走 `pbcopy`；Linux 启用 `set-clipboard on`（OSC52），便于 SSH 远端复制到本机剪贴板。

默认（不带 `--upgrade`）：脚本只检测当前 tmux 版本是否已满足目标版本（`TMUX_VERSION`，默认
3.7b）。已满足则跳过安装/编译直接部署配置；缺失或过旧则仅警告并提示使用 `--upgrade`，不会
强制重新编译或移除现有 tmux，仍会继续部署 `~/.tmux.conf` 与 TPM 插件。

带 `--upgrade`：优先尝试包管理器升级（macOS 用 `brew`；Linux 依次尝试 `apt-get` /
`dnf` / `yum`），若升级后仍不满足目标版本，回退到源码编译安装到 `TMUX_PREFIX`（默认
`~/.local`），并移除过旧的发行版包避免 PATH 冲突。可与 `--dry-run`、`--install-bin-only`
组合使用。

## Agent 窗口状态

`tmux-daemon.sh` 轮询本机默认 tmux server，把当前 pane 里 Claude、Codex、Cursor Agent 的状态写进窗口选项 `@agent_state`，状态栏在窗口序号前画出标记。窗口名不改。

~~~bash
bash terminal/tmux/tmux-daemon.sh start
bash terminal/tmux/tmux-daemon.sh start --interval 5
bash terminal/tmux/tmux-daemon.sh status
bash terminal/tmux/tmux-daemon.sh stop
bash terminal/tmux/tmux-daemon.sh start --once
~~~

标记：黄色 `●` 进行中，整个标签红底 `?` 等你确认，绿色 `✓` 这一轮做完，红色 `✗` 这一轮失败。还没提问，或进程树里已经没有 agent，不显示标记。手动 `stop` 会清掉这些标记；进程被杀掉时不会。默认每 3 秒看一遍。daemon 不随 tmux 或 `setup.sh --all` 自动启动。

标记由 `tmux.conf` 里的 `@agent-status` 画出。已有的 `~/.tmux.conf` 是旧版时，重新运行 `bash terminal/tmux/setup.sh` 部署（会先备份），然后执行 `tmux source-file ~/.tmux.conf`。

判断依据是 pane 画面上的固定文字（脚本顶部的 `SCREEN_MARKERS`），按 Claude Code 2.1、Codex 0.169、Cursor Agent 2026.11 实测。CLI 升级改了界面文字后，状态可能停在上一次的标记；用 `tmux capture-pane -p -t <pane>` 看新画面，更新这张表和 `tests/tmux_daemon_suite.sh` 里的夹具。

## Issues

### 2026-07-28 — setup 将 tmux.conf 软链到仓库路径

**问题表象**

- `setup.sh` 用 `ln -sf` 把 `~/.tmux.conf` 指到仓库内文件，依赖本机 worktree 路径；移动/删除仓库后配置失效。

**根因**

- 部署策略选择了软链而非复制。

**解法**

- 改为备份已有普通文件后 `cp` 覆盖；若目标已是软链则先删除再复制，避免写穿源文件。
- 重新执行：`bash terminal/tmux/setup.sh`（或仅配置路径时 source 后调用 `deploy_config`）。

### 2026-08-17 — GitHub macos-26 E2E 里 brew 报 sorbet-runtime LoadError

**表象**：`tmux_ops_macos_e2e_test` 找到 brew 后立刻失败：`cannot load such file -- sorbet-runtime`。

**根因**：E2E 把 `HOME` 指到临时目录，Homebrew bootsnap 缓存失效。

**解法**：`run_e2e_test.sh` 设置 `HOMEBREW_NO_BOOTSNAP=1`，并把 runner 的 Homebrew cache 指回宿主机 HOME。

### 2026-08-17 — macOS E2E 把 pbcopy yank 误判为失败

**表象**：`tmux_ops_macos_e2e_test` 安装成功后断言 `copy-mode-vi y` 含 `copy-selection`，实际绑定是 `copy-pipe-and-cancel pbcopy`。

**根因**：ops suite 按 Linux 的 `copy-selection` 检查；`tmux.conf` 在 Darwin 上走 pbcopy。

**解法**：ops suite 按 `uname` 分别断言 Darwin `copy-pipe-and-cancel` 与 Linux `copy-selection`。

### 2026-07-30 — 无 `--upgrade` 时对已满足/过旧版本的处理不一致

**问题表象**

- 旧版 `install_tmux` 仅以“是否精确等于 `TMUX_VERSION`”判断是否需要安装，导致已经更新
  （高于目标版本）的 tmux 仍会被强制走一遍移除发行版包、编译依赖安装、源码构建的完整流程；
  而版本过旧或缺失时同样会静默触发同一套重量级流程，用户无法用轻量方式仅部署配置。

**根因**

- 版本判断使用字符串精确匹配而非“>=目标版本”比较，且没有区分“安装”与“升级”两种意图，
  所有路径共用同一个强制安装分支。

**解法**

- 新增 `--upgrade` 标志：不带该标志时仅按 `>=` 比较当前版本，已满足则跳过安装/编译；
  缺失或过旧则只警告并提示 `--upgrade`，仍照常部署配置与 TPM 插件。
- 带 `--upgrade` 时按 vim 模块的模式优先走包管理器升级，仍不足再回退源码编译到
  `TMUX_PREFIX`。
- 复测：`bash terminal/tmux/setup.sh --dry-run --install-bin-only`（无 `--upgrade`，
  应跳过强制编译）与 `bash terminal/tmux/setup.sh --upgrade --dry-run --install-bin-only`
  （应显示包管理器与源码编译两级回退意图）。
