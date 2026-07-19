# subs-check-pro 手机远程测速

本机运行 subs-check-pro，手机通过 Cloudflare Tunnel 添加订阅、启动测速并查看结果。

## 仓库范围

仓库只保存部署脚本、脱敏配置模板和自定义核心补丁。以下内容被 `.gitignore`
明确排除，不会上传 GitHub：API Key、订阅地址、GitHub Token、Cloudflare Tunnel
凭据、真实配置、节点结果、日志和二进制文件。

首次从仓库恢复时：

```powershell
Copy-Item .\runtime\config\config.yaml.example .\runtime\config\config.yaml
Copy-Item .\runtime\cloudflared\config.yml.example .\runtime\cloudflared\config.yml
powershell -ExecutionPolicy Bypass -File .\scripts\build-custom-core.ps1
```

随后填写本机路径和凭据，把构建出的自定义核心复制为
`runtime\bin\subs-check-pro.exe`，并把 `cloudflared.exe` 和 Tunnel 凭据放入
模板约定的位置。真实配置只能保留在本机。

## 日常使用

1. 确认 Windows 电脑保持开机，Sparkle 不开启 TUN 模式。
2. 手机浏览器打开 `https://cesusub.sbxm.eu.org/admin`。
3. 在本机运行 `.\scripts\show-access.ps1` 查看 API Key。
4. 登录后添加订阅并启动检测。

测速由 Windows 电脑发出，不是手机本身发出。默认总测速速度上限为 20 MB/s，
单节点最多下载 10 MB，并发数为 4。

## 节点重命名

当前核心基于官方 v2.6.8，应用了
`patches/subs-check-pro-v2.6.8-custom-rename.patch`。开启 IP 归属地重命名后，
节点使用 `🇭🇰 香港 01 | 1x` 格式：地区内编号补齐为两位，原名存在大于 0 的倍率时
保留并统一为小写 `x`；`0x` 等无效倍率会被丢弃，`01x` 等前导零会被规范化为
`1x`，原名没有倍率时不虚构倍率。IP
归属查询失败时，会继续从原名中的国旗、开头国家代码、中文或英文国家名推断地区；
能识别就按相同格式重命名，无法可靠识别才保留原名。

为了防止官方自动更新覆盖本地补丁，核心自动更新已关闭。这个开关只禁止自动替换
可执行文件，程序仍会检查上游版本并在确有新 Release 时显示 `NEW`。升级核心前需要
把补丁迁移到目标版本、重新运行测试并构建二进制。

复现当前 v2.6.8 构建：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-custom-core.ps1
```

## 管理命令

- 安装当前用户自启动（无需管理员权限）：`powershell -ExecutionPolicy Bypass -File .\scripts\install-current-user.ps1`
- 手动启动：`powershell -ExecutionPolicy Bypass -File .\scripts\start.ps1`
- 启动隧道：`powershell -ExecutionPolicy Bypass -File .\scripts\start-tunnel.ps1`
- 验收检查：`powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1`
- 查看地址：`powershell -ExecutionPolicy Bypass -File .\scripts\show-access.ps1`

日志在 `runtime/logs/`，结果在 `runtime/output/`，凭据在
`runtime/config/config.yaml`。

WebUI 只监听本机回环地址，公网 API 必须提供 API Key；Cloudflare Tunnel
只负责加密转发，不对本机开放防火墙端口。
