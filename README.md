# devtools

Automated setup scripts and configurations for developer tools across macOS and Linux (CentOS/RHEL).

## Directory Structure

```
devtools/
├── os/
│   ├── macos/setup.sh            # macOS system initialization
│   └── linux/setup_centos.sh     # CentOS/RHEL system initialization
├── terminal/
│   ├── ghostty/                  # Ghostty terminal + Starship prompt
│   ├── iterm2/                   # iTerm2 config and SSH login scripts
│   ├── nvim/                     # Neovim (Lua + lazy.nvim)
│   ├── oh-my-zsh/                # Oh My Zsh + powerlevel10k
│   ├── tmux/                     # tmux configuration
│   ├── vim/                      # Vim + vim-plug + coc.nvim
│   └── yazi/                     # yazi file manager setup
├── editors/
│   └── cursor/                   # Cursor editor backup/restore
├── tools/
│   ├── bazel/                    # Bazelisk + buildifier + starpls
│   ├── frp/                      # FRP reverse proxy for Mac SSH/VNC
│   ├── proxy/                    # SNI proxy for GitHub/Docker Hub
│   └── vpn/                      # Xray VLESS + Reality three-hop proxy
├── vcs/git/
│   ├── scripts/                  # git_config.sh, alias.sh
│   └── config/github.gitconfig   # GitHub-specific git aliases
└── agent/                        # AI agent (Claude Code) setup
```

## OS Initialization

### macOS

```bash
./os/macos/setup.sh               # Full installation
./os/macos/setup.sh --info-only   # Show system info only
./os/macos/setup.sh --skip-casks  # Skip GUI applications
./os/macos/setup.sh --skip-omz    # Skip Oh My Zsh
```

Installs: Homebrew, CLI tools (git, curl, wget, jq, tree, htop, gh, neovim), GUI apps (iTerm2, Sublime Text, Obsidian), Node.js via nvm, Oh My Zsh.

### CentOS / RHEL

```bash
./os/linux/setup_centos.sh               # Full installation
./os/linux/setup_centos.sh --info-only
./os/linux/setup_centos.sh --skip-docker # Skip Docker CE
```

Installs: Docker CE (with docker-compose-plugin), Git, Node.js LTS via NodeSource.

## Terminal

### Ghostty + Starship (`terminal/ghostty/`)

Modern terminal emulator with GPU acceleration (Metal on macOS) and a Rust-based Starship prompt.

```bash
./terminal/ghostty/setup.sh            # Full installation
./terminal/ghostty/setup.sh --dry-run  # Preview
./terminal/ghostty/setup.sh --skip-ghostty  # Starship only
./terminal/ghostty/setup.sh --skip-starship # Ghostty only
```

See [`terminal/ghostty/README.md`](terminal/ghostty/README.md) for keybindings and configuration details.

### Oh My Zsh (`terminal/oh-my-zsh/`)

Configures powerlevel10k theme, zsh-autosuggestions, and zsh-syntax-highlighting.

```bash
./terminal/oh-my-zsh/setup.sh
```

### Neovim (`terminal/nvim/`)

Lua-based Neovim configuration using lazy.nvim with LSP, Telescope, nvim-tree, git integration, and Tree-sitter.

```bash
./terminal/nvim/setup.sh             # Full installation
./terminal/nvim/setup.sh --backup    # Backup existing config
./terminal/nvim/setup.sh --update    # Update plugins only
```

See [`terminal/nvim/README.md`](terminal/nvim/README.md) for key mappings and plugin list.

### Vim (`terminal/vim/`)

Vim configuration with vim-plug and coc.nvim language servers (Python, Go, Java, Shell, JSON, YAML). Leader key: `,`.

```bash
./terminal/vim/setup.sh
```

### tmux (`terminal/tmux/`)

tmux configuration with custom keybindings and status bar styling.

```bash
# Copy config to home directory
cp terminal/tmux/tmux.conf ~/.tmux.conf
tmux source-file ~/.tmux.conf
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

## Tools

### Bazel (`tools/bazel/`)

Installs [Bazelisk](https://github.com/bazelbuild/bazelisk), [buildifier](https://github.com/bazelbuild/buildtools), and [starpls](https://github.com/withered-magic/starpls) with shell completion on macOS and Linux.

```bash
./tools/bazel/setup.sh                        # Full installation
./tools/bazel/setup.sh --bazel-version 8.0.0  # Pin a specific version
./tools/bazel/setup.sh --dry-run
```

See [`tools/bazel/README.md`](tools/bazel/README.md) for version management and editor integration.

### FRP Remote Access (`tools/frp/`)

FRP reverse proxy on Linux (frps) + macOS client (frpc) to SSH and VNC into Mac machines via the Linux server's IP.

```bash
# 1. Deploy server (Linux)
sudo ./tools/frp/server/setup.sh

# 2. Deploy client (macOS) — get token from server --status output
./tools/frp/client/setup.sh \
  --server-ip=<LINUX_IP> --token=<TOKEN> --client-name=$(hostname -s)

# Connect
ssh -p 6000 <mac_user>@<LINUX_IP>
open vnc://<LINUX_IP>:6001
```

See [`tools/frp/README.md`](tools/frp/README.md) for multi-Mac port allocation and troubleshooting.

### SNI Proxy (`tools/proxy/`)

Nginx-based SNI transparent proxy on a Singapore ECS to accelerate GitHub and Docker Hub access from China — no proxy client needed, just a `hosts` entry.

```bash
sudo ./tools/proxy/server/setup.sh          # Deploy server
sudo ./tools/proxy/client/configure.sh <ECS_IP>  # Configure client
```

See [`tools/proxy/README.md`](tools/proxy/README.md) for full setup and extending to more domains.

### Xray VLESS + Reality Proxy (`tools/vpn/`)

Three-hop proxy chain (domestic client → Hangzhou relay ECS → Singapore exit ECS) using the Xray VLESS + Reality protocol. Designed to bypass GFW detection when accessing AI services. Supports Linux, macOS (script + system proxy toggle), and iOS (Shadowrocket).

```bash
# 1. Deploy exit node (Singapore ECS)
sudo ./tools/vpn/exit/setup.sh

# 2. Deploy relay node (Hangzhou ECS)
sudo ./tools/vpn/relay/setup.sh

# 3. Install client (domestic machine)
./tools/vpn/client/setup.sh \
  --relay-ip=<RELAY_IP> --uuid=<UUID> \
  --public-key=<PUB_KEY> --short-id=<SHORT_ID>

# macOS: toggle system-wide proxy
./tools/vpn/client/proxy-on.sh
./tools/vpn/client/proxy-off.sh
```

See [`tools/vpn/README.md`](tools/vpn/README.md) for GUI client setup (V2RayXS, Shadowrocket) and troubleshooting.

## Git Utilities

### Global Configuration (`vcs/git/scripts/git_config.sh`)

Interactive setup for `user.name`, `user.email`, and 15+ recommended global git settings.

```bash
bash vcs/git/scripts/git_config.sh           # Interactive setup
bash vcs/git/scripts/git_config.sh --dry-run # Preview only
```

### Shell Aliases (`vcs/git/scripts/alias.sh`)

Injects git helper functions into `~/.zshrc` or `~/.bashrc`.

```bash
bash vcs/git/scripts/alias.sh        # Install
bash vcs/git/scripts/alias.sh --clean # Remove
```

| Command | Description |
|---------|-------------|
| `gitroot` | cd to repository root |
| `gitrebase` | Fetch and rebase onto the default remote branch |
| `gitprune` | Delete local branches already merged into default branch |
| `gitalias` | List all aliases |

### GitHub gitconfig (`vcs/git/config/github.gitconfig`)

```bash
git config --global include.path ~/devtools/vcs/git/config/github.gitconfig
```

Provides `git review`: push current branch and open a PR via `gh`.

## AI Agent

### Claude Code (`agent/claude/`)

Install and configure [Claude Code](https://claude.ai/code) CLI tool. See [agent/claude/README.md](agent/claude/README.md) for full docs.

```bash
./agent/claude/setup.sh install      # Install Claude Code
./agent/claude/setup.sh configure    # Interactive configuration
./agent/claude/setup.sh uninstall    # Uninstall Claude Code
```

Configure API key and models:
```bash
./agent/claude/setup.sh configure --api-key "sk-ant-..." --model "claude-sonnet-4-6"
```

Mac SSH remote session end notification (plays system sound when Claude session ends on remote Linux):
```bash
./agent/claude/mac_ssh_hook.sh install
./agent/claude/mac_ssh_hook.sh setup-remote user@linux-host
./agent/claude/mac_ssh_hook.sh ssh-hint user@linux-host
```

## Quick Start on a New Machine

```bash
# 1. Clone the repo
git clone <repo-url> ~/devtools

# 2. OS setup
./os/macos/setup.sh          # macOS
# or
./os/linux/setup_centos.sh   # CentOS/RHEL

# 3. Configure git globals
bash ~/devtools/vcs/git/scripts/git_config.sh
bash ~/devtools/vcs/git/scripts/alias.sh
source ~/.zshrc

# 4. Set up your preferred terminal/editor
./terminal/ghostty/setup.sh  # or ./terminal/nvim/setup.sh, etc.
bash editors/cursor/setup.sh --restore
```
