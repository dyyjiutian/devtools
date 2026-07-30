# Neovim Configuration

Modern Neovim configuration with Lua-based setup using [lazy.nvim](https://github.com/folke/lazy.nvim) plugin manager.

## Features

- **Modern Lua Configuration**: Full Lua-based configuration using `init.lua`
- **Lazy Plugin Manager**: Fast and efficient plugin loading with lazy.nvim
- **LSP Support**: Full Language Server Protocol support with Mason
- **Auto-completion**: Intelligent code completion with nvim-cmp
- **Fuzzy Finding**: Fast file search and grep with Telescope
- **File Explorer**: Nvim-tree for file navigation
- **Git Integration**: Fugitive, Gitsigns, and LazyGit support
- **Syntax Highlighting**: Tree-sitter powered syntax highlighting
- **Beautiful UI**: TokyoNight colorscheme with Lualine and Bufferline

## Prerequisites

- **Neovim** >= 0.9.0（Linux 安装器固定 **v0.10.4** portable tarball，兼容 Alinux 3 / glibc 2.32，无 FUSE 依赖）
- **Git**
- **Node.js** >= 16 (for LSP servers)
- **Ripgrep** (for Telescope grep)
- **fd** (optional, for faster file finding)

## Quick Start

```bash
# Run the setup script
cd editors/nvim
./setup.sh
```

This will:
1. Install/Update Neovim if needed（Linux：优先 `cache/binaries/nvim-*-v0.10.4.tar.gz`）
2. Install system dependencies
3. Copy configuration files
4. Install Nerd Font for icons
5. Install all plugins and LSP servers

## Manual Setup

If you prefer to set up manually:

```bash
# 1. Install Neovim (macOS)
brew install neovim node ripgrep fd

# 1. Install Neovim (Linux) — pin v0.10.4 tarball (glibc 2.32 / no FUSE)
curl -LO https://github.com/neovim/neovim/releases/download/v0.10.4/nvim-linux-x86_64.tar.gz
tar -xzf nvim-linux-x86_64.tar.gz
mkdir -p ~/.local
rm -rf ~/.local/nvim
mv nvim-linux-x86_64 ~/.local/nvim
ln -sfn ~/.local/nvim/bin/nvim ~/.local/bin/nvim

# 2. Copy config files
mkdir -p ~/.config/nvim
cp -r init.lua lua ~/.config/nvim/

# 3. Start Neovim (plugins will auto-install)
nvim
```

## Directory Structure

```
~/.config/nvim/
├── init.lua                 # Main configuration entry
├── lazy-lock.json          # Plugin lock file (auto-generated)
└── lua/
    ├── config/
    │   ├── options.lua     # Neovim options/settings
    │   ├── keymaps.lua     # Key mappings
    │   └── autocmds.lua    # Auto commands
    └── plugins/
        ├── init.lua        # Plugin imports
        ├── nvim-tree.lua   # File explorer
        ├── telescope.lua   # Fuzzy finder
        ├── lsp.lua         # LSP configuration
        ├── completion.lua  # Auto-completion
        ├── treesitter.lua  # Syntax highlighting
        ├── git.lua         # Git integration
        ├── lualine.lua     # Status line
        ├── bufferline.lua  # Buffer tabs
        └── ...             # Other plugins
```

## Key Mappings

### Leader Key

**Leader key**: `<Space>`

### General

| Key | Description |
|-----|-------------|
| `<Space>e` | Toggle file explorer (nvim-tree) |
| `<Space>w` | Save file |
| `<Space>q` | Quit |
| `<Space>wq` | Save and quit |
| `<Tab>` / `<S-Tab>` | Next/previous buffer |

### Navigation

| Key | Description |
|-----|-------------|
| `<C-h/j/k/l>` | Navigate windows |
| `gd` | Go to definition |
| `gr` | Find references |
| `gI` | Go to implementation |
| `K` | Show hover documentation |

### Telescope (Fuzzy Finder)

| Key | Description |
|-----|-------------|
| `<Space>ff` | Find files |
| `<Space>fg` | Live grep (search in files) |
| `<Space>fb` | List buffers |
| `<Space>fh` | Find help |
| `<Space>fw` | Search word under cursor |
| `<Space>fr` | Resume last search |

### LSP (Language Server)

| Key | Description |
|-----|-------------|
| `<Space>rn` | Rename symbol |
| `<Space>ca` | Code action |
| `[d` / `]d` | Previous/next diagnostic |
| `<Space>e` | Show diagnostic float |

### Git

| Key | Description |
|-----|-------------|
| `<Space>gs` | Git status (Fugitive) |
| `<Space>gd` | Git diff |
| `<Space>gb` | Git blame |
| `<Space>gg` | Open LazyGit |
| `]c` / `[c` | Next/previous git hunk |
| `<Space>hs` | Stage hunk |
| `<Space>hr` | Reset hunk |

### Search & Navigation

| Key | Description |
|-----|-------------|
| `s` | Flash jump |
| `S` | Flash treesitter |
| `<Space>/` | Search in current buffer |
| `<Space>xx` | Toggle Trouble (diagnostics) |

## Included Plugins

### Core

| Plugin | Description |
|--------|-------------|
| [lazy.nvim](https://github.com/folke/lazy.nvim) | Plugin manager |
| [tokyonight.nvim](https://github.com/folke/tokyonight.nvim) | Colorscheme |

### LSP & Completion

| Plugin | Description |
|--------|-------------|
| [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) | LSP configurations |
| [mason.nvim](https://github.com/williamboman/mason.nvim) | LSP/DAP/formatter installer |
| [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) | Auto-completion |
| [LuaSnip](https://github.com/L3MON4D3/LuaSnip) | Snippet engine |

### Navigation

| Plugin | Description |
|--------|-------------|
| [nvim-tree.lua](https://github.com/nvim-tree/nvim-tree.lua) | File explorer |
| [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) | Fuzzy finder |
| [flash.nvim](https://github.com/folke/flash.nvim) | Enhanced search |

### Git

| Plugin | Description |
|--------|-------------|
| [vim-fugitive](https://github.com/tpope/vim-fugitive) | Git commands |
| [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) | Git decorations |
| [lazygit.nvim](https://github.com/kdheepak/lazygit.nvim) | LazyGit integration |

### UI

| Plugin | Description |
|--------|-------------|
| [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) | Status line |
| [bufferline.nvim](https://github.com/akinsho/bufferline.nvim) | Buffer tabs |
| [indent-blankline.nvim](https://github.com/lukas-reineke/indent-blankline.nvim) | Indent guides |
| [which-key.nvim](https://github.com/folke/which-key.nvim) | Keybinding helper |
| [trouble.nvim](https://github.com/folke/trouble.nvim) | Diagnostics viewer |
| [todo-comments.nvim](https://github.com/folke/todo-comments.nvim) | TODO highlighting |

### Editing

| Plugin | Description |
|--------|-------------|
| [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) | Syntax highlighting |
| [nvim-autopairs](https://github.com/windwp/nvim-autopairs) | Auto pairs |
| [Comment.nvim](https://github.com/numToStr/Comment.nvim) | Comment toggle |
| [nvim-surround](https://github.com/kylechui/nvim-surround) | Surround text objects |

## Supported Languages

The configuration includes LSP servers for:

- **Python** (pyright)
- **Go** (gopls)
- **Java** (jdtls)
- **TypeScript/JavaScript** (ts_ls)
- **Rust** (rust_analyzer)
- **C/C++** (clangd)
- **Bash/Shell** (bashls)
- **Lua** (lua_ls)
- **JSON** (jsonls)
- **YAML** (yamlls)
- **HTML/CSS** (html, cssls)
- **Docker** (dockerls)

Additional formatters installed:
- stylua (Lua)
- black, isort (Python)
- prettier (Web)
- shfmt (Shell)

## Commands

### Setup Script

```bash
./setup.sh              # Full installation
./setup.sh --backup     # Backup existing config
./setup.sh --restore    # Restore config from backup
./setup.sh --update     # Update plugins only
./setup.sh --help       # Show help
```

### Neovim Commands

| Command | Description |
|---------|-------------|
| `:Lazy` | Open plugin manager |
| `:Mason` | Open LSP installer |
| `:checkhealth` | Check Neovim health |
| `:TSInstall <lang>` | Install tree-sitter parser |
| `:LspInfo` | Show LSP info |

## Troubleshooting

### Icons not displaying correctly

Install a [Nerd Font](https://www.nerdfonts.com/) and set it as your terminal font. The setup script installs `MesloLGS NF` automatically.

### LSP not working

1. Check LSP status: `:LspInfo`
2. Install missing servers: `:Mason`
3. Check health: `:checkhealth lsp`

### Plugin installation issues

1. Clear plugin cache: `rm -rf ~/.local/share/nvim/lazy`
2. Restart Neovim to re-install plugins

## Issues

### 2026-07-30 — Alinux 3 安装 Neovim stable 失败（glibc）

**表象**：`editors/nvim/setup.sh` 在 Alinux 3 上下载/运行最新 stable 失败，提示找不到可用包或动态链接器不满足要求。

**根因**：较新的 Neovim stable 需要 glibc 2.34+，Alinux 3 为 glibc 2.32。

**解法**：Linux 安装固定为 v0.10.4 portable tarball；优先使用仓库 `cache/binaries/nvim-linux-*-v0.10.4.tar.gz`，缺失时再从 GitHub 下载同版本。可用 `bash cache/download.sh linux` 预拉缓存。

### 2026-07-30 — AppImage 依赖 fusermount / FUSE

**表象**：安装后运行出现 `fuse: failed to exec fusermount: No such file or directory`。

**根因**：AppImage 依赖 FUSE/`fusermount`，精简服务器镜像常未安装。

**解法**：改为官方 `nvim-linux-*.tar.gz`，解压到 `~/.local/nvim` 并 symlink `~/.local/bin/nvim`，不依赖 FUSE。

### 2026-07-30 — mason-lspconfig `vim.lsp.enable` 为 nil（Neovim 0.10）

**表象**：打开文件时报 `Failed to run config for nvim-lspconfig` / `attempt to call field 'enable' (a nil value)`，并常伴随每次启动 `jdtls: installing` / `clangd: installing`。

**根因**：`mason-lspconfig` v2+ 默认 `automatic_enable`，调用 Neovim 0.11 才有的 `vim.lsp.enable()`；同时 `mason-tool-installer` 把全部 LSP 放进 `ensure_installed`，启动时反复尝试安装。

**解法**：钉住 `nvim-lspconfig` v1.8.0、`mason.nvim` v1.11.0、`mason-lspconfig` v1.32.0；仅自动安装常用 LSP + 格式化工具（`debounce_hours = 24`）。已装过插件时执行：

```bash
rm -rf ~/.local/share/nvim/lazy/mason.nvim ~/.local/share/nvim/lazy/mason-lspconfig.nvim ~/.local/share/nvim/lazy/nvim-lspconfig
# 或整目录: rm -rf ~/.local/share/nvim/lazy
nvim --headless -c "Lazy! sync" -c "qa!"
```

重型服务器（jdtls / clangd / rust_analyzer 等）仍可在 `:Mason` 中按需安装。

### 2026-07-30 — `setup.sh` 未加引号导致 Lazy sync 从未执行

**表象**：`lsp.lua` 已 pin mason/lspconfig v1，但打开文件仍报 `vim.lsp.enable` 为 nil，lazy 目录里仍是 v2。

**根因**：`nvim --headless +Lazy! sync +qall` 未加引号，shell 把参数拆成 `+Lazy!`、`sync`、`+qall`，`Lazy! sync` 从未作为一条 Ex 命令执行。

**解法**：改为 `nvim --headless -c "Lazy! sync" -c "qa!"`（`_nvim_headless`）；setup/restore 前清理 pinned 的 mason/lspconfig 目录再 sync。重新执行：

```bash
cd editors/nvim && ./setup.sh --restore
```

## References

- [Neovim Documentation](https://neovim.io/doc/)
- [Lazy.nvim Documentation](https://lazy.folke.io/)
- [Lua Guide for Neovim](https://neovim.io/doc/user/lua-guide.html)
