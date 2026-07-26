# 操作系统初始化

按操作系统提供基础软件、平台配置和系统服务初始化入口。

- `os/macos`：macOS 软件与系统配置。
- `os/linux`：Ubuntu、Debian、CentOS 和 RHEL 系列初始化。
- `os/lib`：跨平台共享逻辑（如 `packages.list` 解析）。

各平台 setup 分两段：

1. **OS 基础配置**：系统信息、权限/包管理器就绪、Homebrew（macOS）或基础构建依赖。
2. **常见软件**：按对应目录下的 `packages*.list` 声明（`name version source`）下载并安装。

需要系统权限的脚本必须先阅读帮助，并优先使用信息或预览模式：

```bash
bash os/macos/setup.sh --help
bash os/macos/setup.sh --dry-run
bash os/linux/setup_ubuntu.sh --dry-run
bash os/linux/setup_centos.sh --dry-run
```
