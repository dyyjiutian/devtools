# 语言运行时与语言笔记

本目录按语言拆分两类内容：

1. **运行时 / 工具链安装**（Python、Go、Java、Rust 等）：各语言独立的 `setup.sh`。
2. **语言编写约定与经验**（当前主要是 Bash）：语法陷阱、兼容性、结构模式、测试习惯。

| 路径 | 类型 | 说明 |
|---|---|---|
| `python/`、`go/`、`java/`、`rust/` | 运行时安装 | 保持安装器独立，不把语言特有逻辑塞进根入口 |
| [`bash/`](./bash/) | 语言笔记 | Bash 脚本方言与本仓基线；**不是**交互 Shell 配置（见 `shell/`） |

Bash 交互环境（bashrc、插件、prompt）在仓库根下的 `shell/`，不要与 `languages/bash/` 混淆。

运行时安装器的 L1/L2/L3 测试见各语言目录的 `tests/` 与 [`tests/README.md`](../tests/README.md)。本地改 `setup.sh` 后默认跑：

```bash
bazel test --config=l1 //languages/go/... //languages/python/... //languages/java/... //languages/rust/...
```
