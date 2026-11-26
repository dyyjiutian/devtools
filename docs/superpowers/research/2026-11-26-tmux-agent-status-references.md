# tmux agent 窗口状态：已有方案对照

这篇笔记回答：已经决定用本机 daemon、按每个 tmux window 的当前 pane 改窗口名时，有哪些可以对照的现成方案。对照范围是 tmux 自己的改名、抓屏、活动标记和格式；iTerm2 的 Session Status（OSC 21337）与 Shell Integration（OSC 133）；Ghostty 的 OSC 133、ConEmu 进度（OSC 9;4），以及它是否实现 OSC 21337；Claude Code、Codex CLI、Cursor Agent CLI 是否自己发出终端状态。已决定的后缀和范围不在这里重做。

每条事实旁边是拥有该事实的手册、文档或源码。打不开的实现不写成结论。

## tmux：`rename-window`、`allow-rename`、`automatic-rename`

用户在状态栏的窗口列表里看到窗口名。tmux 把名字和标题分开：窗口和 session 有名字，只有 pane 有标题；窗口没有自己的标题，所谓窗口标题就是当前 pane 的标题。状态栏默认从左到右是 session 名、窗口列表、当前 pane 标题、时间。窗口列表默认是序号、名字，以及有则附加的标记。

名字的三个来源：

1. 创建时的参数，例如 `new-window -n`。
2. 程序发出的 `\033k名称\033\\`。这只在 `allow-rename` 打开时生效。
3. `automatic-rename` 打开时，用 `automatic-rename-format` 自动改名。

当前源码里的默认值：`automatic-rename` 为开（`default_num = 1`），格式是 `#{?pane_in_mode,[tmux],#{pane_current_command}}#{?pane_dead,[dead],}`；`allow-rename` 为关（`default_num = 0`）。因此默认情况下，pane 里的程序不能用转义序列改窗口名，tmux 自己会把窗口名改成当前命令名；pane 处于 copy mode 等 mode 时名字变成 `[tmux]`，pane 进程已经退出时在名字后加上 `[dead]`。

`rename-window` 把目标窗口改成给定的新名字。手册写明：某个窗口在创建时指定了名字，或者之后用 `rename-window` 或上述转义序列改过名，这个窗口的 `automatic-rename` 会被关掉。

谁发出信号：用户或客户端执行 `rename-window`；或者 pane 里的程序在 `allow-rename` 打开时发转义序列；或者 tmux 自己按格式改名。谁画出来：tmux 把 `window_name` 画进状态栏的窗口列表。粒度是每个 tmux window，同一 session 里多个 window 各有名字。它不表示「这一轮在跑、在等确认、成功或失败」，只表示一个名字字符串，默认来自前台命令名。

来源：<https://man.openbsd.org/tmux>（NAMES AND TITLES、STATUS LINE、`rename-window`、`automatic-rename`）；<https://github.com/tmux/tmux/blob/master/options-table.c>（`allow-rename`、`automatic-rename`、`automatic-rename-format`）。

## tmux：`capture-pane` 读活的底部，而不是 copy mode 视口

`capture-pane` 抓 pane 内容。`-p` 打到标准输出。`-S` / `-E` 用行号：0 是可见区域的第一行，负数进入 history；`-S -` 是 history 开头，`-E -` 是可见区域末尾。不给 `-S` / `-E` 时只抓可见内容。

源码里，不带 `-M` 时用的是 `wp->base.grid`。行号相对这块 grid 的 `hsize`：缺省起点就是 `hsize`，也就是这块 grid 的可见区顶部，终点是可见区最后一行。copy mode 是 pane 的一个 mode。只有带 `-M`，并且当前 mode 提供 `get_screen` 时，才改抓 mode 自己的 screen。因此不带 `-M` 的抓取不跟着 copy mode 翻到的那一屏走。

备用屏幕（alternate screen）是另一件事。进入时，tmux 把当时可见的若干行复制到 `saved_grid`，再清掉活动 grid 的可见区域，并关掉这块 grid 的 history 更新；退出时再把 `saved_grid` 拷回去。`capture-pane -a` 读的是 `saved_grid`（没有则报 no alternate screen）。不带 `-a` 读的是活动 grid，也就是备用屏幕打开时程序正在往上画的那一块。手册把 `-a` 说成使用 alternate screen；上面这段以 `screen_alternate_on` 和 `cmd_capture_pane_history` 的分支为准。

谁发出信号：没有。这是 tmux 客户端来读。谁画：不画，只输出文本。粒度是指定的那一个 pane。它不分类状态，也不改窗口名。

来源：<https://man.openbsd.org/tmux>（`capture-pane`）；<https://github.com/tmux/tmux/blob/master/cmd-capture-pane.c>；<https://github.com/tmux/tmux/blob/master/screen.c>（`screen_alternate_on` / `screen_alternate_off`）。

## tmux：`pane_current_command` 不是进程树

`#{pane_current_command}` 由 `format_cb_current_command` 生成：先调用 `osdep_get_name(wp->fd, wp->tty)`，空了再退回 pane 的 argv，再退回 shell，然后交给 `parse_window_name`。`parse_window_name` 的函数体这次没有打开，所以这里不描述它如何裁剪字符串。

Linux 的 `osdep_get_name` 用 `tcgetpgrp` 取 pane tty 的前台进程组，再读 `/proc/<pgrp>/cmdline`，遇到第一个 NUL 就停。这是前台进程的 argv0，不含参数，也不沿着父进程或子进程往下找。macOS 同样先 `tcgetpgrp`，再取该 pid 的 `pbsi_comm`（短命令名），不是完整命令行。

`#{pane_pid}` 打印的是 pane 结构上保存的 `wp->pid`，不是这次 `tcgetpgrp` 的结果。`#{pane_dead}` 在 `wp->fd == -1` 且带 `PANE_STATUSREADY` 时为 1。`#{pane_dead_status}` 只在进程已退出（`WIFEXITED`）时给出退出码。这是 pane 里 tmux 拉起的那个进程结束了，不是 shell 里某条命令失败，也不是 agent 一轮对话失败。

前台被 Ctrl-Z 停住、shell 回到前台时，`tcgetpgrp` 看到的是 shell。挂起的 agent 仍在进程树里，但 `pane_current_command` 不会再是那个 agent。

谁发出信号：没有，tmux 自己读前台进程。谁画：只有把它放进 `automatic-rename-format`、`window-status-format` 或其它格式时才会出现在状态栏。粒度可以是每个 window 的当前 pane。它不区分进行中、等待、成功、失败，也看不到「进程名是 `agent`，但参数表明它是 Cursor Agent」。

来源：<https://github.com/tmux/tmux/blob/master/format.c>（`format_cb_current_command`、`format_cb_pane_pid`、`format_cb_pane_dead`、`format_cb_pane_dead_status`）；<https://github.com/tmux/tmux/blob/master/osdep-linux.c>；<https://github.com/tmux/tmux/blob/master/osdep-darwin.c>。

## tmux：`monitor-activity`、`monitor-silence`、`monitor-bell`

这三个是窗口选项。`monitor-activity` 默认关，有输出的窗口在状态栏高亮。`monitor-bell` 默认开，收到铃的窗口高亮。`monitor-silence` 默认 0，表示关闭；设成正数秒后，沉默达到该间隔的窗口高亮。对应的 session 选项 `activity-action`、`bell-action`、`silence-action` 决定铃或消息落在哪些窗口；`visual-activity`、`visual-bell`、`visual-silence` 可以把铃换成状态栏消息。还有 hook：`alert-activity`、`alert-bell`、`alert-silence`，以及更细的 `pane-activity`、`pane-bell`。

状态栏窗口名后面的标记是：`*` 当前窗口，`-` 上一个窗口，`#` 有活动且正在监控活动，`!` 有铃且正在监控铃，`~` 沉默达到 `monitor-silence`，`M` 含有 marked pane，`Z` 当前 pane 被 zoom。有铃、活动或沉默警报时，窗口名以反色显示。默认的 `window-status-format` 和 `window-status-current-format` 都是 `#I:#W#{?window_flags,#{window_flags}, }`，也就是序号、窗口名、这些标记。

谁发出信号：pane 的输出、BEL，或一段时间没有输出。谁画：tmux 画在每个 window 的状态栏项上。它不表示命令仍在跑、一轮已结束或退出码非零。沉默只说明这段时间没有新输出。

来源：<https://man.openbsd.org/tmux>（`monitor-activity`、`monitor-bell`、`monitor-silence`、STATUS LINE、HOOKS）；<https://github.com/tmux/tmux/blob/master/options-table.c>（上述选项及两个 `window-status-*-format` 的默认字符串）。

## tmux：不改窗口名时，还能在哪里放状态

窗口名是 `window_name`。下面这些是别的槽，tmux 不会把它们自动抄进每个窗口名。

- Pane 标题。程序在 `allow-set-title` 打开时发 OSC 2（`\033]2;...\033\\`）或 OSC 0（`\033]0;...\033\\`）。当前源码里 `allow-set-title` 默认开。也可以 `select-pane -T`。格式变量是 `#{pane_title}`（别名 `#T`）。状态栏默认把当前 pane 的标题放在右侧引号里，窗口列表本身仍显示窗口名。
- 外层终端标题。`set-titles` 默认关。打开后，tmux 用 `set-titles-string` 设置客户端所在终端的标题，默认字符串是 `#S:#I:#W - "#T" #{session_alerts}`。这是当前客户端的一条标题，跟着当前窗口走，不是每个后台 window 各一条。
- 用户选项。名字以 `@` 开头，可以按 window 或 pane 用 `set-option` 设成任意字符串，再写进 `window-status-format`。这是 tmux 命令设的，不是 pane 里一条标准改名转义。手册列出的由程序设置的名字和标题，是上面的 OSC k 与 OSC 0/2。
- 状态栏刷新。`status-interval` 默认 15 秒重画状态栏；设为 0 则不按间隔重画。格式里的 `#()` 由 tmux 用 `/bin/sh` 跑，不等命令结束，最多约每秒取一次最近一行输出。

谁画：都是 tmux。除了用户选项可以被写进窗口列表格式以外，这些都不等于「每个 window 的名字末尾有一个状态后缀」。pane 标题和外层标题都只有当前附着的那一个窗口会占住外层终端标签。

来源：<https://man.openbsd.org/tmux>（NAMES AND TITLES、`allow-set-title`、`set-titles`、`set-titles-string`、`status-interval`、FORMATS 里的 `#()` 与用户选项）；<https://github.com/tmux/tmux/blob/master/options-table.c>（`allow-set-title`、`set-titles`、`set-titles-string`）。

## tmux：OSC 133 的 hook，不改窗口名

手册有三条与 OSC 133 相关的 hook：`pane-shell-prompt`（提示符开始）、`pane-command-started`（命令开始）、`pane-command-finished`（命令结束）。`capture-pane -F` 能标出提示行（`P`）和输出行（`O`）。`-R` 的诊断输出里，带 OSC 133 标记的行会打出 `exit_status` 等字段。copy mode 也有复制或打开「当前 OSC 133 命令输出」的命令。

这些 hook 默认不会去改窗口名。要变成窗口名，得自己写 `set-hook`。而且信号来自 pane 里的程序或 shell 发出的 OSC 133，不是 tmux 从进程树推断的。全屏 TUI 若不发 OSC 133，这些 hook 不会按「每一轮对话」触发。

来源：<https://man.openbsd.org/tmux>（HOOKS、`capture-pane`、copy mode 的 OSC 133 命令）；<https://github.com/tmux/tmux/blob/master/cmd-capture-pane.c>（`-F` 的 `P`/`O`，以及 `-R` 打印的 `osc133` 字段）。

## iTerm2：Session Status（OSC 21337）

iTerm2 把一段短状态画在该 session 的标签上：副标题文字、一个色点、副标题颜色。文档的用途说明是：同时开很多长时间 session（例如多个 coding agent）时，不用切过去就能看出哪个在工作、哪个在等你、哪个空闲。文档举的副标题例子是 `Working`、`Waiting`，触发器的建议值是 `Working`、`Waiting`、`Idle`。Session Status 工具按优先级排序，默认是 waiting，然后 working，然后 idle。Cockpit 按 Waiting、Working、Idle 分组。

程序用下面的序列设置，空值清除该项，未知键被忽略：

```text
OSC 21337 ; status=文字 ; indicator=#RRGGBB ; status-color=#RRGGBB ; detail=文字 ST
```

`detail` 出现在 Session Status 工具和 Cockpit 里，文档没有说它画在标签上。另外两条路径是 `it2 session set-status`，以及 Profiles → Advanced → Triggers 里的 Set Tab Status。

谁发出：pane 里的程序、`it2`，或一条触发器。谁画：iTerm2，画在它自己的 session 标签上。一个 iTerm2 session 是一个标签（或分屏里的一块），不是 tmux 的一个 window。专有转义码那一页写明：这些序列在 tmux 或 screen 里可能不能正常工作。文档没有把 OSC 21337 说成 tmux 窗口名。

来源：<https://iterm2.com/documentation-session-status.html>；<https://iterm2.com/documentation-escape-codes.html>（Session Status，以及文首对 tmux / screen 的限制）。

## iTerm2：Shell Integration（OSC 133）

Shell Integration 用 FinalTerm 的 OSC 133 标记提示符、用户输入的命令、命令输出和结束。`OSC 133 ; D ; 退出码 ST` 在命令执行之后表示结束；退出码 0 算成功，非 0 算失败，终端可以选择如何显示。iTerm2 实际画出来的是：每条提示符左边一个标记，默认是蓝色小三角；命令失败时标记变红，右键标记可以看到返回码。还可以对「下一个标记」设警报，命令回到提示符时弹出模态警报。

文档没有把 OSC 133 说成标签上的 Working / Waiting / Idle。那三个词属于上一节的 Session Status。

Shell Integration 默认不用于 tmux 或 screen。若要一起用，要在加载集成脚本之前设置 `ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX=1`。文档接着说：它和 tmux integration（`tmux -CC`）配合较好，和普通 tmux 界面则不是。这里的「较好」指的是 Shell Integration，文档没有写 OSC 21337 会因此变成每个 tmux window 一条。

谁发出：shell 集成脚本或会发 OSC 133 的 shell。谁画：iTerm2，画在该 session 的滚动区边缘和可选警报里。粒度是 iTerm2 session，不是 tmux 窗口列表。

来源：<https://iterm2.com/documentation-shell-integration.html>（Marks、Command status、Limitations）；<https://iterm2.com/documentation-escape-codes.html>（FTCS_COMMAND_FINISHED）。

## Ghostty：OSC 133

Ghostty 可以给 bash、elvish、fish、nushell、zsh 注入 shell integration。文档列出的界面效果是：光标停在提示符上时关闭窗口可以不再确认；新终端沿用上一个终端的工作目录；提示符按 shell 重画而不是重排；按住 Control（Linux）或 Command（macOS）三击选中一条命令的输出；提示符处光标变成竖条；`jump_to_prompt` 在提示符之间滚动；在提示符上 Alt/Option 点击移动光标。这些依赖提示符标记。配置参考写明 `cursor-click-to-move` 需要 OSC 133。

1.3.0 的发布说明写：命令结束通知使用 OSC 133，因此需要 shell integration，或 shell 自己发 OSC 133（例如 Fish、Nushell）。`notify-on-command-finish` 默认 `never`；`unfocused` 只在该 surface 没有焦点时通知；`always` 总是通知。`notify-on-command-finish-after` 默认 5 秒，短于这个时间不通知。动作默认包含 `bell`，`notify` 默认关。

谁发出：Ghostty 注入的 shell 集成，或 shell 自己的 OSC 133。谁画：Ghostty 的这个 surface（跳转、选择、通知），不是 tmux 窗口名。文档没有把 OSC 133 描述成标签上的进行中 / 等待 / 空闲三点。

来源：<https://ghostty.org/docs/features/shell-integration>；<https://ghostty.org/docs/config/reference>（`notify-on-command-finish`、`notify-on-command-finish-after`、`cursor-click-to-move`）；<https://ghostty.org/docs/install/release-notes/1-3-0>。

## Ghostty：ConEmu 进度（OSC 9;4）

Ghostty 把 OSC 9;4 画成每个分屏顶部的进度条。状态由 `s` 决定：0 不活动且值为 0；1 进行中，值为 `v`（0 到 100）；2 错误，`v` 有则更新、没有则保留；3 不确定，值不变；4 暂停，规则同 2。

协议本身看不出进度已经过期，例如进程没清掉进度就退出了。Ghostty 因此写死大约 15 秒超时，超时后清掉当前进度。文档建议发送方至少每秒更新一次，当作保活。1.2.0 的发布说明还写过：当时画的是终端顶部一条简单进度条，标签页标题、任务栏、Dock 上的进度留到以后。当前的 OSC 文档仍把可见效果写成每个分屏顶部的进度条，没有改口说已经画到标签上。

谁发出：pane 里的程序。谁画：Ghostty，画在它自己的 split 上。一个 tmux 客户端若占 Ghostty 的一整块 surface，这是那一块上的一条条，不是 tmux 每个 window 一条。它也没有「等用户确认」这个状态。

来源：<https://ghostty.org/docs/vt/osc/conemu>；<https://ghostty.org/docs/install/release-notes/1-2-0>。

## Ghostty 与 iTerm2 OSC 21337

Ghostty 当前的 OSC 解析器没有 21337 这个状态。数字 `2` 之后只接受 `;`（当作 OSC 2）、`1`（转到 21）或 `2`（转到 22）；其它数字走 `unknownOrInvalid`。解析器单独实现了 OSC 133（semantic prompt）、OSC 1337（iTerm2 的另一组专有序列）和 OSC 7501（program status）。

OSC 7501 不是 OSC 21337。解析器注释写：程序用它报告自己在做什么，例如 working，或正在等用户，也可以询问终端是否支持。1.4.0 发布说明写：libghostty 能解析 idle、working、done、blocked、failed，但 Ghostty 的 GUI 目前忽略它。libghostty 的 API 说明也写：怎么显示由调用方决定；回调是 NULL 时，对 `OSC 7501 ; ?` 的询问不回答，随后的报告被丢掉。因此即便程序在 Ghostty 里发出 OSC 7501，当前 GUI 也不会把它画成标签上的点或副标题。

来源：<https://github.com/ghostty-org/ghostty/blob/main/src/terminal/osc.zig>（状态机与 `program_status` 注释）；<https://ghostty.org/docs/install/release-notes/1-4-0>；<https://lib.ghostty.org/vt/struct_ghostty_terminal_program_status.html>；<https://lib.ghostty.org/vt/group__terminal.html>（`GHOSTTY_TERMINAL_OPT_PROGRAM_STATUS`）。

## Claude Code

官方终端配置写：终端若实现 OSC 7501 Program Status Protocol，可以显示每个交互式 Claude Code session 是在工作、在等你，还是已经做完。Claude Code 侧没有开关。需要 v2.1.295 或更新。在 tmux 里，Claude Code 向 tmux 询问是否支持，而不是向外层终端询问；`allow-passthrough` 不影响这次询问。文档因此建议把 session 开在 tmux 外面。后台 session 即使附着着也不向终端报这份状态。`CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1` 时，既不探测也不报告状态。

同一页写：终端报告支持该协议时，标签标题前面不再加 Claude Code 自己的状态字形，因为终端会自己显示状态；其它终端里标题前会有这个字形。这一页没有写出字形具体是哪个字符，也没有提到 OSC 21337。Claude Code 的程序源码没有作为公开树打开，所以这里不能断言它是否另外发送 OSC 21337。

tmux 相关的另一段是通知，不是窗口名：在 tmux 里要让桌面通知到达 Ghostty、Kitty 或 iTerm2，需要 `allow-passthrough on`，并且示例配置下，你没在看的那个 window 里的 pane 不会送出。这是外层终端的通知，不是 tmux 窗口列表上的后缀。

Hooks 是用户配置的命令，不是 Claude 画在 tmux 窗口名上的东西：

- `PermissionRequest`：Claude 正要为一次工具调用征求许可时运行。
- `Notification` 的 `permission_prompt`：终端里，许可提示出现后大约 6 秒且你看起来不在终端前才触发；要立刻知道，文档让用 `PermissionRequest`。
- `Notification` 的 `idle_prompt`：Claude 回应结束大约 60 秒、你没再打字、也没有后台 agent 在跑。
- `Stop`：主 agent 回应结束时运行；用户打断不会跑，API 错误走 `StopFailure`。

Hook 若要让 Claude 代发转义序列，走 JSON 的 `terminalSequence`。允许的只有 OSC 0/1/2（标题）、OSC 9（含 `9;4` 进度）、OSC 99、OSC 777 和 BEL。名单之外的序列会被忽略；文档点名拒绝 OSC 1337，也拒绝 CSI、OSC 8、OSC 52。OSC 21337 和 OSC 7501 不在这份允许名单里。Hook 在 tmux 里要把允许的序列送到外层终端，仍要 tmux 3.3 以上的 `allow-passthrough`；`on` 时只有 tmux 正在显示的 pane 能送出。

来源：<https://code.claude.com/docs/en/terminal-config>（See session status in your terminal、Configure tmux）；<https://code.claude.com/docs/en/hooks>（`terminalSequence`、`PermissionRequest`、`Notification`、`Stop`）。

## Codex CLI

Codex 的 TUI 把生命周期写成两类序列，见 `terminal_program_status.rs`：

- OSC 7501：`state=` 取 `idle`、`working`、`blocked`、`done`、`error`，并带 `app=codex`。`blocked` 再带 `kind=permission`、`question` 或 `auth`。清除时发送 `state=clear`。
- OSC 21337：仅当下面的条件成立时一并发送。标签文字把 Idle、Done、Error 都写成 `Idle`（点色 `#00d75f`），Working 写成 `Working`（`#ff9500`），Blocked 写成 `Waiting`（`#5f87ff`）。

是否发送由 `terminal_program_status_support` 决定。OSC 7501：标准输出是终端，并且若后端是 VTE，则版本未知或至少为 0.54（源码常量 `5400`）。这个判断没有看 multiplexer。OSC 21337 在 OSC 7501 的条件之上，还要求终端名是 iTerm2、`multiplexer` 为空、并且 `STY` 未设置。`detect_multiplexer` 在 `TMUX` 或 `TMUX_PANE` 非空时把 multiplexer 标成 tmux。因此在 tmux 里，这段代码不发 OSC 21337，但只要标准输出仍是终端且 VTE 条件通过，仍会发 OSC 7501。发出去的是写到 pane 标准输出的原始 OSC，这一文件没有包进 tmux 的 DCS passthrough。

标题是另一条路径。`set_terminal_title` 在标准输出是终端时写 OSC 0，以 BEL 结束（`ESC ] 0 ; 标题 BEL`），不写 OSC 2。它不检查 `TMUX`。只有 `STY` 存在（GNU screen）时才把标题收成 ASCII。标题字符串由调用方传入；这次没有打开选择标题正文的那个调用方，所以不记录标题里具体有哪些字。

官方配置文档里的通知又是一条路径：`tui.notifications` 可以按事件过滤，例子是 `agent-turn-complete` 和 `approval-requested`。`tui.notification_method` 为 `auto`、`osc9` 或 `bel`；`auto` 时优先 OSC 9 桌面通知，否则 BEL。`tui.notification_condition` 为 `unfocused` 或 `always`。源码里，终端名是 Ghostty、iTerm2、Kitty、Warp 或 WezTerm 时 `osc9` 为真；multiplexer 是 tmux 时 `dcs_passthrough` 为真。这是通知，不是 tmux 窗口名。

谁画 OSC 21337：iTerm2，画在它自己的 session 标签上，而且 Codex 只在没有 multiplexer 时发送。OSC 7501 在 tmux 里仍会写到 pane；Ghostty 1.4.0 的 GUI 忽略它。tmux 手册没有把 OSC 7501 定义成窗口名或窗口标记。

来源：<https://github.com/openai/codex/blob/main/codex-rs/tui/src/terminal_program_status.rs>；<https://github.com/openai/codex/blob/main/codex-rs/tui/src/terminal_capabilities.rs>（`terminal_program_status_support`、`NotificationCapabilities`）；<https://github.com/openai/codex/blob/main/codex-rs/terminal-detection/src/lib.rs>（`detect_multiplexer`）；<https://github.com/openai/codex/blob/main/codex-rs/tui/src/terminal_title.rs>；<https://developers.openai.com/codex/config-advanced>（`notify` 与 `tui.notifications`）。

## Cursor Agent CLI

官方配置把 `display.showStatusIndicators` 说明为打开终端标题上的状态指示，`/status-indicators` 用来切换。`notifications` 的说明是：agent 结束或需要输入时发送一条终端通知。更新日志里的桌面通知写的是：一轮结束，或 agent 被你挡住（批准、提问、sudo）时通知，终端包括 iTerm2、Ghostty、Warp、Kitty 和 Terminal.app，并带 tmux/screen passthrough，焦点在当前终端时会静音。终端设置页只把 tmux 写成会拦住 Shift+Enter，以及颜色检测要用 `tmux-256color`；没有写状态序列。

这些页面没有给出 OSC 21337、OSC 7501 或 OSC 0/2 的编号，也没有写在 tmux 里会不会停发。Cursor Agent CLI 的实现源码这次没有公开树可打开，所以编号和「是否在 multiplexer 里跳过」都不记。文档能确定的是：它谈的是终端标题和通知。tmux 默认窗口列表画的是窗口名和 `window_flags`，不是 pane 标题，也不是外层终端那一条标题。

来源：<https://cursor.com/docs/cli/reference/configuration>；<https://cursor.com/docs/cli/reference/slash-commands>；<https://cursor.com/docs/cli/changelog>（Desktop notifications，April 2026 一节）；<https://cursor.com/docs/cli/reference/terminal-setup>；tmux 窗口列表见 <https://man.openbsd.org/tmux> 与 <https://github.com/tmux/tmux/blob/master/options-table.c>。

## 对本功能的含义

已经决定的做法是：daemon 看每个 window 的当前 pane，用进程树判断是不是那三家 agent，再读活的底部画面，把 `+...`、`+?`、`+√`、`+×` 写进窗口名。下面只说明哪些现成方案可以当参考，哪些替不了「每个 tmux window 的名字」。

可以参考的部分：

- 改名用 `rename-window`，显示位置就是 tmux 状态栏里每个 window 已有的名字。这和「外层终端一个标签」不是同一条通道。
- 读画面用 `capture-pane` 且不要 `-M`。这样行号落在活动 grid 的可见区底部，不跟着 copy mode。备用屏幕打开时，不带 `-a` 读到的是活动 grid，也就是程序正在画的那一块。
- 认 agent 不能只用 `pane_current_command`。它只看前台进程组：Linux 是 argv0，macOS 是短命令名。shell 在前台时它就是 shell。默认自动改名因此也只跟得上前台命令，跟不上挂起的子进程，更看不出名为 `agent` 的进程是不是 Cursor Agent。
- `rename-window` 会关掉该窗口的 `automatic-rename`。daemon 一旦用它写过名字，tmux 就不会再按前台命令把这个窗口名改回去。`allow-rename` 默认关，只约束程序自己的 OSC k，不约束 `rename-window` 这条命令。
- 三家 CLI 已有的状态词，和四种后缀是同一类信息的不同画法：iTerm2 标签上的 Working / Waiting / Idle；Codex 在直连 iTerm2 时把 Working、Waiting、Idle 写进 OSC 21337，把 working、blocked、done、error 写进 OSC 7501；Claude Code 的文档把 OSC 7501 说成工作、等你、做完。它们都画在终端自己的 session 上，或只是写到 pane 里等终端来画。

替不了每个窗口名的部分：

- iTerm2 的 OSC 21337 和 OSC 133 都落在 iTerm2 session 上。专有序列在 tmux 里可能无效；OSC 133 要额外打开才进 tmux，并且文档说普通 tmux 界面并不合适。Ghostty 的解析器没有 OSC 21337。Ghostty 的 OSC 133 是提示符跳转和命令结束通知；OSC 9;4 是每个 Ghostty 分屏顶部的进度条，大约 15 秒不更新就清除，也没有「等确认」。
- Ghostty 能解析 OSC 7501，但 1.4.0 的 GUI 忽略它。Codex 在 tmux 里仍会写 OSC 7501，同时明确不写 OSC 21337。Claude Code 在 tmux 里改为询问 tmux，`allow-passthrough` 不改变这次询问。这些序列都不会变成 tmux 窗口列表里的名字。
- `monitor-activity`、`monitor-silence`、`monitor-bell` 只在窗口名后加 `#`、`~`、`!` 或反色。沉默不是「仍在跑」，活动也不是「这一轮的结果」。
- `pane_dead_status` 和 OSC 133 的退出码都不是 agent 一轮对话的成败。前者是 pane 进程退出；后者要程序自己发 OSC 133，tmux 默认也不据此改名。
- Pane 标题、`set-titles` 和外层终端通知，都是当前这一个客户端或当前这块终端表面的一条信息。用户选项和 `window-status-format` 可以在不改 `window_name` 的情况下多画一段字，但那是另一条格式，不是这次已经定下的窗口名后缀。

## 没有核实、因此没有写进结论的内容

- Claude Code 的程序源码。官方文档写了 OSC 7501、标题前的状态字形，以及 tmux 里改为询问 tmux。字形本身，以及是否另发 OSC 21337，文档没有写，源码也没有打开。
- Cursor Agent CLI 的实现源码。官方文档只写到「终端标题上的状态指示」和结束 / 需要输入时的通知，以及桌面通知可以穿过 tmux/screen。没有 OSC 编号，也没有「在 tmux 里停止发送」的条件。
- tmux 的 `parse_window_name` 函数体。只确认 `pane_current_command` 会调用它。Linux 上送进去的字符串在此之前已经是前台进程 cmdline 的第一段。
- Program Status 协议正文（libghostty 指向的那份规范页面）没有打开。OSC 7501 的状态名以 Ghostty 的发布说明、libghostty API 和 Codex 源码里实际写出的字符串为准。
