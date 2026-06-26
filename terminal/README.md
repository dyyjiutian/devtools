# Terminal 配置指南

本目录包含终端模拟器、Shell 插件、编辑器和工具的配置脚本。

## 目录结构

```
terminal/
├── bash/             # 轻量级 Bash 插件方案
├── ghostty/          # Ghostty 终端模拟器
├── iterm2/           # iTerm2 配置（macOS）
├── nvim/             # Neovim 配置
├── oh-my-zsh/        # Oh My Zsh 方案（提示符 + 插件）
├── starship/         # Starship 提示符配置
├── tmux/             # tmux 终端复用器配置
├── vim/              # Vim 配置
├── yazi/             # Yazi 文件管理器配置
└── zsh/              # 轻量级 Zsh 插件方案（推荐）
```

---

## Zsh 配置实践

Zsh 下有两种方案，按需二选一。

### 方案 A：轻量级插件（推荐）

不依赖 Oh My Zsh 框架，启动更快，配置更透明。

**安装插件：**

| 插件 | 功能 |
|------|------|
| zsh-autosuggestions | 灰色历史命令建议，右方向键接受 |
| zsh-syntax-highlighting | 输入时实时语法高亮 |
| zoxide | 智能目录跳转，替代 `z` / `autojump` |
| fzf | 模糊搜索：历史命令、文件、目录 |
| starship | 跨 Shell 提示符，显示 Git 状态、语言版本、命令耗时 |

**执行脚本：**

```bash
cd terminal/zsh
./setup.sh           # 完整安装并写入 ~/.zshrc
./setup.sh --dry-run # 预览将要执行的操作
```

脚本会：
1. 通过 Homebrew（macOS）或 curl/git（Linux）安装上述工具
2. 在 `~/.zshrc` 末尾写入统一配置块（有 marker 防止重复）
3. 自动检测 Oh My Zsh 并给出共存提示

**激活配置：**

```bash
source ~/.zshrc   # 或重新打开终端
```

**常用快捷键：**

| 快捷键 | 功能 |
|--------|------|
| `Ctrl+R` | fzf 模糊搜索历史命令 |
| `Ctrl+T` | fzf 模糊查找当前目录文件 |
| `Alt+C` | fzf 模糊跳转子目录 |
| `→` / `Tab` | 接受 autosuggestions 建议 |
| `z <关键词>` | zoxide 跳转常用目录 |
| `zi` | zoxide 交互式目录选择（需要 fzf）|

> **注意**：zoxide 需要先积累记录。激活后正常使用 `cd` 进入几个目录，之后 `z <关键词>` 才会生效。

---

### 方案 B：Oh My Zsh

功能丰富，有大量内置插件，但启动速度相对较慢。

**包含内容：**

| 组件 | 说明 |
|------|------|
| powerlevel10k | 高度可定制的提示符主题，含 Git 状态 |
| zsh-autosuggestions | 历史命令建议 |
| zsh-syntax-highlighting | 实时语法高亮 |
| z（内置） | 目录跳转（Oh My Zsh 内置，非 zoxide） |
| git（内置） | Git 别名和函数 |
| web-search（内置） | 终端直接搜索网页 |
| Meslo LG Nerd Font | powerlevel10k 图标所需字体 |

**执行脚本：**

```bash
cd terminal/oh-my-zsh
./setup.sh           # 安装并配置 Oh My Zsh
./setup.sh --dry-run # 预览操作
```

脚本会：
1. 检测并安装 Oh My Zsh（未安装时询问）
2. 安装 powerlevel10k 主题并恢复 `.p10k.zsh` 配置
3. 安装 zsh-autosuggestions、zsh-syntax-highlighting
4. 设置插件列表，禁用自动更新
5. 通过 Homebrew 安装 Meslo LG Nerd Font

**激活配置：**

```bash
source ~/.zshrc
# 首次运行若未恢复 .p10k.zsh，会自动进入 p10k 向导
p10k configure    # 手动重新配置主题
```

> **注意**：Starship（方案 A）和 powerlevel10k（方案 B）都是提示符方案，只选其中一种，勿同时初始化。

---

## Bash 配置实践

Bash 可通过 `terminal/bash/setup.sh` 自动安装常用工具并写入 `~/.bashrc`，以下为手动配置参考。

### 推荐工具

| 工具 | 功能 | 安装 |
|------|------|------|
| bash-completion | Tab 补全增强 | `brew install bash-completion@2` (macOS) / `apt install bash-completion` (Linux) |
| starship | 提示符（与 Zsh 共用同一份配置） | `brew install starship` |
| fzf | 模糊搜索 | `brew install fzf` / `git clone fzf` |
| zoxide | 智能目录跳转 | `brew install zoxide` |

### 配置步骤

**1. 安装工具（macOS）**

```bash
brew install bash-completion@2 starship fzf zoxide
```

**2. 写入 `~/.bashrc`（或 `~/.bash_profile`）**

```bash
# bash-completion（macOS 需要指定路径）
[[ -r "$(brew --prefix)/etc/profile.d/bash_completion.sh" ]] && \
    source "$(brew --prefix)/etc/profile.d/bash_completion.sh"

# fzf
eval "$(fzf --bash)"

# zoxide（z 命令）
eval "$(zoxide init bash)"

# starship 提示符
eval "$(starship init bash)"
```

**Linux 版本（以 Debian/Ubuntu 为例）：**

```bash
# bash-completion
[[ -f /usr/share/bash-completion/bash_completion ]] && \
    source /usr/share/bash-completion/bash_completion

# fzf（通过 git 安装后）
[[ -f ~/.fzf.bash ]] && source ~/.fzf.bash

# zoxide
command -v zoxide &>/dev/null && eval "$(zoxide init bash)"

# starship
eval "$(starship init bash)"
```

**3. 激活配置**

```bash
source ~/.bashrc
```

**常用快捷键：**

| 快捷键 | 功能 |
|--------|------|
| `Ctrl+R` | fzf 模糊搜索历史命令 |
| `Ctrl+T` | fzf 模糊查找当前目录文件 |
| `Alt+C` | fzf 模糊跳转子目录 |
| `z <关键词>` | zoxide 跳转常用目录 |
| `Tab` | bash-completion 增强补全 |

> **注意**：zoxide 同样需要先通过 `cd` 积累目录记录后才能使用 `z`。

---

## Starship 提示符配置

Zsh 和 Bash 共用同一份 Starship 配置，位于：

```
terminal/starship/starship.toml        # 主配置（自定义主题）
terminal/starship/starship-tokyo.toml  # Tokyo Night 风格配置
```

**部署配置：**

```bash
# 主配置
cp terminal/starship/starship.toml ~/.config/starship.toml

# 或 Tokyo Night 风格
cp terminal/starship/starship-tokyo.toml ~/.config/starship.toml
```

提示符包含：用户名 → 主机名（SSH 时）→ 目录 → Git 分支 / 状态，右侧显示语言版本和命令耗时。

---

## 其他工具配置

| 目录 | 说明 | 脚本 |
|------|------|------|
| `bash/` | Bash 插件 + Starship 初始化 | `./setup.sh` |
| `ghostty/` | Ghostty 终端 | `./setup.sh` |
| `starship/` | Starship 配置模板 | 手动复制或由 bash/zsh setup 部署 |
| `nvim/` | Neovim（lazy.nvim + LSP） | `./setup.sh` |
| `vim/` | Vim（vim-plug + coc.nvim） | `./setup.sh` |
| `yazi/` | Yazi 文件管理器 | `./setup.sh` |
| `iterm2/` | iTerm2 配置导入 | 手动导入 `config/` |
| `tmux/` | tmux 配置 | `cp tmux.conf ~/.tmux.conf` |
