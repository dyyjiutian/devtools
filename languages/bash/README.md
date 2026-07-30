# Bash（脚本语言）

本目录沉淀 **Bash 作为脚本语言** 的约定与经验：语法陷阱、兼容性、结构模式、测试方式。

它不是 Bash/Zsh 的交互环境配置；启动文件、插件、prompt 仍在 `shell/`。

| 路径 | 内容 |
|---|---|
| [`pitfalls.md`](./pitfalls.md) | 常见陷阱（对齐 [BashPitfalls](https://mywiki.wooledge.org/BashPitfalls) 思路） |
| [`compatibility.md`](./compatibility.md) | 本仓兼容基线（macOS Bash 3.2+、`set -u` 等） |
| [`patterns.md`](./patterns.md) | 脚本结构与幂等模式 |
| [`testing.md`](./testing.md) | 语法检查、回归与测试习惯 |

## 与其它目录的分工

| 目录 | 职责 |
|---|---|
| `languages/bash/` | 写 Bash 脚本时的语言知识与硬约束细节 |
| `shell/` | 人如何用终端（bashrc、oh-my-zsh、starship） |
| 根 `AGENTS.md` / `CLAUDE.md` | 仓库级短约束；细节链到本目录 |

本仓可执行脚本默认方言是 **Bash**，兼容基线是 **macOS 自带 Bash 3.2+**（见 `compatibility.md`）。仓库级硬约束摘要见根 `AGENTS.md`「Shell 脚本约定」。
