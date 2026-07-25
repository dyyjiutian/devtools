# Mac 盒盖远程桌面（VNC + 虚拟屏）

MacBook 合盖当服务器时，SSH（远程登录，端口 22）通常正常，但**屏幕共享 / VNC（端口 5900）会在过一段时间后失效**。

根因：盒盖 + 无外接显示器 → 内置屏休眠 → 图形子系统关闭 → `screensharingd` 进程仍在但无法接受连接。

**解决方案**：用虚拟显示器软件，让 macOS 认为始终有屏幕，从而稳定 VNC。

---

## 快速开始

### 前提

- macOS 12+（Monterey 及以上）
- 已安装 [Homebrew](https://brew.sh)
- **首次配置建议开盖**（完成屏幕共享授权、登录项等）
- 接电源

### 一键配置

```bash
cd os/macos/remote-desktop
chmod +x setup.sh

# 安装 + 配置虚拟屏 + 防睡 + 重启 VNC
./setup.sh configure
```

### 重启后 VNC 挂了

```bash
./setup.sh repair
```

### 查看状态

```bash
./setup.sh status
```

---

## 脚本命令

| 命令 | 说明 |
|------|------|
| `./setup.sh install` | 仅安装虚拟屏软件（Homebrew cask） |
| `./setup.sh configure` | 完整配置（推荐） |
| `./setup.sh repair` | 重连虚拟屏 + 重启 screensharingd |
| `./setup.sh status` | 诊断盒盖 / 虚拟屏 / VNC |
| `./setup.sh nosleep` | 仅配置 pmset + caffeinate 防睡 |

### 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `VIRTUAL_BACKEND` | `betterdisplay` | `betterdisplay` 或 `deskpad`（免费） |
| `VIRTUAL_SCREEN_NAME` | `HeadlessServer` | BetterDisplay 虚拟屏名称 |
| `VIRTUAL_RESOLUTION` | `1920x1080` | 分辨率 `WIDTHxHEIGHT` |
| `VIRTUAL_HIDPI` | `off` | `off` 时远程桌面 UI 更大 |
| `SKIP_NOSLEEP` | — | 设为 `1` 跳过防睡 |

```bash
# 免费开源方案（Monterey 12+）
VIRTUAL_BACKEND=deskpad ./setup.sh configure

# 2K 分辨率
VIRTUAL_RESOLUTION=2560x1440 VIRTUAL_HIDPI=off ./setup.sh configure
```

---

## 必须手动完成的步骤

脚本**无法可靠自动完成**以下操作，需开盖或用已有 VNC 会话操作一次：

### 1. 开启屏幕共享

| 系统 | 路径 |
|------|------|
| Monterey | 系统偏好设置 → **共享** → 勾选 **屏幕共享** |
| Ventura+ | 系统设置 → 通用 → **共享** → **屏幕共享** |

「远程登录」= SSH（22），「屏幕共享」= VNC（5900），两项独立。

### 2. 首次 VNC 授权

若系统弹出「是否允许屏幕共享」，必须在 Mac 上点 **允许**（合盖后无法再点）。

### 3. 登录项（重启后自动恢复）

系统偏好设置 → **用户与群组** → **登录项** → 添加：

- BetterDisplay，或
- DeskPad

---

## 虚拟屏软件对比

| | BetterDisplay | DeskPad |
|---|---------------|---------|
| 价格 | 基础虚拟屏**免费**；自定义分辨率等需 Pro（约 ¥168） | **完全免费**（MIT） |
| macOS 12 Monterey | ✅ | ✅ |
| macOS 14+ SimpleDisplay | — | 也可用 [SimpleDisplay](https://simpledisplay.app/) |
| 分辨率调整 | CLI / 菜单栏 | 系统偏好设置 → 显示器 |
| 安装 | `brew install --cask betterdisplay` | `brew install --cask deskpad` |

### BetterDisplay 免费 vs Pro

| 功能 | 免费 | Pro |
|------|------|-----|
| 创建虚拟屏 | ✅ | ✅ |
| 连接虚拟屏 | ✅ | ✅ |
| 自定义虚拟屏（高级分辨率列表等） | ❌ | ✅ |

试用结束后可在 BetterDisplay → 设置 → Advanced 关闭 Pro 试用，验证免费版是否满足需求。

---

## 连接方式

### 局域网

```bash
open vnc://192.168.x.x
# 或
open vnc://macbook-pro.local
```

### SSH 隧道（推荐，更安全）

在客户端执行：

```bash
ssh -L 5901:localhost:5900 user@192.168.x.x
open vnc://localhost:5901
```

### 仅命令行（不需要 VNC）

SSH 足够当服务器使用，可忽略虚拟屏：

```bash
ssh user@192.168.x.x
# 配合 ../../os/macos/power/nosleep.sh start 防止睡眠
```

---

## 分辨率与「屏幕太小」

虚拟屏默认可能偏小，尤其是 **HiDPI 开启** 时（逻辑分辨率减半）。

| 设置 | 远程桌面观感 |
|------|-------------|
| 1280×720 + HiDPI | 非常小 |
| 1920×1080 + HiDPI 关 | 适中（推荐） |
| 2560×1440 + HiDPI 关 | 更大工作区 |

**BetterDisplay 调整：**

```bash
/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay \
  set -name=HeadlessServer -resolution=1920x1080 -hiDPI=off
sudo pkill screensharingd
```

**DeskPad**：系统偏好设置 → 显示器 → DeskPad Display → 选 1920×1080（非 HiDPI）。

---

## 故障排查

### VNC 5900 超时，但 SSH 正常

```bash
./setup.sh status
./setup.sh repair
```

常见原因：

1. 盒盖后内置屏休眠，虚拟屏未连接 → `repair`
2. 屏幕共享未开启 → 系统设置手动打开
3. `screensharingd` 僵死 → `sudo pkill screensharingd`

### `launchctl kickstart -k` 报 Operation not permitted

macOS 禁止 `-k` 强杀系统服务，改用：

```bash
sudo pkill screensharingd
# 或（无 -k）
sudo launchctl kickstart system/com.apple.screensharing
```

### 刚合盖能连，过一阵不行

| 现象 | 原因 |
|------|------|
| SSH 一直通 | 系统未睡，正常 |
| VNC 过一会挂 | 显示/GPU 休眠，虚拟屏断开 |

确保：

- `./setup.sh nosleep` 或 `caffeinate -dims`（含 **-d** 防 display 睡眠）
- 虚拟屏软件在**登录项**中自启
- 重启后执行 `./setup.sh repair`

### 验证命令

```bash
# 盒盖状态
ioreg -r -k AppleClamshellState | grep AppleClamshellState

# 显示是否休眠
system_profiler SPDisplaysDataType | grep Asleep

# 端口
nc -zv 127.0.0.1 22
nc -zv 127.0.0.1 5900
```

---

## 架构说明

```
┌─────────────┐     合盖      ┌──────────────────────────────┐
│  MacBook    │ ──────────►  │ 内置屏 Display Asleep         │
│  + 电源     │              │ GPU / WindowServer 可能收掉   │
└─────────────┘              └──────────────────────────────┘
                                        │
                    虚拟屏软件           ▼
              ┌─────────────────────────────────┐
              │ BetterDisplay / DeskPad         │
              │ → 系统认为有外接显示器           │
              │ → screensharingd 可正常服务 VNC  │
              └─────────────────────────────────┘
                                        │
                                        ▼
                              VNC :5900 / SSH :22
```

---

## 相关脚本

| 路径 | 说明 |
|------|------|
| `os/macos/remote-desktop/setup.sh` | 本目录：虚拟屏 + VNC 配置 |
| `os/macos/power/nosleep.sh` | 防睡（合盖保持 SSH / 网络） |
| `os/macos/setup.sh` | macOS 通用初始化 |

---

## 硬件替代（可选）

若不想依赖软件或 Pro  license，可用 **HDMI 假显示器**（约 ¥20，非真显示器）：

- MacBook Pro 2015（Thunderbolt 2）：Mini DisplayPort 转 HDMI + dummy plug
- 效果通常比纯软件更稳定，无需 BetterDisplay Pro

---

## 参考

- [BetterDisplay 免费/Pro 功能对比](https://github.com/waydabber/BetterDisplay/wiki/List-of-free-and-Pro-features)
- [DeskPad](https://github.com/Stengo/DeskPad)
- [SimpleDisplay](https://simpledisplay.app/)（需 macOS 14+）
