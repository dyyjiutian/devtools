# devtools

Automated setup scripts and configurations for developer tools across macOS and Linux (CentOS/RHEL).

## Directory Structure

```
devtools/
├── os/
│   ├── macos/                    # macOS 初始化、电源、通知、远程桌面
│   └── linux/                    # Ubuntu/Debian/CentOS/RHEL 初始化
├── languages/                    # Python / Go / Java / Rust 运行时；bash/ 为脚本语言笔记
├── shell/                        # 交互用 Bash / Zsh / Oh My Zsh / Starship
├── terminal/
│   ├── ghostty/                  # Ghostty terminal
│   ├── iterm2/                   # iTerm2 config and SSH login scripts
│   ├── tmux/                     # tmux configuration
│   └── yazi/                     # yazi file manager setup
├── editors/
│   ├── nvim/                     # Neovim (Lua + lazy.nvim)
│   ├── vim/                      # Vim + vim-plug + coc.nvim
│   ├── cursor/                   # Cursor editor backup/restore
│   └── vscode/                   # VS Code setup
├── network/                      # FRP / proxy / VPN infrastructure
├── tools/                        # Bazel / Git / SSH standalone tools
├── agents/                       # Claude / Codex / Cursor Agent
├── docker/                       # Alinux 3 开发镜像
├── cache/                        # Offline installation assets
├── docs/                         # Design documents and implementation plans
└── tests/                        # Shell regression tests
```

## Alibaba Cloud Linux 3 开发镜像

`docker/alinux3/` 提供基于 Alibaba Cloud Linux 3 的 x86_64 `devbox` 开发镜像。构建时会初始化 Git（含 lazygit / delta / 子命令）、Vim 9.2 + coc、Neovim（含 `bashls` 等常用 LSP）、tmux、Bash（ble / fzf / zoxide / Starship）、`rg` / `jq` / `bat` / `tree` / `yazi`、Docker CE（特权 DinD）、Bazel、Go、Java，以及 Claude / Codex / Cursor Agent CLI（无 API key）。镜像不写入 Git 身份，也不包含 Dev Container 或 SSH 变体。入口以 root 拉起里层 `dockerd` 后 drop 到 `admin`，工作目录 `/home/admin`。标签为 `alinux3-devbox:<YYYYMMDD-HHMM>` 与 `alinux3-devbox:latest`。

```bash
bash docker/alinux3/bake.sh
docker run --privileged --rm -it alinux3-devbox:latest
```

没有 Buildx 时可使用：

```bash
docker build --platform linux/amd64 \
  --file docker/alinux3/Dockerfile \
  --tag alinux3-devbox:$(date +%Y%m%d-%H%M) \
  --tag alinux3-devbox:latest .
```

详细说明见 [`docker/alinux3/README.md`](docker/alinux3/README.md)。

## OS Initialization

### macOS

```bash
./os/macos/setup.sh               # Full installation (base + packages.list)
./os/macos/setup.sh --info-only   # Show system info only
./os/macos/setup.sh --dry-run     # Preview without installing
./os/macos/setup.sh --base-only   # Homebrew only
./os/macos/setup.sh --skip-casks  # Skip GUI applications
./os/macos/setup.sh --skip-omz    # Skip Oh My Zsh
```

Part 1 installs Homebrew. Part 2 installs from [`os/macos/packages.list`](os/macos/packages.list) (CLI formulae, GUI casks, Node via nvm, Oh My Zsh).

### Ubuntu / Debian

```bash
./os/linux/setup_ubuntu.sh               # Full installation
./os/linux/setup_ubuntu.sh --dry-run
./os/linux/setup_ubuntu.sh --skip-docker
```

Uses [`os/linux/packages.ubuntu.list`](os/linux/packages.ubuntu.list).

### CentOS / RHEL

```bash
./os/linux/setup_centos.sh               # Full installation
./os/linux/setup_centos.sh --info-only
./os/linux/setup_centos.sh --dry-run
./os/linux/setup_centos.sh --skip-docker # Skip Docker CE
```

Part 1 installs base deps. Part 2 installs from [`os/linux/packages.centos.list`](os/linux/packages.centos.list) (Docker CE, Git, Node via NodeSource, terminal tools, Nerd Fonts).

## Shell and Terminal

### Ghostty (`terminal/ghostty/`)

Modern terminal emulator with GPU acceleration (Metal on macOS). Starship prompt configs live in `shell/starship/` and are reused by shell setup scripts.

```bash
./terminal/ghostty/setup.sh            # Full installation
./terminal/ghostty/setup.sh --dry-run  # Preview
./terminal/ghostty/setup.sh --skip-ghostty  # Starship config only
./terminal/ghostty/setup.sh --skip-starship # Ghostty only
```

See [`terminal/ghostty/README.md`](terminal/ghostty/README.md) for keybindings and configuration details.

### Oh My Zsh (`shell/oh-my-zsh/`)

Configures powerlevel10k theme, zsh-autosuggestions, and zsh-syntax-highlighting.

```bash
./shell/oh-my-zsh/setup.sh
```

### Neovim (`editors/nvim/`)

Lua-based Neovim configuration using lazy.nvim with LSP, Telescope, nvim-tree, git integration, and Tree-sitter.

```bash
./editors/nvim/setup.sh             # Full installation
./editors/nvim/setup.sh --backup    # Backup existing config
./editors/nvim/setup.sh --update    # Update plugins only
```

See [`editors/nvim/README.md`](editors/nvim/README.md) for key mappings and plugin list.

### Vim (`editors/vim/`)

Vim configuration with vim-plug and coc.nvim language servers (Python, Go, Java, Shell, JSON, YAML). Leader key: `,`.

```bash
./editors/vim/setup.sh
./editors/vim/setup.sh --upgrade   # upgrade Vim (pkg manager, else ~/.local) then install
./editors/vim/setup.sh --dry-run
```

### tmux (`terminal/tmux/`)

Installs **tmux 3.7b** (source build on Linux; Homebrew on macOS), deploys config, and sets up TPM plugins. Enables `extended-keys` for Codex Shift+Enter newlines.

```bash
./terminal/tmux/setup.sh              # install 3.7b + config + TPM
./terminal/tmux/setup.sh --install-bin-only
```

### yazi (`terminal/yazi/`)

Terminal file manager with image preview and shell integration.

```bash
./terminal/yazi/setup.sh
```

## Editors

### Cursor (`editors/cursor/`)

Backup and restore Cursor editor settings, keybindings, and extensions across machines.

```bash
bash editors/cursor/setup.sh --backup   # Backup to config/
bash editors/cursor/setup.sh --restore  # Restore on new machine
bash editors/cursor/setup.sh --backup  --dir ~/dotfiles/cursor
```

See [`editors/cursor/config/README.md`](editors/cursor/config/README.md) for custom keybindings.

## Build and Network Tools

### Bazel (`tools/bazel/`)

Installs [Bazelisk](https://github.com/bazelbuild/bazelisk), [buildifier](https://github.com/bazelbuild/buildtools), and [starpls](https://github.com/withered-magic/starpls) with shell completion on macOS and Linux.

```bash
./tools/bazel/setup.sh                        # Full installation
./tools/bazel/setup.sh --bazel-version 8.0.0  # Pin a specific version
./tools/bazel/setup.sh --dry-run
```

See [`tools/bazel/README.md`](tools/bazel/README.md) for version management and editor integration.

### FRP Remote Access (`network/frp/`)

FRP reverse proxy on Linux (frps) + macOS client (frpc) to SSH and VNC into Mac machines via the Linux server's IP.

```bash
# 1. Deploy server (Linux)
sudo ./network/frp/server/setup.sh

# 2. Deploy client (macOS) — get token from server --status output
./network/frp/client/setup.sh \
  --server-ip=<LINUX_IP> --token=<TOKEN> --client-name=$(hostname -s)

# Connect
ssh -p 6000 <mac_user>@<LINUX_IP>
open vnc://<LINUX_IP>:6001
```

See [`network/frp/README.md`](network/frp/README.md) for multi-Mac port allocation and troubleshooting.

### SNI Proxy (`network/proxy/`)

Nginx-based SNI transparent proxy on a Singapore ECS to accelerate GitHub and Docker Hub access from China — no proxy client needed, just a `hosts` entry.

```bash
sudo ./network/proxy/server/setup.sh          # Deploy server
sudo ./network/proxy/client/configure.sh <ECS_IP>  # Configure client
```

See [`network/proxy/README.md`](network/proxy/README.md) for full setup and extending to more domains.

### Xray VLESS + Reality Proxy (`network/vpn/`)

Three-hop proxy chain (domestic client → Hangzhou relay ECS → Singapore exit ECS) using the Xray VLESS + Reality protocol. Designed to bypass GFW detection when accessing AI services. Supports Linux, macOS (script + system proxy toggle), and iOS (Shadowrocket).

```bash
# 1. Deploy exit node (Singapore ECS)
sudo ./network/vpn/exit/setup.sh

# 2. Deploy relay node (Hangzhou ECS)
sudo ./network/vpn/relay/setup.sh

# 3. Install client (Linux domestic machine)
sudo ./network/vpn/client/linux_setup.sh install \
  --relay-ip=<RELAY_IP> --uuid=<UUID> \
  --public-key=<PUB_KEY> --short-id=<SHORT_ID>

# macOS: install Xray and manage the system proxy
./network/vpn/client/macos_setup.sh install \
  --relay-ip=<RELAY_IP> --uuid=<UUID> \
  --public-key=<PUB_KEY> --short-id=<SHORT_ID>
./network/vpn/client/macos_setup.sh proxy on
./network/vpn/client/macos_setup.sh proxy off
```

See [`network/vpn/README.md`](network/vpn/README.md) for GUI client setup (V2RayXS, Shadowrocket) and troubleshooting.

## Git Utilities

See [`tools/git/README.md`](tools/git/README.md) for full documentation.

### One-Shot Setup (`tools/git/setup.sh`)

Installs git-delta and GitHub CLI (`gh`; then run `gh auth login` to authenticate), installs the `git rb` / `git bc` / `git wc` / `git review` / `git sparse-clone` subcommands, applies global Git defaults, adds the `gitroot` shell alias, and enables status/pull/fetch optimizations. On Linux, only APT/DNF/YUM are used; git-delta prefers temporary Alibaba Cloud mirrors, with a verified offline static cache for CentOS 7 x86_64.

```bash
bash tools/git/setup.sh           # Full setup
bash tools/git/setup.sh --dry-run # Preview only
bash tools/git/setup.sh --skip-delta
bash tools/git/setup.sh --skip-gh
```

### Global Configuration (`tools/git/scripts/config.sh`)

Interactive setup for `user.name`, `user.email`, 15+ recommended global git settings, and status/pull/fetch/checkout performance tweaks. Also configures [git-delta](https://github.com/dandavison/delta) as the diff pager if it is installed.

```bash
bash tools/git/scripts/config.sh           # Interactive setup
bash tools/git/scripts/config.sh --dry-run # Preview only
```

### Git Subcommand Installer (`tools/git/scripts/sub-command.sh`)

Installs `git rb` / `git bc` / `git wc` / `git review` / `git sparse-clone` and their man pages to `~/.local/bin`. Runnable on its own with `--dry-run` / `--help`.

```bash
bash tools/git/scripts/sub-command.sh           # Install
bash tools/git/scripts/sub-command.sh --dry-run # Preview only
```

### Portable Git Subcommands (`tools/git/bin/`)

Installed to `~/.local/bin` by setup, so they keep working even if this repo is removed. All support `--help` and auto-detect the default branch via `origin/HEAD`.

| Command | Description |
|---------|-------------|
| `git rb [branch]` | Fetch and rebase onto the remote default branch, or the specified branch |
| `git bc [branch] [--dry-run]` | Delete local branches already merged into the target remote branch (merged / rebase); skips worktree branches |
| `git wc [branch] [--dry-run]` | Remove linked worktrees whose branches are already merged (merged / rebase), then delete those branches |
| `git review [branch]` | Open a review for the current branch, auto-detecting the platform |
| `git sparse-clone <url> [paths...]` | Sparse-clone selected directories (cone); append with `--append` |

`git review` detects the platform from the `origin` remote URL and targets the repository's default branch (override with `git review <branch>`), matched in priority order:

| Platform | Detection | Action |
|----------|-----------|--------|
| GitHub | URL contains `github.com` | `git push -u origin HEAD` + `gh pr create --fill --base <default>` |
| Alibaba GitLab | URL contains `alibaba` | `git push origin HEAD:refs/for/<default>/<branch>` |
| GitLab | URL contains `gitlab` | `git push -o merge_request.create` (no extra CLI needed) |
| Gerrit | Otherwise | `git push origin HEAD:refs/for/<default>` |

### Shell Alias (`tools/git/scripts/alias.sh`)

Injects only `gitroot` into `~/.zshrc` or `~/.bashrc`. The rebase / clean / review workflows are git subcommands (above) rather than aliases; `gitroot` stays an alias because `cd` must run in the active shell process.

```bash
bash tools/git/scripts/alias.sh         # Install
bash tools/git/scripts/alias.sh --clean # Remove
```

| Command | Description |
|---------|-------------|
| `gitroot` | cd to repository root |

### Delta — Enhanced Diff Pager

`tools/git/setup.sh` installs `git-delta` through Homebrew on macOS or APT/DNF/YUM on Linux. Ubuntu/Debian and RHEL-family 8/9 use temporary Alibaba Cloud mirrors first; CentOS 7 x86_64 prefers the verified `cache/binaries/` musl archive and downloads the same pinned upstream release when the cache is missing or invalid. After running setup, all `git diff`, `git log`, and `git show` output is rendered through delta with side-by-side layout and syntax highlighting.

```bash
brew install git-delta   # or install via os/macos/setup.sh
```

## AI Agent

### Claude Code (`agents/claude/`)

Install and configure [Claude Code](https://claude.ai/code) CLI tool. See [agents/claude/README.md](agents/claude/README.md) for full docs.

```bash
./agents/claude/setup.sh install      # Install Claude Code
./agents/claude/setup.sh configure    # Interactive configuration
./agents/claude/setup.sh uninstall    # Uninstall Claude Code
```

Configure API key and models:
```bash
./agents/claude/setup.sh configure --api-key "sk-ant-..." --model "claude-sonnet-4-6"
```

Mac Agent session notifications use the shared listener and hooks:
```bash
./os/macos/agent-notify/agent-hooks-setup.sh install
./os/macos/agent-notify/agent-hooks-setup.sh hook add all
```

Codex and Cursor Agent setup scripts are available under agents/codex/ and agents/cursor-agent/.

## Testing (L1 / L2 / L3)

分层与模块该跑到哪一层见 [`tests/README.md`](tests/README.md)。**改脚本后默认只跑 L1。**

```bash
# L1 — 本机 profile + fake（默认，无 Docker、无真装）
bazel test //...

# L2 — Docker + fake（需要 Docker）
bazel test --config=l2 //...

# L3 — 真装（可选；Linux Docker E2E，macOS 在 GitHub macos-26）
bazel test --config=l3 --test_tag_filters=l3,-requires-macos //...
```

GitHub 有三条流水线 `UT` / `IT` / `E2E`（`.github/workflows/{ut,it,e2e}.yml`）。在 commit 或 PR 标题/正文里写 `[test#L1]`、`[test#L1,L2]`、`[test#ut,e2e]` 或 `[test#skip]` 选择层（`ut`/`it`/`e2e` 是 L1/L2/L3 的别名）；不写则三层都跑。详见 `tests/README.md`。

## Quick Start on a New Machine

```bash
# 1. Clone the repo
git clone <repo-url> ~/devtools

# 2. OS setup
./os/macos/setup.sh          # macOS
# or
./os/linux/setup_centos.sh   # CentOS/RHEL

# 3. Configure git globals, delta, and aliases
bash ~/devtools/tools/git/setup.sh
source ~/.zshrc

# 4. Set up your preferred terminal/editor
./terminal/ghostty/setup.sh  # or ./editors/nvim/setup.sh, etc.
bash editors/cursor/setup.sh --restore
```
