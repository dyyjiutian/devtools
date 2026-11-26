# tmux agent 窗口状态设计

## 目标

在本机默认 tmux server 上跑一个后台进程，大约每几秒看一遍每个 window 的当前 pane。进程树里有 Claude、Codex 或 Cursor Agent 时，把这一轮的状态写进该 window 的选项 `@agent_state`，由状态栏画成带颜色的标记，用来在多个 window 并行时一眼区分谁还在跑、谁在等确认、谁做完了、谁失败了。

## 决策摘要

| 项 | 选择 |
|---|---|
| 程序 | `terminal/tmux/tmux-daemon.sh`，子命令 `start`、`stop`、`status`，另有测试用的 `--once` |
| 范围 | 本机默认 tmux server 的每个 session、每个 window 的当前 pane。不进根入口 `setup.sh --all`，也不由 `tmux.conf` 自动启动 |
| 间隔 | `start --interval <秒>`，正整数，默认 3。不写配置文件 |
| 谁被标记 | 进程树中有 `claude`、`codex`、`cursor-agent`（按进程名或命令行首段的文件名认，Cursor Agent 的进程名实际是 `MainThread`）；名字仅为 `agent` 时，命令行能看出是 Cursor Agent 才算。其它程序不标记 |
| 状态 | window 选项 `@agent_state`：`busy` 进行中、`wait` 等确认、`done` 做完、`fail` 失败。还没提问、进程树里没有 agent 时取消该选项。窗口名不改 |
| 显示 | `terminal/tmux/tmux.conf` 的 `@agent-status` 画在窗口序号前：黄 `●` 进行中，整个标签红底 `?` 等确认，绿 `✓` 做完，红 `✗` 失败；颜色取自现有 Catppuccin 配色。改选项后 tmux 立即重画状态栏 |
| 判断 | daemon 读 pane 最新输出的末尾一小段。不使用 iTerm2 / Ghostty 的 OSC 上报，不看 copy mode 翻到的那一屏 |
| 优先级 | 确认提示盖过进行中；进行中盖过屏幕上方的旧错误。认不出时保持该窗口当前状态；第一次认不出不设状态 |
| 做完标记 | 保留到下一轮开始或 agent 退出；切到该窗口看过不清除 |
| 写入失败 | 某个 window 设选项失败则跳过，其余继续 |
| 单实例 | 同一默认 server 只能有一个。再次 `start` 退出并说明已在运行 |
| 手动停止 | `stop` 先确认 daemon 已退出，再取消各 window 的 `@agent_state`，agent 仍在跑也清 |
| 被杀掉 | 不是执行 `stop` 时不做清理。下次 `start` 按当时画面重算 |
| 静默 | 不发通知、不响铃。pane 内容不写日志。只连本机默认 socket，不 SSH |
| tmux 未运行 | daemon 保持运行，下一次间隔再试 |

## 方案 / 边界

入口是 `terminal/tmux/tmux-daemon.sh`。`start` 放入后台并立刻做一轮，之后按间隔循环。`status` 只打印是否在跑、pid、间隔秒数，不打印 pane 内容。`--once` 只做一轮后退出，给测试用，不放入后台。

每一轮对每个 window：

1. 看当前 pane 的进程树。没有目标 agent 时取消 `@agent_state`。
2. Ctrl-Z 之后前台变成 shell 也一样：进程树里还有挂起的 agent，就保持 `busy`。
3. 有 agent 时，只读历史最末尾的固定行数（相对活的底部，不是 copy mode 视口）。三家 CLI 各有一小张可见特征表，放在脚本里；测试夹具使用同一组字符串。按下面顺序归类，命中即停：
   - 画面是等你确认（批准命令或确认计划）→ `wait`
   - 画面仍是进行中 → `busy`
   - 这一轮已停住，且最近结果是失败 → `fail`
   - 已经提问过，这一轮做完并停在输入处 → `done`
   - 还没提问（欢迎或空输入区，上面没有完成的一轮）→ 取消状态
   - 对不上特征表 → 不改当前状态
   - 「等确认」和「进行中」只看可见屏幕（最后 `pane_height` 行），滚到上方历史里的旧状态行不算。其余三种从最近 120 行历史里找，最靠下的那一条为准：上一轮报错之后又做完一轮算 `done`；同一 pane 里旧会话下面出现新 CLI 的欢迎头算还没提问。
   - 被用户中断的一轮（Codex `■ Conversation interrupted`、Claude `What should Claude do instead`）算失败 `fail`。
   - 特征表按 Claude Code 2.1、Codex 0.169、Cursor Agent 2026.11 的真实画面实测；Cursor Agent 的确认框取自安装包字符串，未实测。
4. 「这一拍没有新输出」本身不是进行中。三十秒任务中间屏幕停住时，要么画面上仍有进行中特征，要么窗口已经是 `busy` 且这一屏认不出结束态，两种都保持 `busy`。空会话不会因为没变化就被标成进行中。
5. 当前状态和要写的状态相同时不调用 tmux，重复轮询幂等。

状态不写进窗口名，因此 tmux 的 `automatic-rename`、按窗口名查找的脚本和 tmux-resurrect 保存的名字都不受影响；名字太长被截断时，序号前的标记仍然可见。没有加载新版 `tmux.conf` 时，daemon 照常写选项，但状态栏上看不到标记。

`stop` 的顺序是：先让正在跑的 daemon 退出，确认进程已经没了，再扫描窗口并取消 `@agent_state`。进程停不掉时 `stop` 失败，并且不去改选项，避免和仍在跑的循环抢写。daemon 自己不在退出时清理；清理只发生在 `stop` 子命令里。因此 `SIGKILL` 或崩溃会留下标记。daemon 忽略 `SIGHUP`，收到 `SIGTERM` 时会打断等待中的 `sleep` 立即退出。

脚本保持 Bash 3.2 与 `set -euo pipefail`，不用 Bash 4 的关联数组；进程树遍历和画面归类各用一次 awk。pid 文件可用环境变量改到临时目录，测试不写死本机路径。

不解析 OSC 21337 / OSC 133，不把状态写到外层终端标签。不提供按 window 关闭监控的开关。不记录状态历史。

## 测试要点

- **层级：** L1 场景测试足够。不需要 L2 Docker，也不需要 L3 真装或真实的三家 CLI。
- **方法：** `terminal/tmux/tests/tmux_daemon_suite.sh` 用 PATH 上的假 `tmux` 喂 `list-panes`、进程树、`capture-pane` 末尾文本，并记录 `set-option`；出现 `rename-window` 等其它调用即失败。用 `--once` 跑一轮，避免真的 sleep。覆盖：三家真实画面的四种状态与空会话、静默仍为进行中、确认盖过进行中、旧错误在上方但新一轮在跑仍为进行中、滚出屏幕的旧状态行不算、旧会话下的新欢迎头、shell 前台但进程树里有挂起的 agent、进程树没有 agent 时取消状态、`make` / `tail` / 无关的 `agent` 不标记、真实进程形态（`MainThread`、macOS 全路径进程名）、认不出时不改、重复轮询不重复写、一个 window 写入失败不影响其它、第二次 `start` 退出、`stop` 在进程退出后清掉全部状态、后台启动后立即可见且 `stop` 不等间隔、默认间隔 3、tmux 不存在时一轮空转、`tmux.conf` 画出四种状态、`--help` 与未知参数。
- **环境：** Bazel L1 profile：`macos`、`linux_ubuntu`、`linux_alinux3`、`linux_alinux4`。无 Docker、无网络、无 sudo，不连接用户正在用的 tmux。
- **特别注意：** Bash 3.2；`stop` 的清理发生在 daemon 确认退出之后；测试日志和输出里不出现喂进去的 pane 正文。
- **完成证据：** `bash -n terminal/tmux/tmux-daemon.sh`；`bazel test //terminal/tmux:tmux_daemon_macos_test //terminal/tmux:tmux_daemon_linux_ubuntu_test //terminal/tmux:tmux_daemon_linux_alinux3_test //terminal/tmux:tmux_daemon_linux_alinux4_test`；`git diff --check`。

## 非目标

- 不驱动 iTerm2 / Ghostty 标签上的点或副标题
- 不监控默认 server 以外的 tmux socket，也不通过 SSH 管理远程 tmux
- 不在 daemon 被杀掉时保证标记已经清掉
- 不区分「刚打开」和「上一轮已做完」以外的更多状态，也不记录历史状态
- 不把该命令挂进 `setup.sh --all` 或 tmux 配置的自动启动
