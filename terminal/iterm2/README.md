# iTerm2 配置指南

## 目录

- [快捷键配置](#快捷键配置)
- [光标按单词快速移动](#光标按单词快速移动)
- [默认窗口设置](#默认窗口设置)
- [控制台滚动行数](#控制台滚动行数)
- [免密 SSH 登录](#免密-ssh-登录)
- [保持会话 / 防止断连](#保持会话--防止断连)

---

## 快捷键配置

通过 `Settings → Keys → Hotkey` 设置全局唤起快捷键（推荐 `⌥Space`）。

（截图已移除，含个人环境信息）

---

## 光标按单词快速移动

在 `Settings → Profiles → Keys → Key Bindings` 中添加以下绑定，实现 `⌥←` / `⌥→` 按单词跳跃：

参考配置：[CSDN 教程](https://blog.csdn.net/skyyws/article/details/78480132)

（截图已移除，含个人环境信息）

---

## 默认窗口设置

在 `Settings → Profiles → Window` 中可配置半透明背景（Blending 50%）和窗口大小（Full-Width / Top of Screen）。

（截图已移除，含个人环境信息）

---

## 控制台滚动行数

在 `Settings → Profiles → Terminal` 中勾选 **Unlimited Scrollback**，去除默认 1000 行限制。

（截图已移除，含个人环境信息）

---

## 免密 SSH 登录

### 方式一：ssh-copy-id（推荐，基于密钥）

最安全的方式，将本地公钥拷贝到远程服务器，之后 SSH 无需密码。

```bash
# 1. 本地生成密钥对（如果还没有）
ssh-keygen -t ed25519 -C "your_email@example.com"

# 2. 将公钥推送到远程服务器
ssh-copy-id user@remote-host

# 3. 验证
ssh user@remote-host   # 此后无需输入密码
```

> 密钥默认存放在 `~/.ssh/id_ed25519`（私钥）和 `~/.ssh/id_ed25519.pub`（公钥）。

---

### 方式二：login.exp（基于 expect 脚本）

适用于无法使用密钥、只能密码登录的场景（如某些跳板机）。

脚本位置：`scripts/login.exp`

**用法：**

```bash
# 用法: ./login.exp <user> <host> <password>
./scripts/login.exp root 192.168.1.100 mypassword
```

**配合 iTerm2 Profile 使用：**

在 `Settings → Profiles → General → Command` 中选择 **Command**，填入：

```
/usr/bin/expect /path/to/scripts/login.exp root 192.168.1.100 mypassword
```

这样打开该 Profile 时，自动完成 SSH 登录。

> **注意**：密码明文写在命令行中存在安全风险，仅建议用于内网或测试环境。

---

### 方式三：sshpass（命令行密码注入）

`sshpass` 可在命令行直接传入密码，适合脚本批量操作。

```bash
# 安装
brew install sshpass

# 用法
sshpass -p 'mypassword' ssh user@remote-host

# 结合 scp 使用
sshpass -p 'mypassword' scp file.txt user@remote-host:/path/
```

**配合 iTerm2 Profile 使用：**

同样在 Profile 的 Command 中填入：

```
sshpass -p 'mypassword' ssh user@remote-host
```

> **注意**：同上，密码明文，谨慎用于生产环境。

---

### 三种方式对比

| 方式 | 安全性 | 适用场景 |
|------|--------|---------|
| ssh-copy-id（密钥） | ⭐⭐⭐ 高 | 推荐，有权限写入 `authorized_keys` |
| login.exp（expect） | ⭐⭐ 中 | 跳板机、交互式登录场景 |
| sshpass | ⭐ 低 | 快速测试、内网批量脚本 |

---

## 保持会话 / 防止断连

长时间无操作导致 SSH 会话断连，可通过以下方式解决：

### 方法一：iTerm2 客户端心跳（推荐）

在 `Settings → Profiles → Session` 中找到 **When idle, send ASCII code**：

- 勾选该选项
- 设置发送间隔为 **60 秒**（或更短）
- ASCII code 填写 `0`（空字符，不影响终端显示）

---

### 方法二：SSH 客户端配置（全局生效）

编辑 `~/.ssh/config`，添加：

```
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

- `ServerAliveInterval 60`：每 60 秒发送一次心跳包
- `ServerAliveCountMax 3`：连续 3 次无响应才断开

---

### 方法三：服务端配置（需 root 权限）

在远程服务器编辑 `/etc/ssh/sshd_config`：

```
ClientAliveInterval 60
ClientAliveCountMax 3
```

修改后重启 sshd：

```bash
sudo systemctl restart sshd
```
