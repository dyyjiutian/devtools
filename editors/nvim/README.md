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
| `<Space>n` | Toggle file explorer (nvim-tree) |
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
./setup.sh --update     # Sync init.lua/lua/ config, then update plugins and LSP servers
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

**解法**：改为 `nvim --headless -c "Lazy! sync" -c "qa!"`（`_nvim_headless`）；sync 前清理 pinned 的 mason/lspconfig 目录再 sync。重新执行：

```bash
cd editors/nvim && ./setup.sh --update
```

### 2026-07-30 — mason-lspconfig 报错导致所有 LSP 都未注册（gr 无结果）

**表象**：`gr`（`textDocument/references`）没有任何结果，`:LspInfo` 里没有 client attach。

**根因**：`require("mason-lspconfig").setup{...}` 抛错后，`config` 函数整体中断，其中的 `handlers` 从未执行，
`require("lspconfig")[server].setup(...)` 一次都没被调用，因此没有任何 server 注册、没有 client attach。
`gr` 是在 `LspAttach` 里才绑定的，所以按键也表现为「未映射」。

**解法**：`mason-lspconfig.setup` 用 `pcall` 包裹；失败时回退遍历 `servers`，对二进制已在 PATH 的 server
直接调用 `lspconfig[...].setup()`，保证单个插件报错不会拖垮整套 LSP。

### 2026-07-30 — Go / C 无 LSP，以及 bashls references 的两个限制

**表象**：`.go`、`.c` 文件里 `gr` 毫无反应（`clients=[]`）。

**根因**：`servers` 表里没有 `gopls`；`clangd` 虽在表内但不在自动安装名单，未安装就不会 attach。

**解法**：`servers` 增加 `gopls`，并把 `gopls` / `clangd` 加入 `ensure_installed`。
更重的 `jdtls` / `rust_analyzer` 仍按需在 `:Mason` 里手装。

`bashls` 的 references 有两个已知限制（属上游行为，未做改动）：

- 刚 attach 就请求会返回 `null`，需等其完成 background analysis（大仓库更明显）。
- 它是纯文本同名匹配而非作用域感知，不同文件中的同名函数/变量也会被算作引用。

### 2026-07-30 — Telescope 弹框有、结果全空（`file_ignore_patterns` 被当成 glob 写）

**表象**：`gr` / `<Space>ff` 等 picker 正常弹出，但一条结果都没有；只在 `~/workspace/github/` 这类路径下复现。

**根因**：`file_ignore_patterns` 是 **Lua 模式**而非 glob。`".git"` 里的 `.` 是「任意字符」通配符，
因此它匹配到了路径中的 `/github/`（`/git` + 任意字符）。telescope 是先建 picker 再逐条
`string.find(file, v)` 过滤，命中即丢弃，于是弹框在、内容全被静默丢掉。同理 `"*.pyc"` 是 glob 写法，
在 Lua 模式里 `*` 需要跟在某个字符类后面，并不表示「任意多个字符」。

**解法**：改用转义并带目录分隔符锚定的 Lua 模式，例如 `"^%.git/"`、`"/%.git/"`、`"%.pyc$"`。
可用 `lua -e 'print(string.find(path, pattern))'` 快速自查某条模式是否误伤。

### 2026-07-31 — treesitter 跟随默认分支导致 preview 报 `ft_to_lang` 为 nil

**表象**：跨文件 `gr` 打开 preview 时报
`telescope/previewers/utils.lua:135: attempt to call field 'ft_to_lang' (a nil value)`。

**根因**：`nvim-treesitter` 的默认分支已切换为重写版 `main`，而配置没有 pin 分支。`main` 要求 Neovim 0.12+，
并移除了 `nvim-treesitter.configs` 与 `parsers.ft_to_lang()`；telescope 0.1.x 的 previewer 仍会调用它，于是取到 nil。
同时 `main` 的 `setup()` 会忽略 master 风格的 `ensure_installed` / `highlight` / `indent`，
所以 parser 目录一直是空的、treesitter 高亮其实从未生效（只是不报错，容易被忽略）。

**解法**：`branch = "master"`，并把 `config` 改回 `require("nvim-treesitter.configs").setup(opts)`。
`setup.sh` 同步前会删除 `nvim-treesitter` 目录，让 Lazy 重新 clone 到正确分支。生效后可用
`:TSInstallInfo` 确认 parser 已安装。

### 2026-07-31 — 适配 Neovim 0.10.4 的三个遗留问题（`--update` / `<Space>e` / LazyGit）

Linux 侧固定安装 Neovim 0.10.4（见上文 glibc 一节），而插件生态默认跟随最新版，于是暴露出三个问题，一并修复：

**1. `./setup.sh --update` 不生效**

- 表象：改了 `lua/` 下的配置后执行 `--update`，行为没有任何变化。
- 根因：`--update` 只跑 `Lazy! sync` + Mason 更新，从不把仓库里的 `init.lua` / `lua/` 同步到 `~/.config/nvim`。
- 解法：`--update` 改为「同步配置 + 更新插件与 LSP」。配置同步收敛到 `sync_config()`，
  首次接管时备份非托管配置并写入 `.devtools-nvim` marker，之后原地覆盖，不再堆积 `~/.config/nvim.bak.*`。
  同时删除 `--restore`（与 `--update` 语义重复，且只会多做一次备份）。

**2. `<Space>e` 打不开文件树**

- 表象：`<Space>e` 弹出的是诊断浮窗，不是 nvim-tree。
- 根因：`config/keymaps.lua` 的 `vim.diagnostic.open_float` 与 `plugins/nvim-tree.lua` 的 `NvimTreeToggle`
  抢同一个键，后加载者覆盖前者。
- 解法：文件树改到 `<Space>n`（`NvimTreeToggle`），`<Space>e` 保留给诊断浮窗。
  同类问题还有 `<Space>q`：`vim.diagnostic.setloclist` 被同文件后面的 `<cmd>q<CR>` 覆盖，一直是死映射；
  诊断列表已由 trouble.nvim 的 `<Space>xx` / `<Space>xX` 提供，故直接删除该映射，`<Space>q` 只表示退出。

**3. `<Space>gg` 打不开 LazyGit**

- 表象：`lazygit.nvim/lua/lazygit.lua:65` 报错。
- 根因：上游改用 `vim.fn.jobstart(cmd, { term = true })`，`term` 选项是 Neovim 0.11 才有的；0.10 只能用 `termopen`。
- 解法：0.11 以下 pin 到最后一个使用 `termopen` 的提交 `4839ab6`，0.11+ 仍跟随默认分支（`vim.fn.has("nvim-0.11")` 判断）。
  代价是旧版本上拿不到 `4839ab6` 之后的上游修复；宿主升到 0.11 后该 pin 会自动失效。

以上被 pin 的插件（mason / lspconfig / treesitter / lazygit）在 `_reset_pinned_plugins` 中统一清理后再 sync，
避免本机留着不兼容的旧 checkout。

## References

- [Neovim Documentation](https://neovim.io/doc/)
- [Lazy.nvim Documentation](https://lazy.folke.io/)
- [Lua Guide for Neovim](https://neovim.io/doc/user/lua-guide.html)
