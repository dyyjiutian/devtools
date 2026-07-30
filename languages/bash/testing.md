# Bash 脚本测试

## 最小检查

```bash
bash -n path/to/script.sh
git diff --check
```

## 本仓习惯

- 优先用临时目录和 fake 命令验证；不要为了验证而跑真实安装或无回滚方案的远程/网络变更。
- 安装器变更：覆盖 `--help`、`--dry-run`、缓存路径、**重复执行（幂等）**、失败回滚。
- 有 Bazel 时跑适用的 OS-profile × module 目标（`macos` / `linux_ubuntu` / `linux_alinux3` / `linux_alinux4`）；缺工具则如实说明，勿报假绿。
- macOS 相关可用 `bats`（见 `os/macos/run_bats.sh` 等）。

## 针对兼容性陷阱

- 静态或单测锁住已知坑（例如未花括号 `$VAR` 紧贴全角 `）`），见 [`pitfalls.md`](./pitfalls.md)。
- 仅在 Linux Bash 5 上跑通不足以证明 macOS Bash 3.2 兼容。
