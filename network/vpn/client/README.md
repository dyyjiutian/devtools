# VPN 客户端

安装和管理本机 Xray 客户端、代理开关、TUN 路由与测速工具。

~~~bash
bash network/vpn/client/linux_setup.sh --help
bash network/vpn/client/macos_setup.sh --help
~~~

Linux 和 macOS 使用不同脚本；涉及路由、系统代理和服务状态时应先使用 dry-run 或 status。

`geoip.dat` / `geosite.dat` 优先使用仓库 `cache/binaries/` 中的缓存（可用
`bash cache/download.sh linux` 预取），避免国内网络访问 jsdelivr 超时。
