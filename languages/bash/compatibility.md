# Bash 兼容性

## 本仓基线

- **方言：** Bash（`#!/usr/bin/env bash`），不是泛 POSIX `sh`，也不是 Zsh。
- **最低版本：** macOS 自带 **Bash 3.2**。不要依赖 Bash 4+ 语法（关联数组、`mapfile`、某些 `readarray`、`|&` 等），除非脚本明确仅在更高版本运行并写明。
- **严格模式：** 所有本仓 `.sh` 脚本必须在开头（`shebang` 与简短文件头注释之后）启用：

```bash
set -euo pipefail
```

| 选项 | 作用 |
|---|---|
| `-e` / `errexit` | 命令失败则退出 |
| `-u` / `nounset` | 使用未绑定变量则报错 |
| `-o pipefail` | 管道中任一命令失败则整段失败 |

`set -u` 会放大 3.2 下的展开坑（空数组、多字节紧贴 `$VAR`），见 [`pitfalls.md`](./pitfalls.md)。

## Shell vs Bash

- **Shell：** 命令解释器族的统称（含 POSIX `sh`、Bash、Zsh、Dash 等）。
- **Bash：** 本仓脚本使用的具体实现/方言。
- 交互配置（rc、插件）在 `shell/`；本文件只约束「怎么写可执行 Bash 脚本」。

## 与 Linux 新 Bash 的差异

在 Linux Bash 5 上能跑的脚本，在 macOS Bash 3.2 上仍可能失败。改脚本后至少：

1. `bash -n script.sh`
2. 相关回归测试
3. 心里过一遍：是否用了 4+ 语法、空数组、`$VAR`+多字节
