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
- **Debugging**: nvim-dap with VSCode-style F5/F9/F10/F11 keys (Python, Go)
- **Testing**: neotest runs and debugs tests from the editor (Python, Go)
- **Format on Save**: conform.nvim, switchable with `:FormatToggle`
- **AI Suggestions**: GitHub Copilot ghost-text completion (`:Copilot auth` required, opt-in)
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

GitHub Copilot needs a one-time, interactive sign-in that the script cannot
perform: open Neovim and run `:Copilot auth`, then follow the device-flow link
in your browser. Copilot suggestions stay silent (no ghost text) until this
completes; a subscription is required.

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
| `<Space>o` | Toggle code outline (aerial) |
| `<Space>sr` | Project-wide search and replace (grug-far) |
| `<Space>sw` | Search and replace word under cursor |

### Format & Lint

Saving a buffer formats it (conform.nvim). `:FormatToggle` switches that off
globally, `:FormatToggle!` for the current buffer only.

| Key | Description |
|-----|-------------|
| `<Space>cf` | Format buffer or selection |

### Debug (nvim-dap)

F-keys match VSCode; the `<Space>d` group covers the rest.

| Key | Description |
|-----|-------------|
| `<F5>` | Start / continue |
| `<F9>` | Toggle breakpoint |
| `<F10>` / `<F11>` / `<S-F11>` | Step over / into / out |
| `<Space>db` / `<Space>dB` | Toggle breakpoint / conditional breakpoint |
| `<Space>du` | Toggle debugger UI |
| `<Space>de` | Evaluate expression |
| `<Space>dr` / `<Space>dl` / `<Space>dt` | REPL / run last / terminate |

Adapters are installed by Mason: `debugpy` (Python) and `delve` (Go).

### Test (neotest)

| Key | Description |
|-----|-------------|
| `<Space>tt` / `<Space>tf` | Run nearest test / whole file |
| `<Space>ts` / `<Space>to` / `<Space>tp` | Summary / output / output panel |
| `<Space>tl` / `<Space>tx` | Run last / stop |
| `<Space>td` | Debug nearest test (via nvim-dap) |

### Terminal

| Key | Description |
|-----|-------------|
| `<C-\>` | Toggle terminal |
| `<Space>tv` / `<Space>tF` | Vertical / floating terminal |

### AI Suggestions (GitHub Copilot)

Completion: `<Tab>` and `<CR>` prefer the open cmp menu, then a displayed Copilot
ghost suggestion, otherwise indent / newline; `↑`/`↓` (or `<C-n>`/`<C-p>`) move
the cmp selection. Use `<C-S-g>` to request Copilot (no manual cmp-complete key;
`<C-Space>` stays free for tmux). Copilot's built-in `<Tab>` map stays disabled
(`copilot_no_tab_map`).

| Key | Description |
|-----|-------------|
| `<Tab>` (insert mode) | Confirm cmp if visible; else accept Copilot ghost text; else indent |
| `<CR>` (insert mode) | Confirm cmp if visible; else accept Copilot ghost text; else newline |
| `<C-j>` (insert mode) | Accept Copilot suggestion directly, bypassing cmp |
| `<C-S-g>` (insert mode) | Close cmp (if open) and request a Copilot suggestion |
| `<M-]>` / `<M-[>` | Next / previous suggestion (Copilot default) |
| `<C-]>` (insert mode) | Dismiss suggestion (Copilot default) |

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
| [copilot.vim](https://github.com/github/copilot.vim) | GitHub Copilot ghost-text suggestions (requires subscription + `:Copilot auth`) |

### Navigation

| Plugin | Description |
|--------|-------------|
| [nvim-tree.lua](https://github.com/nvim-tree/nvim-tree.lua) | File explorer |
| [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) | Fuzzy finder |
| [flash.nvim](https://github.com/folke/flash.nvim) | Enhanced search |
| [aerial.nvim](https://github.com/stevearc/aerial.nvim) | Code outline |
| [grug-far.nvim](https://github.com/MagicDuck/grug-far.nvim) | Project search and replace |
| [nvim-treesitter-context](https://github.com/nvim-treesitter/nvim-treesitter-context) | Sticky scope header |
| [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim) | Integrated terminal |

### Debug & Test

| Plugin | Description |
|--------|-------------|
| [nvim-dap](https://github.com/mfussenegger/nvim-dap) | Debug Adapter Protocol client |
| [nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui) | Debugger panels |
| [nvim-dap-virtual-text](https://github.com/theHamsta/nvim-dap-virtual-text) | Inline variable values |
| [nvim-dap-python](https://github.com/mfussenegger/nvim-dap-python) / [nvim-dap-go](https://github.com/leoluz/nvim-dap-go) | Python / Go adapters |
| [neotest](https://github.com/nvim-neotest/neotest) | Test runner |
| [neotest-python](https://github.com/nvim-neotest/neotest-python) / [neotest-golang](https://github.com/fredrikaverpil/neotest-golang) | Python / Go test adapters |

### Format & Lint

| Plugin | Description |
|--------|-------------|
| [conform.nvim](https://github.com/stevearc/conform.nvim) | Format on save |
| [nvim-lint](https://github.com/mfussenegger/nvim-lint) | Linters outside LSP |

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

Formatters, linters and debug adapters installed by Mason:

- stylua (Lua), prettier (Web), shfmt (Shell)
- ruff (Python format + lint), shellcheck (Shell lint)
- debugpy (Python debug), delve (Go debug)

Debugging and test running currently cover **Python and Go**. Java keeps LSP
only: driving jdtls debug/test needs `nvim-jdtls` plus extra bundles, which is
tracked as separate work.

## Commands

### Setup Script

```bash
./setup.sh              # Full installation
./setup.sh --backup     # Backup existing config
./setup.sh --update     # Sync init.lua/lua/ config, then update plugins and LSP servers
./setup.sh --help       # Show help
NVIM_SETUP_STRICT=1 ./setup.sh   # fail if plugin / treesitter sync is incomplete
NVIM_SETUP_QUIET=1 ./setup.sh    # hide headless progress (Docker/BuildKit log limits)
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

### 2026-08-17 — 镜像构建时 Lazy sync 进度把 BuildKit 日志打满

**表象**：`bash docker/alinux3/bake.sh` 在 `Installing plugins` 阶段被掐掉，日志停在某个插件 `clone | remote: Counting objects`，没有 Docker `ERROR: failed to solve`。

**根因**：lazy.nvim 对每个 git clone 刷百分比。BuildKit 默认步进日志约 1MiB，打满后客户端断开，整个 RUN 失败。

**解法**：`NVIM_SETUP_QUIET=1` 时 `_nvim_headless` 把进度写到临时文件，失败才打印末尾。`alinux3` Dockerfile 构建期同时设置 `NVIM_SETUP_STRICT=1` 与 `NVIM_SETUP_QUIET=1`。

### 2026-08-16 — 构建期没装上 bashls，打开 setup.sh 时 gd/gr 没反应

**表象**：`alinux3-devbox` 里 `nvim setup.sh` 按 `gd` / `gr` 没有映射、没有结果。`:LspInfo` 无 client。

**根因**：`setup.sh` 的「Installing LSP servers」只跑 `MasonToolsInstallSync`，它只安装 `mason-tool-installer` 名单。`bashls` 写在 `mason-lspconfig` 的 `ensure_installed` 里，那是异步的，headless `qa!` 还没下完就退出。`gd`/`gr` 只在 `LspAttach` 后绑定。

**解法**：把常用 LSP（`bashls`、`lua_ls`、`pyright`、`jsonls`、`yamlls`、`ts_ls`）放进 `mason-tool-installer`；`NVIM_SETUP_STRICT=1` 时校验 `~/.local/share/nvim/mason/packages/bash-language-server` 等目录。`gopls` / `clangd` 仍只由 `mason-lspconfig` 按需安装。已有环境：

```bash
cd editors/nvim && ./setup.sh --update
```

### 2026-08-15 — headless Lazy sync 未等克隆结束，镜像里打开文件会全量装插件

**表象**：`alinux3-devbox` 里第一次 `nvim <file>` 会 clone 全部 lazy 插件。

**根因**：构建期 `ENV HOME=/home/admin` 让 root 先占用 `~/.cache`，`admin` 无法创建 `~/.cache/nvim`，lazy.setup 失败后插件不会 clone。失败原先只告警。

**解法**：在 bootstrap 前 `chown` `/home/admin`；`Lazy! sync` 后校验插件目录。容器构建设置 `NVIM_SETUP_STRICT=1`，缺插件即失败。

### 2026-08-09 — Neovim 0.12.x 打开文件时报 treesitter highlighter 崩溃

**表象**：macOS（Homebrew nvim ≥ 0.12）打开 `setup.sh` 等文件时反复报
`Decoration provider "start" (ns=nvim.treesitter.highlighter) ... treesitter.lua:197: attempt to call method 'range' (a nil value)`。

**根因**：`nvim-treesitter` 被钉在 `branch = "master"`（注释误以为 master 是重写版）。上游默认分支已改为 `main`（完整重写版，需 Neovim 0.12+），`master` 是锁定给 Neovim ≤ 0.11 的旧版兼容分支并正在归档；在 0.12.x 上旧分支的 highlighter 解析路径直接崩溃。另：telescope 0.1.x 的 previewer 依赖 `nvim-treesitter.parsers.ft_to_lang()`/`configs.*`，这些在 `main` 重写版被移除，0.12 上 `gr` 预览与 `<leader>/` 都会报 `attempt to call field 'ft_to_lang' (a nil value)`。

**解法**：按宿主 nvim 版本选分支——≥ 0.12 用 `main`（重写版，parser 装到 `~/.local/share/nvim/site`，需 `brew install tree-sitter-cli` 编译 parser；注意 `tree-sitter` 公式只含 C 库无 CLI），< 0.12 保持 `master`（Linux 0.10.4 / glibc 2.32 基线不变）。telescope 同样按版本分支：≥ 0.12 用 `master`（≥ v0.11.7，原生 `vim.treesitter`），< 0.12 保持 `0.1.x`。更新后执行：

```bash
brew install tree-sitter-cli   # macOS，仅 ≥ 0.12 需要
brew install go                # gopls 由 mason 经 `go install` 安装，需 Go 工具链
./setup.sh --update
```

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

### 2026-07-31 — 引入 conform 后与手写的行尾空白清理冲突

**表象**：接入 conform 的保存时格式化后，`:FormatToggle` 关掉自动格式化，保存时行尾空白仍被删除。

**根因**：`config/autocmds.lua` 里有一条无条件的 `BufWritePre` `%s/\s\+$//e`，与 conform 抢同一个事件。
它还会吃掉 Markdown 用于换行的两个行尾空格。

**解法**：删除该 autocmd。conform 覆盖的格式化器（stylua / prettier / shfmt / gofmt / ruff）本身就会处理行尾空白。

### 2026-07-31 — nvim-lint 在 linter 未安装时每次保存报 ENOENT

**表象**：打开或保存 Python 文件时报 `Error running ruff: ENOENT: no such file or directory`。

**根因**：`try_lint()` 会无条件启动 `linters_by_ft` 里的每个 linter，Mason 尚未装好对应二进制时直接抛错。

**解法**：`lint.lua` 在触发前用 `vim.fn.executable()` 过滤，只运行已安装的 linter；一个都没有就跳过。

### 2026-07-31 — lazy 加载插件未声明 `cmd`，Ex 命令补全缺失

**表象**：安装/`--update` 后输入 `:Copilot`、`:DapContinue`、`:Neotest` 无补全、命令不存在；先按过快捷键或进过插入模式后又可用。

**根因**：lazy.nvim 仅在 `cmd` / `keys` / `event` 等触发器命中后才加载插件。`copilot.vim` 只有 `event = InsertEnter`，`nvim-dap` / `neotest` 只有 `keys`，都没有预挂 `cmd` stub，因此插件自带的 user command 在首次触发前未注册。

**解法**：为这三个插件补上对应 `cmd`（保留原有 `event`/`keys`）。同类已正确声明的有 lazygit / trouble / aerial / toggleterm / grug-far / conform。生效：`./setup.sh --update` 后重启 Neovim，无需清 lazy 缓存。

### 2026-07-31 — `<Tab>` 只确认 cmp，有 Copilot 幽灵字时变成插入 Tab

**表象**：关闭 cmp 菜单后按 `<Tab>` 插入制表符/缩进，不接受已显示的 Copilot 幽灵建议；`<C-j>` / `<CR>` 才能接受。

**根因**：为避免与 cmp 抢键，配置了 `copilot_no_tab_map = true`，且 cmp 的 `<Tab>` 只在 `cmp.visible()` 时 `confirm`，否则直接 `fallback()`，没有检查 Copilot。

**解法**：`<Tab>` 优先级改为「cmp 可见 → confirm；否则有幽灵字 → `copilot#Accept`；否则缩进」。仍禁用 Copilot 自带 Tab 映射，由 `completion.lua` 统一处理。`./setup.sh --update` 后重启生效。

### 2026-07-31 — treesitter parser 安装报 `Error during tarball extraction`

**表象**：`./setup.sh --update` 或 `:TSUpdate` 时出现
`nvim-treesitter[bash]: Error during tarball extraction` /
`tree-sitter-bash.tar.gz: Cannot open: No such file or directory`。

**根因**：默认用 curl 拉 GitHub archive 再 `tar` 解压；下载失败或不完整时解压找不到文件。另有 `auto_install` 与 `ensure_installed` / Lazy `build = :TSUpdate` 并发装同一 parser 的竞态。

**解法**：`prefer_git = true`（改用 git clone）；`auto_install = false`（只靠 `ensure_installed` + `:TSUpdate`）。生效后执行 `./setup.sh --update`，若仍失败可手动 `:TSInstall bash`。

### 2026-07-31 — `<CR>` 不确认 nvim-cmp

**表象**：补全菜单打开时按 Enter 只会换行，不能接受当前 cmp 项（只能用 Tab）。

**根因**：此前为避免误确认，`<CR>` 只处理 Copilot 幽灵字，从不调用 `cmp.confirm`。

**解法**：`<CR>` 与 `<Tab>` 同优先级——cmp 可见 → confirm；否则 Copilot；否则换行。

### 2026-07-31 — 手动 cmp 快捷键与 tmux / Copilot 抢键

**表象**：`<C-Space>` 打开 cmp 会撞 tmux 前缀；把手动补全改到 `<C-S-g>` 后又与「主动请求 Copilot」抢键，优先级来回改体验不稳。

**根因**：tmux prefix=`C-Space`；插入模式快捷键有限，cmp 手动补全与 Copilot suggest 不宜再抢同一套修饰键。

**解法**：去掉 nvim-cmp 的手动 `complete()` 快捷键（仍自动弹菜单，可用 `<C-n>`/`<C-p>` 选择）。`<C-S-g>` 专用于关闭 cmp 并 `copilot#Suggest()`。`<Tab>`/`<CR>` 恢复为「cmp → Copilot → 缩进/换行」。

### 2026-07-31 — 首次打开 Neovim 后 Copilot 不工作，需 `:Copilot restart`

**表象**：新开 nvim 进入插入模式没有幽灵提示；执行 `:Copilot` / restart 之后才开始工作。

**根因**：`copilot.vim` 只在 `VimEnter` 里调用 `copilot#Init()`。插件用 `event = InsertEnter` 懒加载时，`VimEnter` 已过，Init 从未执行，语言服务不启动。

**解法**：改为 `event = VeryLazy`，并在 `config` 里 `vim.schedule` 调用 `copilot#Init()`，补上错过的初始化。

## References

- [Neovim Documentation](https://neovim.io/doc/)
- [Lazy.nvim Documentation](https://lazy.folke.io/)
- [Lua Guide for Neovim](https://neovim.io/doc/user/lua-guide.html)
