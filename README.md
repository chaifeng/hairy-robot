# 注意
完成最初始的一键安装脚本，有很大的可能性无法在你的环境里安装。

不是所有的 WiFi 网卡都可以用的。

# 使用方法
## 安装 PPTP 服务端
install-pptp-server.sh

在 Ubuntu 12.04 上测试通过

## 在树莓派上安装 PPTP 客户端
install-pptp-client-on-pi.sh

在 2014-01-07-wheezy-raspbian.zip 上测试通过

安装完成后会自动启动，用 ssh 登录后可以看到 WiFi 密码

默认不启用中国 IP 路由，可以使用 add-china-routes 命令来启用。
