# 离线安装包缓存目录

将需要的文件下载到此目录后，`os/macos/setup.sh` 和 `os/linux/setup_centos.sh`
在执行时会自动优先使用本地缓存，无需联网，适合网络受限环境或统一分发。

运行 `download.sh` 可一键下载所有文件到对应子目录。

---

## 目录结构

```
cache/
├── scripts/          # 安装脚本（shell 脚本、repo 配置）
└── binaries/         # 预编译二进制包
```

---

## scripts/ — 安装脚本

| 文件 | 来源 | 用于 |
|------|------|------|
| `homebrew-install.sh` | https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | macOS |
| `nvm-install.sh` | https://raw.githubusercontent.com/nvm-sh/nvm/HEAD/install.sh | macOS |
| `ohmyzsh-install.sh` | https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | macOS |
| `docker-ce.repo` | https://download.docker.com/linux/centos/docker-ce.repo | Linux |
| `nodesource-setup-20.x` | https://rpm.nodesource.com/setup_20.x | Linux |

## binaries/ — 二进制包

| 文件 | 来源 | 用于 |
|------|------|------|
| `yazi-x86_64-unknown-linux-gnu.zip` | https://github.com/sxyazi/yazi/releases/download/v0.3.3/yazi-x86_64-unknown-linux-gnu.zip | Linux x86_64 |
| `yazi-aarch64-unknown-linux-gnu.zip` | https://github.com/sxyazi/yazi/releases/download/v0.3.3/yazi-aarch64-unknown-linux-gnu.zip | Linux arm64 |
| `lazygit_0.44.1_Linux_x86_64.tar.gz` | https://github.com/jesseduffield/lazygit/releases/download/v0.44.1/lazygit_0.44.1_Linux_x86_64.tar.gz | Linux x86_64 |
| `lazygit_0.44.1_Linux_arm64.tar.gz` | https://github.com/jesseduffield/lazygit/releases/download/v0.44.1/lazygit_0.44.1_Linux_arm64.tar.gz | Linux arm64 |
| `fzf-0.72.0-linux_amd64.tar.gz` | https://github.com/junegunn/fzf/releases/download/v0.46.1/fzf-0.72.0-linux_amd64.tar.gz | Linux x86_64 |
| `fzf-0.72.0-linux_arm64.tar.gz` | https://github.com/junegunn/fzf/releases/download/v0.46.1/fzf-0.72.0-linux_arm64.tar.gz | Linux arm64 |
| `zoxide-0.9.4-x86_64-unknown-linux-musl.tar.gz` | https://github.com/ajeetdsouza/zoxide/releases/download/v0.9.4/zoxide-0.9.4-x86_64-unknown-linux-musl.tar.gz | Linux x86_64 |
| `zoxide-0.9.4-aarch64-unknown-linux-musl.tar.gz` | https://github.com/ajeetdsouza/zoxide/releases/download/v0.9.4/zoxide-0.9.4-aarch64-unknown-linux-musl.tar.gz | Linux arm64 |

> **tmux**：通过系统包管理器（dnf/yum）安装，无法离线缓存。离线环境需提前配置内网 yum 源。

---

## 使用方式

**方式一：运行下载脚本（需要联网）**

```bash
bash cache/download.sh          # 下载全部
bash cache/download.sh macos    # 仅下载 macOS 所需
bash cache/download.sh linux    # 仅下载 Linux 所需
```

**方式二：手动下载后提交**

将对应文件下载到 `scripts/` 或 `binaries/` 目录后 `git add` 提交即可。

**自动生效**：setup 脚本会自动检测缓存目录，有缓存则直接使用，无缓存则联网下载。无需传任何参数。
