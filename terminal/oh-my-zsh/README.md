# Oh My Zsh 配置

本项目提供自动化脚本来配置 Oh My Zsh，包括主题设置、插件启用和第三方插件安装。

## 什么是 Oh My Zsh?

[Oh My Zsh](https://ohmyz.sh/) 是一个社区驱动的开源框架，用于管理 Zsh 配置。它带有数千个有用的函数、插件、主题等，让你的终端更强大、更易用。

## 安装 Oh My Zsh

### 前置要求

- 已安装 [Zsh](http://www.zsh.org) (v5.0.8 或更高版本)
- 已安装 [Git](https://git-scm.com)
- 已安装 [curl](https://curl.se) 或 [wget](https://www.gnu.org/software/wget/)

### 安装命令

使用 curl:
```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

或使用 wget:
```bash
sh -c "$(wget https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -O -)"
```

> 安装脚本会自动备份现有的 `.zshrc` 文件。

## 使用本项目的配置脚本

### 快速开始

```bash
chmod +x setup.sh
./setup.sh
```

### 查看帮助

```bash
./setup.sh --help
```

### 试运行模式

查看脚本将要执行的修改，但不实际修改文件：

```bash
./setup.sh --dry-run
```

## 脚本功能说明

本脚本 (`setup.sh`) 会自动完成以下配置：

### 1. 配置恢复

- **检测原配置**: 检查 `~/.zshrc.pre-oh-my-zsh`（Oh My Zsh 安装时的默认备份）
- **显示差异**: 对比原配置与当前配置的差异
- **智能恢复**: 提示用户是否将差异部分追加到现有配置

### 2. 主题设置

- **主题**: `powerlevel10k/powerlevel10k`
- [Powerlevel10k](https://github.com/romkatv/powerlevel10k) 是一个高性能的 Zsh 主题，强调速度、灵活性和开箱即用体验
- 支持丰富的提示符段落：git 状态、命令执行时间、Python 虚拟环境、Node.js 版本等
- 脚本会自动安装主题并恢复备份的 `.p10k.zsh` 配置文件
- 需要安装 [Nerd Fonts](https://www.nerdfonts.com/) 才能正确显示图标

### 3. p10k 配置恢复

- 脚本会自动将项目中备份的 `.p10k.zsh` 恢复到 `~/.p10k.zsh`
- 如需重新配置，运行 `p10k configure`

### 4. 禁用自动更新

- **配置项**: `DISABLE_AUTO_UPDATE="true"`
- Oh My Zsh 默认会定期检查更新，禁用后避免更新提示干扰
- 如需手动更新，可运行 `omz update`

### 5. 内置插件

启用的 Oh My Zsh 内置插件：

| 插件 | 功能描述 |
|------|---------|
| `git` | 提供 git 别名和自动补全 |
| `z` | 目录快速跳转，基于访问频率的智能跳转 |
| `web-search` | 在命令行中进行网络搜索，支持 Google、Bing、GitHub 等 |

### 6. 第三方插件

自动从 GitHub 安装：

| 插件 | 功能描述 | 仓库地址 |
|------|---------|---------|
| `zsh-autosuggestions` | 根据历史记录自动建议命令，按 → 键接受 | [zsh-users/zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) |
| `zsh-syntax-highlighting` | Fish shell 风格的语法高亮，命令输入时实时显示合法性 | [zsh-users/zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting) |

### 7. 字体自动安装

- **字体**: Meslo LG Nerd Font
- **安装方式**: 自动通过 Homebrew 安装 (`font-meslo-lg-nerd-font`)
- **用途**: 为 powerlevel10k 主题提供图标和特殊字符支持
- **要求**: 系统已安装 Homebrew

如果你想手动配置，可以参考以下步骤：

### 修改主题

编辑 `~/.zshrc`：
```bash
ZSH_THEME="powerlevel10k/powerlevel10k"
```

### 禁用自动更新

编辑 `~/.zshrc`，在 `ZSH_THEME` 行后添加：
```bash
DISABLE_AUTO_UPDATE="true"
```

如需手动更新 Oh My Zsh，运行：
```bash
omz update
```

### 启用插件

编辑 `~/.zshrc` 中的 `plugins` 行：
```bash
plugins=(git z web-search zsh-autosuggestions zsh-syntax-highlighting)
```

### 安装第三方插件

```bash
# zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

# zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-syntax-highlighting ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
```

### 应用更改

```bash
source ~/.zshrc
```

### 安装 powerlevel10k 主题

```bash
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/themes/powerlevel10k
```

## 推荐字体

powerlevel10k 主题需要 Nerd Font 字体支持。本脚本会自动通过 Homebrew 安装 **MesloLGS NF** 字体。

### 自动安装

脚本会自动执行：
```bash
brew install --cask font-meslo-lg-nerd-font
```

### 手动安装

如未使用脚本或需要重新安装：

```bash
brew install --cask font-meslo-lg-nerd-font
```

### 其他字体选择

- [Powerline Fonts](https://github.com/powerline/fonts)
- [Nerd Fonts](https://www.nerdfonts.com/font-downloads)

### 终端字体设置

安装后在终端设置中将字体更改为 "MesloLGS NF" 或类似的 Powerline 字体。

## 常用快捷键

| 快捷键 | 功能 |
|--------|------|
| `→` 或 `End` | 接受自动建议 |
| `Ctrl + R` | 搜索命令历史 |
| `z <目录名>` | 快速跳转到常用目录 |
| `d` | 列出访问过的目录，输入数字快速跳转 |

## 官方文档和参考链接

- **官方网站**: https://ohmyz.sh/
- **GitHub 仓库**: https://github.com/ohmyzsh/ohmyzsh
- **Wiki 文档**: https://github.com/ohmyzsh/ohmyzsh/wiki
- **主题画廊**: https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
- **插件列表**: https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins
- **第三方插件**: https://github.com/ohmyzsh/ohmyzsh/wiki/Plugins-Overview
- **Zsh 文档**: https://zsh.sourceforge.io/Doc/

## 注意事项

### 配置文件备份

运行本脚本会自动备份和检查以下文件：

| 备份类型 | 文件路径 | 说明 |
|---------|---------|------|
| Oh My Zsh 原始备份 | `~/.zshrc.pre-oh-my-zsh` | Oh My Zsh 安装时自动备份的原始配置 |
| 脚本运行备份 | `~/.zshrc.backup.YYYYMMDD_HHMMSS` | 本脚本运行前自动创建的备份 |
| p10k 配置备份 | `.p10k.zsh` (项目根目录) | powerlevel10k 配置备份，脚本运行时自动恢复到 `~/.p10k.zsh` |

### 配置恢复流程

1. 脚本首先检查 `~/.zshrc.pre-oh-my-zsh` 是否存在
2. 如存在，计算原配置与当前配置的差异
3. 显示差异内容（最多20行）并询问是否恢复
4. 确认后，差异内容将追加到现有 `~/.zshrc` 末尾

### 手动禁用自动更新

如需手动修改禁用自动更新，编辑 `~/.zshrc`：

```bash
DISABLE_AUTO_UPDATE="true"
```

### 安全提示

- 建议先使用 `--dry-run` 试运行查看将要执行的修改
- 脚本会创建备份，但重要配置建议自行额外备份
- 恢复配置时请仔细查看差异，避免重复或冲突的配置

## 故障排除

### 主题显示乱码
- 确保终端字体设置为 Nerd Font
- 推荐字体: MesloLGS NF, JetBrainsMono Nerd Font
- 运行 `p10k configure` 重新配置主题

### 语法高亮不生效
- 确保 `zsh-syntax-highlighting` 是插件列表中的最后一个
- 执行 `source ~/.zshrc` 重新加载配置

### 自动建议不显示
- 检查 `${ZSH_CUSTOM}/plugins/zsh-autosuggestions` 目录是否存在
- 确保终端支持 256 色

## 许可证

本项目遵循与 Oh My Zsh 相同的许可证。

