# Bash Pitfalls

本仓常见踩坑记录。更完整的通用清单见 [BashPitfalls（Greg's Wiki）](https://mywiki.wooledge.org/BashPitfalls)。

## `$VAR` 紧贴多字节字符（macOS Bash 3.2 + `set -u`）

**错误写法：**

```bash
set -u
TARGET=codex
info "跳过（--target $TARGET）"   # 全角 ）紧跟 $TARGET
```

**现象：** `TARGET�: unbound variable`（变量名被污染成含 UTF-8 字节的非法名）。

**原因：** Bash 3.2 在部分 locale 下，未花括号的 `$VAR` 后若紧跟多字节字符，可能把后续字节算进变量名；配合 `set -u` 即报 unbound。

**正确写法：**

```bash
info "跳过（--target ${TARGET}）"
# 或避免紧贴：info "跳过 (--target $TARGET)"
```

**回归：** 静态检查脚本中是否存在 `\$[A-Za-z_][A-Za-z0-9_]*）` 这类「未花括号 + 全角右括号」模式。

## 空数组在 `set -u` 下展开（Bash 3.2）

**错误写法：**

```bash
set -u
args=()
cmd "${args[@]}"   # Bash 3.2 可能报 unbound variable
```

**正确写法：** 条件展开或显式分支，例如仅在非空时展开，或用兼容写法避免对空数组做 `"${arr[@]}"`。参见本仓 `tools/ssh` 相关处理与其 README Issues。

## 未引用的展开

`$var` / `$(cmd)` 未加双引号会触发词切割与 glob。路径与用户输入一律 `"$var"` / `"$(cmd)"`。需要按词拆分时再显式处理 `IFS`。

## 用 `ls` 的输出做循环

```bash
# 错误
for f in $(ls *.mp3); do ...; done
```

应直接用 glob 或 `find -print0` + `read -d ''`。详见 BashPitfalls #1。
