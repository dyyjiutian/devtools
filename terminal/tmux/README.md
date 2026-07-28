# tmux

安装 tmux 3.7b、部署 tmux.conf 并配置 TPM 插件。

~~~bash
bash terminal/tmux/setup.sh --help
bash terminal/tmux/setup.sh --dry-run
bash terminal/tmux/setup.sh --install-bin-only
~~~

Linux 可能从源码构建；macOS 使用 Homebrew。配置以复制方式写入 `~/.tmux.conf`（覆盖前备份已有普通文件）。

## Issues

### 2026-07-28 — setup 将 tmux.conf 软链到仓库路径

**问题表象**

- `setup.sh` 用 `ln -sf` 把 `~/.tmux.conf` 指到仓库内文件，依赖本机 worktree 路径；移动/删除仓库后配置失效。

**根因**

- 部署策略选择了软链而非复制。

**解法**

- 改为备份已有普通文件后 `cp` 覆盖；若目标已是软链则先删除再复制，避免写穿源文件。
- 重新执行：`bash terminal/tmux/setup.sh`（或仅配置路径时 source 后调用 `deploy_config`）。
