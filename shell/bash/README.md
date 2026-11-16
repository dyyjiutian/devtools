# Bash 配置

安装 ble.sh、zoxide、fzf 和 Starship，并幂等写入 ~/.bashrc 与 ~/.blerc。

~~~bash
bash shell/bash/setup.sh --help
bash shell/bash/setup.sh              # 完整安装
bash shell/bash/setup.sh install      # 同上
bash shell/bash/setup.sh install fzf  # 只装 fzf（仍写入完整 bashrc / blerc 配置块）
bash shell/bash/setup.sh list         # 列举插件与本机状态
bash shell/bash/setup.sh install -n   # 试运行
~~~

插件 ID：`blesh`（别名 `ble.sh`）、`zoxide`、`fzf`、`starship`。

Linux 安装优先使用 cache/ 中的二进制缓存。

`~/.blerc` 由本脚本用 marker 托管块维护，默认关闭 ble.sh 的命令执行摘要
（`[ble: elapsed ...]` / `[ble: exit ...]`）。用户自定义配置可写在 marker 外，重复运行只会替换托管块。

## 常见问题 (Issues)

### 2026-11-16 ls 不着色（Ghostty 等 TERM 与 /etc/DIR_COLORS.* 不匹配）

**现象**：在 Ghostty（`TERM=xterm-ghostty`）等终端中，`ls`、`ll` 输出目录、可执行文件时
没有颜色，且 `alias ls` 查不到别名。

**原因**：`/etc/profile.d/colorls.sh` 会按 `TERM` 选择 `/etc/DIR_COLORS.$TERM`、
`/etc/DIR_COLORS.256color` 或 `/etc/DIR_COLORS`。`/etc/DIR_COLORS.256color` 带有
`TERM *256color*` 行，`dircolors` 在 `TERM=xterm-ghostty` 下匹配失败，输出空的
`LS_COLORS`；colorls.sh 随后命中 `[ -z "$LS_COLORS" ] && return`，跳过了文件末尾的
`alias ls='ls --color=auto'`。没有该别名时 GNU ls 默认按 `--color=never` 输出。

**本脚本的处理**：Linux 上托管的 `~/.bashrc` 配置块兜底：`LS_COLORS` 为空时用
`dircolors -b` 补默认配色，并定义 `ls`、`ll`、`la`、`l.` 四个带 `--color=auto` 的别名。
已装过的环境重跑 `bash shell/bash/setup.sh install`，再 `source ~/.bashrc` 或开新终端。

**验证**：

~~~bash
alias ls          # 应输出 alias ls='ls --color=auto'
ls -d /tmp        # 目录名应带颜色
~~~

### 2026-08-06 命令执行后出现 [ble: elapsed ...] / [ble: exit ...] 摘要

**现象**：启用 ble.sh 后，每条命令后可能出现耗时、CPU 占用或非零退出码提示，例如
`[ble: elapsed 16.270s (CPU 101.5%)]`、`[ble: exit 127]`。

**原因**：这是 ble.sh 默认的 `exec_elapsed_mark` / `exec_errexit_mark` / `exec_exit_mark`。

**本脚本的处理**：安装时幂等写入 `~/.blerc` 托管块，将上述三项设为空以关闭摘要。
已装过的环境重新运行 `bash shell/bash/setup.sh`（或 `install`）即可更新；然后
`source ~/.bashrc` 或开新终端。

**手动开关**（在交互式 ble 会话中立刻生效，或写入 `~/.blerc` marker 外）：

~bash
# 关闭
bleopt exec_elapsed_mark=
bleopt exec_errexit_mark=
bleopt exec_exit_mark=
# 恢复默认示例
# bleopt exec_elapsed_mark='elapsed %s (CPU %s%%)'
# bleopt exec_errexit_mark='exit %d'
~

### 2026-07-27 方向键左右移动时会"按词跳"，无法逐字符移动

**现象**：装完 ble.sh 后，命令行里按左/右方向键不是一格一格移动，而是**整词跳过**；
典型可复现场景 `find ./ -name ''`——光标无法停到两个引号中间，`'    '` 里的多个空格
也会被整体跳过。`ble-detach`（退回原生 readline）后一切正常。

**原因**：ble.sh 会导入 readline 的 `~/.inputrc` 键绑定。若某些环境的 `~/.inputrc`
把**应用光标模式下的普通方向键** `\eOD` / `\eOC` 误绑成了 `backward-word` / `forward-word`
（常见于照抄 macOS 的 "Alt/Option+方向键按词跳" 配置），ble.sh 会把 `\e[D`(CSI D) 与
`\eOD`(SS3 D) 统一成同一个 `left` 键，导致**所有**左/右方向键都变成按词移动。纯 readline
平时走 `\e[D` 且不合并这两种序列，所以看不出问题。

**本脚本的处理**：写入 `~/.bashrc` 的 `source ble.sh` 行已带 `--noinputrc`，让 ble.sh
**不重建 readline 的键绑定**（只用 ble.sh 自身及 `~/.blerc` 的绑定），从根源规避此问题，
且**不改动**你的 `~/.inputrc`（其它 readline 程序如 python/gdb/psql 仍照常读取它）。

**验证 / 排查**：

~bash
# 看方向键当前绑到了什么（word 移动即中招）
ble-bind -d | grep -iE 'left|right|cword'
# 看 ~/.inputrc 里是否有误绑 \eOD / \eOC
grep -nE '\\eOD|\\eOC' ~/.inputrc
~

如需让 ble.sh 恢复导入 inputrc，去掉该行的 `--noinputrc` 即可（`--inputrc` 取值：
`auto`/`diff`/`all`/`user`/`none`，`--noinputrc` 等价 `--inputrc=none`）。
