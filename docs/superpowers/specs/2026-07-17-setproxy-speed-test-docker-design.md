# Setproxy 独立测速与 Docker 守护进程代理设计

## 目标

将 `network/vpn/client/bin/speed_test` 作为独立命令安装到 `~/.local/bin`，并使
`setproxy` 在启用或关闭终端代理时同步管理已识别 Docker 守护进程的 HTTP 代理。
所有 Docker/Colima 重启均由用户手动执行。

## 安装器

`install-setproxy.sh` 将 `bin/setproxy` 和 `bin/speed_test` 分别以 `0755` 权限
安装至 `~/.local/bin/setproxy` 与 `~/.local/bin/speed_test`。`--dry-run` 显示两个
文件的变更，`--uninstall` 同时删除二者，并保留既有 shell 钩子与 setproxy 配置
清理行为。

成功信息将提示：

```text
setproxy on | off | status | test [--size MB]
speed_test [--size MB] [--vpn-port PORT]
```

## Setproxy 测速参数

`setproxy test` 增加 `--size MB` 和 `--size=MB`。默认仍为 10 MB，合法范围为
1–1000 的整数 MB。该选项只改变 `setproxy test` 中 Cloudflare（经 SOCKS）与
清华 TUNA（强制直连）两项下载测速的大小；站点连通性检查和其他子命令不受影响。

参数解析失败时打印用法并以非零状态退出。

## Docker 守护进程代理

### 通用规则

Docker 使用 HTTP 代理 `http://<HTTP_HOST>:<HTTP_PORT>`，写入 `proxies` 中的
`http-proxy`、`https-proxy` 与 `no-proxy` 字段。配置写入前记录原始 `proxies`
值，关闭时仅恢复这一字段，不改变同一 JSON 文件的其他键。

状态保存在 `~/.config/vpn/setproxy-docker-state.json`，按 Docker 目标分别记录原始
`proxies`（或其原本不存在的标记）及 setproxy 写入后的值。恢复前会先确认当前值仍
等于 setproxy 的写入值；若被其他工具修改，则保留当前值并警告，避免以过期备份覆盖
用户的新配置。

操作只在确认目标 Docker 引擎存在时执行。无法解析已有 JSON、权限不足或找不到
可用引擎时，不破坏原配置，并给出可操作的告警。写入或恢复后不会执行任何重启；
输出平台对应的手动重启命令。

### Linux Docker Engine

检测到本机 Docker Engine 后，管理 `/etc/docker/daemon.json`。因该路径通常需要
管理员权限，脚本仅在实际需要写入时请求 `sudo`。成功后提示：

```text
sudo systemctl restart docker
```

### macOS Colima

仅在识别到正在使用 Docker runtime 的 Colima 时执行。脚本通过 `colima ssh` 修改
该 Colima VM 内的 `/etc/docker/daemon.json`；代理地址使用 VM 可访问的宿主机网关，
不使用 VM 自身的 `127.0.0.1`。成功后提示：

```text
colima restart
```

Docker Desktop 不写入 `daemon.json`，因为其忽略该文件的守护进程代理配置；状态和
启用流程会提示用户到 Docker Desktop 设置中手动配置。

## 状态与错误处理

`setproxy status` 输出 Docker/Colima 的检测结果、由 setproxy 管理的代理状态及
仍需用户执行的重启命令。没有 Docker、没有 Colima 或不支持的 Docker Desktop
不是错误，不应使 `setproxy on` 或 `setproxy off` 失败。

## 测试

扩展 `network/vpn/client/setproxy_test.sh`，覆盖：

- `setproxy test --size` 的参数验证和传递给两项测速的字节范围；
- 安装器同时安装可执行的 `speed_test`，并在卸载时删除；
- Linux Docker 的 JSON 合并、原始 `proxies` 恢复以及无自动重启；
- macOS Colima 的识别、宿主机网关代理地址和仅提示重启；
- Docker Desktop 的跳过提示。

测试使用伪造命令与临时配置目录，不接触真实 Docker、Colima 或系统配置。
