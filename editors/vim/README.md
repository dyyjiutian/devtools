#Vim 配置

一套开箱即用的 Vim 开发环境配置，使用 [vim-plug](https://github.com/junegunn/vim-plug) 管理插件，集成代码补全、文件导航、模糊搜索、Git 集成等常用功能。

## 快速安装

```bash
./setup.sh
```

脚本会自动完成以下操作：

1. 安装系统依赖（vim、node、ctags、fzf、ripgrep）
2. 备份已有的 `~/.vimrc`（普通文件），然后复制本配置覆盖到 `~/.vimrc`
3. 安装 vim-plug 及所有插件
4. 安装 coc.nvim 语言服务器（Python、Go、Java、Shell、JSON、YAML）

> macOS 通过 Homebrew 安装依赖；Linux 支持 apt-get / dnf / yum。
> 在 Alinux、RHEL 等仓库没有 `fzf` / `ripgrep` 时，会自动从 GitHub 下载二进制到 `~/.local/bin`（优先使用仓库 `cache/binaries/`）。

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

### 2026-07-28 — setup 将 vimrc 软链到仓库路径

**问题表象**

- `setup.sh` 用 `ln -sf` 把 `~/.vimrc` 指到仓库内 `vimrc`，依赖本机仓库路径；移动/删除仓库后配置失效。

**根因**

- 部署策略选择了软链而非复制。

**解法**

- 改为备份已有普通文件后 `cp` 覆盖到 `~/.vimrc`；若目标已是软链则先删除再复制。
- 已有环境可重新执行：`bash editors/vim/setup.sh` 或 `bash editors/vim/setup.sh --restore`。

