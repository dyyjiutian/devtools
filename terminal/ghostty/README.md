# Ghostty 配置

现代化的 Ghostty 终端配置方案。Starship 提示符模板已抽到 `shell/starship/`，本脚本可复用该通用配置。

## 特性

### Ghostty 终端
- **GPU 加速**: 基于 Metal (macOS) 的高性能渲染
- **主题**: 内置 Catppuccin、Tokyo Night、Dracula 等主题
- **窗口管理**: 标签页、分割窗口、快速终端
- **字体**: 支持 Nerd Font 图标
- **快捷键**: 丰富的自定义快捷键绑定

## 文件结构

```
terminal/ghostty/
├── setup.sh           # 安装脚本
├── ghostty.config     # Ghostty 配置文件
└── README.md          # 本文件
```

## 快速开始

### 完整安装

```bash
cd terminal/ghostty
./setup.sh
```

### 试运行（查看将要执行的操作）

```bash
./setup.sh --dry-run
```

### 自定义安装

```bash
# 跳过字体安装
./setup.sh --skip-fonts

# 仅应用 Starship 配置
./setup.sh --skip-ghostty

# 仅安装 Ghostty
./setup.sh --skip-starship

# 卸载配置
./setup.sh --uninstall
```

## 配置详情

### Starship 配置

Starship 配置模板位于 `shell/starship/starship.toml`。运行本脚本且未指定 `--skip-starship` 时，会复制该模板到 `~/.config/starship.toml`。

#### 自定义

```bash
# 编辑配置
starship config

# 预览配置效果
eval "$(starship init zsh)"

# 查看预设主题
starship preset
```

### Ghostty 配置 (`ghostty.config`)

- **主题**: Catppuccin Mocha (深色)
- **字体**: JetBrainsMono Nerd Font (14pt)
- **窗口**: 140x40 字符，半透明背景
- **透明度**: 95%，背景模糊
- **滚动历史**: 100,000 行

#### 快捷键

| 快捷键 | 功能 |
|--------|------|
| `Cmd + T` | 新建标签页 |
| `Cmd + W` | 关闭标签页 |
| `Cmd + 数字` | 切换到指定标签页 |
| `Cmd + D` | 垂直分割窗口 |
| `Cmd + Shift + D` | 水平分割窗口 |
| `Cmd + Alt + 方向键` | 在分割窗口间导航 |
| `Cmd + +` | 增大字体 |
| `Cmd + -` | 减小字体 |
| `Cmd + 0` | 重置字体 |
| `Cmd + Ctrl + F` | 全屏 |

#### 自定义

```bash
# 查看所有配置选项
ghostty +show-config --default --docs

# 查看可用主题
ghostty +list-themes

# 编辑配置
gedit ~/Library/Application\ Support/com.mitchellh.ghostty/config
```

## 依赖要求

### macOS
- Homebrew
- macOS 11+ (Big Sur 或更新)

### Linux
- 需要手动编译 Ghostty
- 参考: https://ghostty.org/docs/install/build

## 与其他配置的关系

此配置与项目中的其他终端配置互补：

| 配置 | 用途 |
|------|------|
| `oh-my-zsh/` | Zsh 配置（与 Starship 互斥，二选一）|
| `nvim/` | Neovim 编辑器配置 |
| `tmux/` | 终端复用器配置 |
| `ghostty/` | 本配置：终端模拟器 + 提示符 |

**注意**: Starship 和 Oh My Zsh 的 powerlevel10k 主题都是提示符方案，建议只使用其中一种。

## 故障排除

### 字体图标不显示

1. 确保已安装 JetBrainsMono Nerd Font：
   ```bash
   brew list --cask font-jetbrains-mono-nerd-font
   ```

2. 在 Ghostty 设置中手动选择字体

### Starship 不生效

1. 检查初始化是否已添加到 shell 配置：
   ```bash
   grep "starship init" ~/.zshrc
   ```

2. 手动添加：
   ```bash
   echo 'eval "$(starship init zsh)"' >> ~/.zshrc
   ```

3. 重新加载配置：
   ```bash
   source ~/.zshrc
   ```

### Ghostty 无法启动

1. 检查 macOS 版本是否 >= 11.0
2. 检查是否有权限问题：
   ```bash
   xattr -dr com.apple.quarantine /Applications/Ghostty.app
   ```

## 参考链接

- [Ghostty 文档](https://ghostty.org/docs)
- [Starship 文档](https://starship.rs)
- [Nerd Fonts](https://www.nerdfonts.com/)
