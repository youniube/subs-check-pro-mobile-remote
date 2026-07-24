# subs-check-pro Windows 便携包

这个压缩包包含已经打好补丁的 `subs-check-pro.exe`、校验过的 `cloudflared.exe`、
配置模板和启动脚本。新电脑不需要安装 Git、Go 或 Node.js。

## 第一次使用

1. 将整个压缩包解压到不会再移动的目录，例如 `C:\subs-check-pro`。
2. 双击 `setup.cmd`。
3. 如果暂时只在电脑本机使用，Cloudflare 凭据路径直接留空。
4. 如果需要手机远程访问，输入 `credentials.json` 的位置以及 WebUI 域名。
5. 完成后双击 `verify.cmd` 检查服务。

初始化程序会自动生成随机 API Key 和 Sub-Store 私有路径，并存入
`runtime\config\config.yaml`。凭据、订阅、测速结果和日志都只保存在本机。

## Cloudflare Tunnel

可以使用已有 Tunnel，也可以创建新的 Tunnel。迁移已有 Tunnel 时，把
`credentials.json` 通过私密方式复制到新电脑；不要上传到 GitHub，也不要发送到公开聊天。

如果新旧电脑同时运行同一个 Tunnel，访问流量可能进入任意一台。正式迁移后应停止旧电脑上的
Tunnel，或者为新电脑创建独立 Tunnel 和域名。

## 常用入口

- `setup.cmd`：首次初始化或重新配置。
- `start.cmd`：手动启动后台程序。
- `verify.cmd`：检查核心、端口和 Tunnel 状态。
- `scripts\show-access.ps1`：显示访问地址和本机保存的 API Key。

程序默认仅监听 `127.0.0.1:8199` 和 `127.0.0.1:8299`，不会开放 Windows 防火墙端口。
手机访问由 Cloudflare Tunnel 加密转发。
