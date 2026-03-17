# Cursor 配置指南

## 目录

- [配置文件说明](#配置文件说明)
- [备份配置](#备份配置)
- [在新机器上还原配置](#在新机器上还原配置)
- [插件管理](#插件管理)
- [快捷键说明](#快捷键说明)

---

## 配置文件说明

本目录存放 Cursor 的核心配置文件备份，可用于在新机器上快速复现开发环境。

| 文件 | 说明 |
|------|------|
| `settings.json` | 编辑器全局设置 |
| `keybindings.json` | 自定义快捷键绑定 |
| `extensions.txt` | 已安装插件列表 |

macOS 上 Cursor 配置文件的原始路径：

```
~/Library/Application Support/Cursor/User/settings.json
~/Library/Application Support/Cursor/User/keybindings.json
```

插件安装目录：

```
~/.cursor/extensions/
```

---

## 备份配置

### 备份 settings.json 和 keybindings.json

```bash
CURSOR_CONFIG="$HOME/Library/Application Support/Cursor/User"
REPO_DIR="$(git rev-parse --show-toplevel)/editors/cursor/config"

cp "$CURSOR_CONFIG/settings.json"   "$REPO_DIR/settings.json"
cp "$CURSOR_CONFIG/keybindings.json" "$REPO_DIR/keybindings.json"
```

### 导出插件列表

```bash
cursor --list-extensions > editors/cursor/config/extensions.txt
```

> 如果 `cursor` 命令不存在，在 Cursor 中执行 `Shell Command: Install 'cursor' command in PATH` 即可（Command Palette → `⌘⇧P`）。

---

## 在新机器上还原配置

### 第一步：安装 Cursor

从 [cursor.com](https://www.cursor.com/) 下载并安装，然后在 Command Palette 中执行 `Shell Command: Install 'cursor' command in PATH` 注册 CLI。

### 第二步：复制配置文件

```bash
CURSOR_CONFIG="$HOME/Library/Application Support/Cursor/User"
REPO_DIR="path/to/devtools/editors/cursor/config"

cp "$REPO_DIR/settings.json"   "$CURSOR_CONFIG/settings.json"
cp "$REPO_DIR/keybindings.json" "$CURSOR_CONFIG/keybindings.json"
```

### 第三步：批量安装插件

```bash
cat path/to/devtools/editors/cursor/config/extensions.txt | xargs -L1 cursor --install-extension
```

安装完成后重启 Cursor 使所有插件生效。

---

## 插件管理

### 当前已安装插件

| 插件 ID | 说明 |
|---------|------|
| `anysphere.remote-ssh` | SSH 远程开发 |
| `anthropic.claude-code` | Claude AI 编程助手 |
| `k--kato.intellij-idea-keybindings` | IntelliJ IDEA 风格快捷键 |

### 查看已安装插件

```bash
cursor --list-extensions
```

### 安装单个插件

```bash
cursor --install-extension <extension-id>
```

### 卸载插件

```bash
cursor --uninstall-extension <extension-id>
```

---

## 快捷键说明

以下为 `keybindings.json` 中自定义的快捷键：

| 快捷键 | 功能 |
|--------|------|
| `⌥J` | 在文件树中定位当前打开的文件 |
| `⌘J` | 打开 / 切换集成终端面板 |
| `⇧⌘J` | 在当前文件所在目录打开新终端 |
