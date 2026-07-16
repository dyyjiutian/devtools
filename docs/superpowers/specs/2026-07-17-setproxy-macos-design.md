# setproxy macOS 与 Git SSH 代理设计

## 目标

把 `tools/vpn/client/bin/setproxy` 作为 macOS 和 Linux 通用的终端代理开关，并适配两类本地 Xray 客户端：

- macOS V2RayXS：HTTP `8001`，SOCKS5 `1081`
- 仓库命令行 Xray：HTTP `10809`，SOCKS5 `10808`

`setproxy on` 除 HTTP/SOCKS 环境变量外，还导出 `GIT_SSH_COMMAND`，使 `git@host:path` 和 `ssh://` Git 远端通过本地 SOCKS5。工具不修改 `~/.ssh/config`。

## 端口选择与持久化

优先级如下：

1. 命令行 `--http-host`、`--http-port`、`--socks-host`、`--socks-port`
2. 环境变量 `VPN_HTTP_HOST`、`VPN_HTTP_PORT`、`VPN_SOCKS_HOST`、`VPN_SOCKS_PORT`
3. `~/.config/vpn/setproxy.conf` 中上次保存的值
4. 本机监听端口自动检测
5. 平台默认值：macOS 使用 `8001/1081`，Linux 使用 `10809/10808`

自动检测时优先选择完整监听的一组端口；macOS 优先 V2RayXS，Linux 优先命令行 Xray。`setproxy on` 把最终选择写入 `setproxy.conf`，后续 `status`、`test` 和重新开启复用。

## 开启与关闭

`setproxy on` 写入 `~/.config/vpn/proxy.env`：

```sh
export http_proxy="http://127.0.0.1:8001"
export https_proxy="http://127.0.0.1:8001"
export HTTP_PROXY="http://127.0.0.1:8001"
export HTTPS_PROXY="http://127.0.0.1:8001"
export all_proxy="socks5h://127.0.0.1:1081"
export ALL_PROXY="socks5h://127.0.0.1:1081"
export no_proxy="127.0.0.1,localhost,::1"
export NO_PROXY="127.0.0.1,localhost,::1"
export GIT_SSH_COMMAND='ssh -o ProxyCommand="nc -x 127.0.0.1:1081 -X 5 %h %p"'
```

`setproxy off` 删除 `proxy.env`。`setproxy off --emit` 输出对应的 `unset` 命令，使以下方式立即更新当前 shell：

```sh
eval "$(setproxy on --emit)"
eval "$(setproxy off --emit)"
```

`--emit` 模式的标准输出只能包含可供 shell 执行的 `export` 或 `unset`；提示信息写到标准错误。

## Git SSH 行为

`GIT_SSH_COMMAND` 只影响 Git 启动的 SSH，不影响用户直接运行的 `ssh`，也不写入 SSH 配置。所有 Git SSH 目标先进入本地 SOCKS5；目标域名及端口保持 Git 远端原值，Xray 再根据自身路由规则决定出口。

如果系统缺少支持 `-x/-X` 的 `nc`，开启时打印警告。用户可通过 `--no-git-ssh` 或 `VPN_GIT_SSH_PROXY=false` 禁用该变量。

## 测试与状态

`setproxy test` 中：

- 海外测试显式指定 HTTP 或 SOCKS 代理。
- 国内直连测试显式使用 `curl --proxy '' --noproxy '*'`，不继承当前代理环境。
- macOS 状态提示同时支持 V2RayXS 进程/端口和仓库 LaunchAgent，不假设只有 `com.vpn.xray-client`。

## 安装与卸载

安装器继续安装到 `~/.local/bin/setproxy`，并用受管标记添加 PATH。

卸载时清理：

- `~/.local/bin/setproxy`
- shell rc 中 setproxy PATH 受管块
- shell rc 中 `proxy.env` 自动加载受管块
- `~/.config/vpn/proxy.env`
- `~/.config/vpn/setproxy.conf`

安装时若发现 shell 中已有 `setproxy()` 或 `unsetproxy()` 函数定义，打印冲突提示，不自动删除用户代码。本次本机迁移会单独注释 `~/.zshrc` 中旧函数区块。

