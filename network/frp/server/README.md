# FRP 服务端

在具备公网访问能力的 Linux 服务器上部署 frps，为内网 Mac 提供 SSH/VNC 反向访问入口。

~~~bash
sudo bash network/frp/server/setup.sh --help
~~~

脚本可能安装 systemd 服务并配置防火墙端口。
