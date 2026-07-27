# Bash 配置

安装 ble.sh、zoxide、fzf 和 Starship，并幂等写入 ~/.bashrc。

~~~bash
bash shell/bash/setup.sh --help
bash shell/bash/setup.sh --dry-run
~~~

Linux 安装优先使用 cache/ 中的二进制缓存。

## 常见问题 (Issues)

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
