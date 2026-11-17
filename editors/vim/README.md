#Vim 配置

一套开箱即用的 Vim 开发环境配置，使用 [vim-plug](https://github.com/junegunn/vim-plug) 管理插件，集成代码补全、文件导航、模糊搜索、Git 集成等常用功能。

## 快速安装

```bash
./setup.sh
./setup.sh --upgrade    # Vim 过旧时升级到 9.2.x 后再装 coc
./setup.sh --dry-run    # 试运行
```

脚本会自动完成以下操作：

1. 安装系统依赖（vim、node、ctags、fzf、ripgrep）
2. 检测 Vim 版本；使用 `--upgrade` 时统一升级到 `VIM_9_TARGET`（默认 `9.2.0782`）
3. 备份已有的 `~/.vimrc`（普通文件），然后复制本配置覆盖到 `~/.vimrc`
4. 安装 vim-plug 及所有插件
5. 安装 coc.nvim 语言服务器（Python、Go、Java、Shell、JSON、YAML）

> macOS 通过 Homebrew 安装依赖；Linux 支持 apt-get / dnf / yum。
> 在 Alinux、RHEL 等仓库没有 `fzf` / `ripgrep` 时，会自动从 GitHub 下载二进制到 `~/.local/bin`（优先使用仓库 `cache/binaries/`）。

### `--upgrade` 目标版本

`--upgrade` 一律升级到 `VIM_9_TARGET`（默认 `9.2.0782`，可用环境变量覆盖），不再按当前 8.x / 9.x 分流。

升级顺序：包管理器（brew / apt / dnf / yum）→ 仍不足则源码编译到 `${VIM_PREFIX:-~/.local}`，并确保 `~/.local/bin` 优先于系统 PATH。未传 `--upgrade` 且版本过低时仍会跳过 coc（与旧行为一致）。
## 插件列表

| 插件 | 用途 |
|------|------|
| [NERDTree](https://github.com/preservim/nerdtree) + vim-devicons | 文件树浏览 |
| [coc.nvim](https://github.com/neoclide/coc.nvim) | 代码补全与 LSP |
| [fzf.vim](https://github.com/junegunn/fzf.vim) | 模糊搜索文件和内容 |
| [vim-fugitive](https://github.com/tpope/vim-fugitive) + vim-gitgutter | Git 集成 |
| [tagbar](https://github.com/preservim/tagbar) + vim-gutentags | 代码结构导航（ctags） |
| [vim-airline](https://github.com/vim-airline/vim-airline) | 状态栏美化 |
| [gruvbox](https://github.com/morhetz/gruvbox) | 配色方案 |
| [vim-polyglot](https://github.com/sheerun/vim-polyglot) | 多语言语法高亮 |
| [auto-pairs](https://github.com/jiangmiao/auto-pairs) | 括号自动配对 |
| [vim-commentary](https://github.com/tpope/vim-commentary) | 快捷注释 |
| [vim-oscyank](https://github.com/ojroques/vim-oscyank)（仅 Linux） | OSC52 远程剪贴板（SSH 下 `,y` 复制到本机） |

## 快捷键

Leader 键为 `,`（逗号）。

### 文件与导航

| 快捷键 | 功能 |
|--------|------|
| `,n` | 打开/关闭文件树 |
| `,f` | 在文件树中定位当前文件 |
| `,t` | 打开/关闭标签侧栏 |
| `,p` | 模糊搜索文件 |
| `,g` | Ripgrep 全文搜索 |
| `,b` | 切换 Buffer |

### 代码编辑（coc.nvim）

| 快捷键 | 功能 |
|--------|------|
| `Tab` / `S-Tab` | 补全列表导航 |
| `Enter` | 确认补全 |
| `gd` | 跳转到定义 |
| `gy` | 跳转到类型定义 |
| `gi` | 跳转到实现 |
| `gr` | 查找引用 |
| `K` | 显示文档 |
| `,rn` | 重命名符号 |
| `[d` / `]d` | 上/下一个诊断 |

### Git

| 快捷键 | 功能 |
|--------|------|
| `,gs` | Git status |
| `,gd` | Git diff（分屏） |
| `,gb` | Git blame |
| `,gl` | Git log |

### 窗口与 Buffer

| 快捷键 | 功能 |
|--------|------|
| `Ctrl-h/j/k/l` | 窗口间移动 |
| `,bn` | 下一个 Buffer |
| `,bp` | 上一个 Buffer |
| `,bd` | 关闭当前 Buffer |
| `,w` | 保存 |
| `,q` | 退出 |
| `,Space` | 清除搜索高亮 |
| `,y` | 复制到系统剪贴板（Linux: OSC52；macOS: `"+`） |
| `,P` | 从系统剪贴板粘贴 |

## 插件管理

本配置使用 [vim-plug](https://github.com/junegunn/vim-plug) 管理插件。

### 安装插件

在 `.vimrc` 中的 `call plug#begin()` 和 `call plug#end()` 之间添加插件声明，然后在 Vim 中执行：

```vim
:PlugInstall
```

### 卸载插件

从 `.vimrc` 中删除对应的 `Plug '...'` 行，然后在 Vim 中执行：

```vim
:PlugClean
```

vim-plug 会提示确认后删除未声明的插件目录。

### 查看插件列表

```vim
:PlugStatus
```

### 更新插件

```vim
:PlugUpdate          " 更新所有插件
:PlugUpdate NERDTree " 更新指定插件
```

### 查看插件帮助文档

在 Vim 中查看某个插件的详细用法：

```vim
:help nerdtree       " 查看 NERDTree 帮助
:help fugitive       " 查看 vim-fugitive 帮助
:help coc-nvim       " 查看 coc.nvim 帮助
```

> 帮助文档的名称通常与插件名一致，可通过 `:help` 后按 `Tab` 补全查找。

## 基础设置

- 配色：gruvbox (dark)
- 行号：绝对行号 + 相对行号
- 缩进：4 空格（Go 使用 Tab，Shell/YAML/JSON 使用 2 空格）
- 搜索：增量搜索、忽略大小写（输入大写时自动区分）
- 鼠标：启用
- 新窗口在下方和右侧打开

## 语言支持

通过 coc.nvim 提供以下语言的补全和诊断：

- **Python** — coc-pyright
- **Go** — coc-go
- **Java** — coc-java
- **Shell** — coc-sh
- **JSON** — coc-json
- **YAML** — coc-yaml

如需添加其他语言支持，在 Vim 中执行：

```vim
:CocInstall coc-<language>
```

## Issues

### 2026-11-17 — coc 要求 Node ≥ 22.15，旧 Node 下 Vim 卡死并烧掉 CI 一小时

**问题表象**

- `vim_ops_linux_ubuntu_e2e_test` TIMEOUT 3600s，整条 e2e-linux 流水线跑了 82 分钟。
- coc 启动即崩：`Current Node.js version v18.19.1 < 22.15.0` / `Please upgrade your Node.js`；
  ops suite 只打印 `PASS: vim opens a real file`，第二个 vim 调用（`Git blame`）再也不退出。

**根因**

- `vimrc` 的 `Plug 'neoclide/coc.nvim', {'branch': 'release'}` 浮动到最新 release，而该 build 硬性要求
  Node ≥ 22.15.0；Ubuntu 24.04 发行版 nodejs 只有 18.19.1。coc 崩溃后 vim 退出被卡住。
- e2e 默认 `size = "enormous"` → 单测试超时 3600s，于是「一个挂起 = 白烧一小时」。
- `setup.sh` 原先只检查 Vim 版本（8.1.1719+），没有 Node 版本门禁。

**解法**

- `vimrc` 先算 `g:coc_enabled = (Vim 版本够) && (Node ≥ 22.15)`；不满足就不加载 coc，走 AutoComplPop 回退，
  coc 的映射与设置同样受该开关保护。
- `setup.sh` 新增 `check_node_version`（ok / old / missing，复用 `version_ge`），不满足就 warn 并跳过 coc 扩展。
- `Dockerfile.e2e.ubuntu` 改用 NodeSource Node 22（与 `os/linux/setup_ubuntu.sh` 同一套做法），构建期断言 ≥ 22.15。
- `install_deps_linux` 新增 `_dep_already_present`：`node`/`npm`/`vim` 已存在就跳过包管理器安装，
  否则 `apt-get install nodejs npm` 会把镜像里（或用户 nvm/NodeSource 装好的）Node 22 换回发行版 18，门禁就白加了。
- ops suite 每次 vim 调用套 `timeout -k 10 120`（macOS 回退 `gtimeout`），挂起 2 分钟内失败而不是拖满超时。
- vim/nvim 的 e2e（docker + host）改 `size = "large"` → 900s；rust/vpn/proxy 等真装慢测试仍保持 enormous
  （rust alinux3 实测 1176s、vpn ubuntu 1039s，降下去会被误杀）。`tests/repository_structure_test.sh` 守住这条约束。

**影响与后续**

- `os/linux/packages.*.list` 仍钉 Node 20（nodesource），低于 coc 门槛：按仓库初始化的机器会走 AutoComplPop
  回退而拿不到 coc。需要 coc 就自行升级到 Node ≥ 22.15（本次未改 packages 列表）。

**验证**

```bash
bazel test --config=l1 //editors/vim:vim_linux_ubuntu_test //editors/vim:vim_macos_test
bazel test --config=l1 //tests:repository_structure_check
# 真实 Ubuntu 容器（需 Docker 与外网）：
bazel test --config=l3 //editors/vim:vim_ops_linux_ubuntu_e2e_test
```

### 2026-08-08 — 大 Git 仓库里 Airline / GitGutter 拖慢打开与 Git 相关操作

**问题表象**

- 在大型 Git 仓库中打开 Vim 或切换 buffer 时，状态栏相关 Git 查询与 gutter 更新明显变慢。

**根因**

- Airline 的 `branch` 扩展会对仓库做分支 / dirty / untracked 检查。
- vim-gitgutter 默认 `base_path` 会执行整库 `git diff --diff-filter=R --name-status`，做 rename 枚举。

**解法**

- `vimrc`：`g:airline#extensions#branch#enabled = 0`。
- `vimrc`：在插件加载后覆盖 `gitgutter#utility#base_path`，按当前文件路径解析，跳过整库 rename 扫描（刚 rename、仍需按旧路径对 index 的极少数场景可能不准）。
- 已有环境重新应用：`bash editors/vim/setup.sh`（或 `--dry-run` 预览）。

### 2026-08-16 — Alinux 3 镜像未升级 Vim，gd/gr 无映射

**问题表象**

- `alinux3-devbox` 里系统 Vim 是 8.0.1763，打开 `setup.sh` 按 `gd` / `gr` 没反应。

**根因**

- coc.nvim 需要 8.1.1719+；`vimrc` 把 `gd`/`gr` 包在 `has('patch-8.1.1719')` 里。镜像 bootstrap 调用 `editors/vim/setup.sh` 时没有 `--upgrade`，安装器按设计跳过 coc。

**解法**

- 镜像改为 `editors/vim/setup.sh --upgrade`（包管理器不够新则源码装到 `~/.local` 的 9.2.x，再装 coc-sh）。
- 已有容器可手动：`bash /opt/devtools/editors/vim/setup.sh --upgrade`。

### 2026-07-30 — Vim 过旧时只能跳过 coc，无法一键升级

**问题表象**

- 系统 Vim（常见于 CentOS/Alinux 的 7.x / 8.0）低于 coc.nvim 要求时，`setup.sh` 仅警告并跳过 coc，需用户自行升级。

**根因**

- 安装器只做版本检测，没有提供可控的升级路径。

**解法**

- 增加 `./setup.sh --upgrade`：按当前大版本选择钉死稳定版，优先包管理器，仍不足则源码安装到 `~/.local`。
- 预览：`bash editors/vim/setup.sh --dry-run --upgrade`。

### 2026-07-28 — setup 将 vimrc 软链到仓库路径

**问题表象**

- `setup.sh` 用 `ln -sf` 把 `~/.vimrc` 指到仓库内 `vimrc`，依赖本机仓库路径；移动/删除仓库后配置失效。

**根因**

- 部署策略选择了软链而非复制。

**解法**

- 改为备份已有普通文件后 `cp` 覆盖到 `~/.vimrc`；若目标已是软链则先删除再复制。
- 已有环境可重新执行：`bash editors/vim/setup.sh` 或 `bash editors/vim/setup.sh --restore`。

### 2026-08-17 — Linux E2E 在 ops 通过后因 `rm -rf $HOME` 失败

**表象**：`vim_ops_linux_*_e2e_test` 已打印 `PASS: vim E2E ops`，Bazel 仍 Exit 1：`rm: cannot remove '.../.npm/_cacache/...': Directory not empty`。

**根因**：Docker overlayfs 上 npm cache 的 `rm -rf` 可能留下非空目录；`run_e2e_test.sh` 的 EXIT trap 因此把成功用例变成失败。

**解法**：cleanup trap 忽略 `rm` 失败。

### 2026-08-17 — GitHub macos E2E 并行 brew 抢 Cellar 锁

**表象**：`vim_ops_macos_e2e_test` 报 `A brew install vim process has already locked /opt/homebrew/Cellar/cmake`。nvim 同 job 里也在 `brew install`。

**根因**：macOS E2E 默认并行，Homebrew 不能同时写 Cellar。

**解法**：`.github/workflows/e2e.yml` 的 macOS job 使用 `--jobs=2`（macos-26 约 3–4 核）。`run_e2e_test.sh` 用目录锁串行化 `brew`，避免并行抢 Cellar。

