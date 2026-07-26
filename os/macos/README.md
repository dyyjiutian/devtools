# macOS 初始化

负责 Homebrew、系统软件、Node.js、Oh My Zsh 和 macOS 专属辅助服务。

## 两段流程

1. **OS 基础配置**：系统信息检测、Homebrew 安装/更新。
2. **常见软件**：按 [`packages.list`](packages.list) 安装 CLI（brew）、GUI（brew-cask）、Node（nvm）、Oh My Zsh。

清单格式：

```text
# name            version     source       kind  tags
git               latest      brew         cli   dev
iterm2            latest      brew-cask    gui   shell
node              lts         nvm          cli   dev
oh-my-zsh         latest      script       cli   shell
```

- **kind**：`cli` / `tui` / `gui`
- **tags**：`productivity` / `diagnostic` / `dev` / `ops` / `shell`

```bash
bash os/macos/setup.sh --help
bash os/macos/setup.sh --check
bash os/macos/setup.sh --check --kind gui
bash os/macos/setup.sh --check --tag productivity
bash os/macos/setup.sh --install bat
bash os/macos/setup.sh --tag diagnostic --packages-only --dry-run
bash os/macos/setup.sh --skip-casks
```

电源管理、Agent 通知和远程桌面位于本目录的独立子模块，不由基础初始化脚本自动执行。
