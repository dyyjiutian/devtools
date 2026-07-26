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

补全脚本存放于 `~/.config/bazel/`：

- **Bash**：优先用 `bazel completion bash` 生成（Bazel 9+），失败时回退到 GitHub 脚本
- **Zsh**：使用官方 `_bazel`，并追加 `_bazel "$@"` 入口，修复 zsh autoload 下「首次 Tab 无候选」的问题

### Bash

`~/.bashrc` 中由脚本写入托管块：

```bash
# >>> bazel-completion BEGIN >>>
[ -f ~/.config/bazel/bazel-complete.bash ] && . ~/.config/bazel/bazel-complete.bash
# <<< bazel-completion END <<<
```

### Zsh

`~/.zshrc` 中由脚本写入托管块（含 fpath、补全 cache、`compinit`）：

```zsh
# >>> bazel-completion BEGIN >>>
fpath=(~/.config/bazel $fpath)
mkdir -p ~/.cache/bazel-completion
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ~/.cache/bazel-completion
autoload -Uz compinit && compinit -C
# <<< bazel-completion END <<<
```

配置后新开终端，或 `source ~/.zshrc`，输入 `bazel ` 按 Tab 即可补全子命令与选项。

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

## Issues 

### 2026-07-26 — macOS zsh 下 `bazel` Tab 无命令/选项补全

**问题表象**

- 已通过 Homebrew 安装 bazelisk，`~/.zshrc` 也写入了 fpath / `compinit`，但输入 `bazel ` 按 Tab 仍无子命令或选项提示。
- 偶发表现为：第一次 Tab 完全无反应，多按几次后才偶尔出现候选。

**根因**

- 官方 zsh 补全文件 `_bazel`（`#compdef bazel`）在 zsh autoload 语义下，**整文件即为函数体**。
- 文件内部又定义了 `_bazel() { ... }`，却未在末尾调用 `_bazel "$@"`。
- 首次 Tab 只执行顶层加载（定义内部函数），不产生补全候选；第二次及以后才走到真正的补全逻辑。
- Homebrew 自带的 `_bazel` 与上游一致，同样缺少该入口调用。

**解法**

- `setup.sh` 将 `_bazel` 安装到 `~/.config/bazel/` 后，追加：

  ```zsh
  _bazel "$@"
  ```

- 同时用 BEGIN/END 托管块更新 `~/.zshrc`（fpath 前置、启用 completion cache、`compinit -C`），bash 侧优先用 `bazel completion bash` 生成脚本。
- 已有环境可重新执行：

  ```bash
  ./setup.sh --skip-bazelisk --skip-buildifier --skip-starpls --skip-bazelrc
  source ~/.zshrc
  ```
