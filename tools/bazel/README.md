# Bazel 编译环境

通过 [Bazelisk](https://github.com/bazelbuild/bazelisk) 管理 Bazel 版本，并安装配套开发工具。
支持 **macOS**（Homebrew）和 **Linux**（二进制下载），可重复执行。

## 目录结构

```
tools/bazel/
├── setup.sh    # 安装脚本
└── README.md   # 本文档
```

## 快速开始

```bash
cd tools/bazel
./setup.sh
```

## 安装内容

| 工具 | macOS | Linux | 说明 |
|------|-------|-------|------|
| [bazelisk](https://github.com/bazelbuild/bazelisk) | `brew install bazelisk` | GitHub Releases 二进制 | Bazel 版本管理器，接管 `bazel` 命令 |
| [buildifier](https://github.com/bazelbuild/buildtools) | `brew install buildifier` | GitHub Releases 二进制 | BUILD / `.bzl` 文件格式化工具 |
| [starpls](https://github.com/withered-magic/starpls) | `brew install withered-magic/brew/starpls` | GitHub Releases 二进制 | Starlark 语言服务器（LSP） |

安装完成后：
- `~/.bazeliskrc` 中写入 `USE_BAZEL_VERSION=9.0.0`，使 bazelisk 全局默认使用该版本
- `~/.config/bazel/` 中存放 bash 和 zsh 补全脚本
- `~/.bashrc` 和 `~/.zshrc` 中写入补全配置

## 脚本选项

```
用法:
  ./setup.sh [选项]

选项:
  -h, --help              显示帮助信息
  --bazel-version <ver>   指定默认 Bazel 版本（默认: 9.0.0）
  --skip-bazelisk         跳过 Bazelisk 安装
  --skip-buildifier       跳过 Buildifier 安装
  --skip-starpls          跳过 Starpls 安装
  --skip-completion       跳过 Shell 补全配置
  --dry-run               预览操作，不实际执行

示例:
  ./setup.sh                          # 完整安装
  ./setup.sh --bazel-version 8.0.0    # 默认使用 Bazel 8
  ./setup.sh --skip-starpls           # 不安装 starpls
  ./setup.sh --dry-run                # 预览安装步骤
```

## Bazel 版本管理

bazelisk 按以下优先级决定使用哪个 Bazel 版本：

1. `USE_BAZEL_VERSION` 环境变量
2. 工作区根目录的 `.bazelversion` 文件
3. `~/.bazeliskrc`（本脚本配置）

### `~/.bazeliskrc`

脚本通过 `~/.bazeliskrc` 设置全局默认版本（纯 `KEY=VALUE` 格式，bazelisk 原生读取，无需 shell 语法）：

```
USE_BAZEL_VERSION=9.0.0
```

重复执行脚本会自动更新该文件中的版本号，不会产生重复配置。

在项目中固定版本（优先级更高）：

```bash
echo "9.0.0" > .bazelversion
```

临时切换版本：

```bash
USE_BAZEL_VERSION=8.0.0 bazel version
```

## Shell 补全

补全脚本下载自 Bazel GitHub（版本对应 `--bazel-version`），存放于 `~/.config/bazel/`。

### Bash

`~/.bashrc` 中写入：

```bash
# Bazel bash completion
[ -f "~/.config/bazel/bazel-complete.bash" ] && source "~/.config/bazel/bazel-complete.bash"
```

### Zsh

`~/.zshrc` 中写入：

```zsh
# Bazel zsh completion
if [[ -d "~/.config/bazel" ]]; then
  fpath=("~/.config/bazel" $fpath)
fi
autoload -Uz compinit && compinit -C
```

在 macOS 上通过 Homebrew 安装的 bazelisk 还会将 `_bazel` 放入
`/opt/homebrew/share/zsh/site-functions/`，两者同时生效互不干扰。

补全配置后，输入 `bazel ` 按 Tab 即可获得命令补全。

## Linux 说明

在 Linux 上，脚本将二进制文件下载到 `~/.local/bin/`，并：

- 创建 `bazel -> bazelisk` 软链接，使 `bazel` 命令直接可用
- 在 `~/.bashrc` / `~/.zshrc` 中追加 `export PATH="$HOME/.local/bin:$PATH"`（幂等）

支持架构：`x86_64`（amd64）、`aarch64`（arm64）。

## 可重复执行

脚本的每个步骤都会检查当前状态后再决定是否操作：

- 工具已安装 → 打印 `[OK] 已安装，跳过`
- `~/.bazeliskrc` 版本一致 → 跳过；版本不同 → 原地更新
- 补全脚本已存在 → 跳过下载
- rcfile 中已有配置标记 → 跳过追加

## 编辑器集成

### Cursor / VSCode

安装 [Bazel 扩展](https://marketplace.visualstudio.com/items?itemName=BazelBuild.vscode-bazel) 后，在 `settings.json` 中配置 starpls 作为 LSP：

```json
{
  "bazel.lsp.command": "starpls"
}
```

## 常用命令

```bash
bazel version                   # 查看当前 Bazel 版本
bazel build //...               # 构建所有目标
bazel test //...                # 运行所有测试
bazel query "//..."             # 查询所有目标
bazel clean                     # 清理构建产物

buildifier BUILD.bazel          # 格式化单个文件
find . -name "*.bazel" -o -name "*.bzl" | xargs buildifier  # 批量格式化
```
