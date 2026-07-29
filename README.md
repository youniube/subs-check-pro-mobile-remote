# subs-check-pro 手机远程测速

本机运行 subs-check-pro，手机通过 Cloudflare Tunnel 添加订阅、启动测速并查看结果。

## Windows 便携包

GitHub Actions 会在 Pull Request、`main` 更新、手动触发或推送 `portable-v*` 标签时，
自动构建 `subs-check-pro-portable-windows-amd64.zip`。普通构建可以在 Actions 页面下载
并保留 30 天；`portable-v*` 标签构建还会把压缩包和 SHA256 文件发布到 GitHub Releases。

便携包已经包含打好项目补丁的核心、校验过的 cloudflared、配置模板和首次初始化脚本，
新电脑不需要安装 Git、Go 或 Node.js。解压到固定目录后双击 `setup.cmd`，再按提示选择
本机模式或提供 Cloudflare Tunnel 凭据。详细步骤见 `README-PORTABLE.md`。

构建包采用文件白名单，不包含 `config.yaml`、订阅、API Key、Tunnel 凭据、测速结果或日志。

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

本地复现便携包：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-custom-core.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\build-portable-package.ps1
```

## 日常使用

1. 确认 Windows 电脑保持开机，Sparkle 不开启 TUN 模式。
2. 手机浏览器打开 `https://cesusub.sbxm.eu.org/admin`。
3. 在本机运行 `.\scripts\show-access.ps1` 查看 API Key。
4. 登录后添加订阅并启动检测。

测速由 Windows 电脑发出，不是手机本身发出。默认总测速速度上限为 20 MB/s，
单节点最多下载 10 MB，并发数为 4。

WebUI 保存 `cron-expression` 后，运行中的定时器会立即按新表达式重建，不需要重启核心。
调度判断以“定时器实际正在使用的配置”为准，而不是只比较已加载的配置文件值；这样即使
配置对象已经更新、旧定时器仍未替换，也会自动修复。例如 `0 5,19 * * *` 会在每天
05:00 和 19:00 执行。

## 节点重命名

当前核心基于官方 v2.6.8，应用了
`patches/subs-check-pro-v2.6.8-custom-rename.patch`。开启 IP 归属地重命名后，
节点使用 `🇭🇰 香港 01 | 1x` 格式：地区内编号补齐为两位，原名存在大于 0 的倍率时
保留并统一为小写 `x`；`0x` 等无效倍率会被丢弃，`01x` 等前导零会被规范化为
`1x`，原名没有倍率时不虚构倍率。IP
归属查询失败时，会继续从原名中的国旗、开头国家代码、明确分隔符后的国家代码
（例如 `::US`）、中文或英文国家名推断地区；能识别就按相同格式重命名，
无法可靠识别的节点会从最终结果中删除。

为了防止官方自动更新覆盖本地补丁，核心自动更新已关闭。这个开关只禁止自动替换
可执行文件，程序仍会检查上游版本并在确有新 Release 时显示 `NEW`。升级核心前需要
把补丁迁移到目标版本、重新运行测试并构建二进制。

复现当前 v2.6.8 构建：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-custom-core.ps1
```

## 保留成功与历史节点

开启 `keep-success-proxies` 后，核心会在下一次检测时自动回读本机生成的 `all.yaml` 和
`history.yaml`。官方 v2.6.8 只按纯端口拼接这两个内部地址，遇到本项目用于限制回环监听的
`127.0.0.1:8199` 会生成重复主机名的非法 URL。本项目通过
`patches/subs-check-pro-v2.6.8-loopback-history.patch` 先从监听地址中提取端口，再生成
`http://127.0.0.1:8199/...`，同时让内部订阅分类使用同一套端口规范化逻辑。这样既恢复
上次成功与历史节点的复检，也不会把 WebUI 暴露到局域网。

核心内部使用 URL 片段 `Succeed` 和 `History` 区分上次成功节点与历史节点，并据此决定
去重优先级；`patches/subs-check-pro-v2.6.8-clean-internal-tags.patch` 保留该内部优先级，
但不再把两个内部标签追加到最终节点名称。普通订阅链接中用户自定义的 URL 片段标签不受影响。

## 分析报告

官方 v2.6.8 会在生成分析报告前清空逐订阅统计，表现为活跃订阅显示 `成功数 / 0`、
成功率被放大 100 倍，并漏掉没有产出节点的沉默订阅。本项目通过
`patches/subs-check-pro-v2.6.8-analysis-report.patch` 保留报告所需统计，并把零产出的
订阅补入沉默列表；`patches/subs-check-pro-webui-b8db5f51c367-analysis-report.patch`
让“含沉默订阅”显示数量，勾选时展开沉默列表并同步更新排名标题，复制 URL/YAML
时也包含这些订阅。

补丁不会重算已经落盘的旧报告。升级或首次应用后需要再运行一次节点检测，新的总数、
成功率和沉默订阅列表才会写入 `runtime/output/stats/subs-analysis.yaml`。

“沉默订阅”表示该订阅在本次检测中没有任何节点通过，不等于应该立刻删除。报告会把
每次完整检测的结果累计到 `runtime/output/stats/subs-health-history.yaml`，并在沉默列表中
显示“连续沉默 N 次”和“上次可用时间”：

- 连续 1 次：视为临时异常。
- 连续 2 次：继续观察。
- 连续 3 次及以上：标记“建议核查/删除”，但不会自动删除订阅。
- 后续任意一次有节点通过，连续沉默次数立即清零。
- 手动中止或因 `success-limit` 提前结束的检测不计入历史，避免把没测完误判为沉默。

报告同时区分 `0/0`（没有解析出可测节点）和 `0/N`（解析出 N 个节点，但全部没有通过）。
历史从部署后的下一次完整检测开始累计，不会用旧报告反推过去的连续次数。

达到“连续 3 次沉默”的订阅会另存到
`runtime/output/stats/silent-subscriptions.yaml`。这个档案不会因订阅从当前配置中删除而消失；
以后在 WebUI 配置页重新加入同一链接（即使改了 `#备注`），保存时会直接提示并拒绝，
避免把已经筛过的低质量来源当成新订阅再次测速。单次或连续两次沉默不会进档案，防止把
临时网络异常误判成低质量来源；如果确实要重测，可先手动删除档案中的对应记录。

`sub-urls-remote` 会先按上游支持的 YAML、数组、Clash provider、Markdown 或纯文本格式
展开成具体订阅链接，再逐条查询沉默档案；命中的链接会在订阅下载和节点测速之前移除，
日志只显示跳过数量，不输出可能带令牌的地址。档案读取异常时采用放行策略，保证远程清单
仍可正常检测，并在日志明确提示本轮未执行跳过。

普通订阅首轮仍使用上游默认 UA。只有首轮正文没有产生结构有效节点（`server`、`port`、
`type` 均合法）时，
`patches/subs-check-pro-v2.6.8-ua-fallback.patch` 才会依次使用 `clash.meta`、
Clash Meta Android 和 `sing-box` UA 重新拉取，并在首次得到结构有效节点后停止。判断不再
采用解析器的原始候选数，避免 HTML 中的客户端唤起链接或 Cloudflare 脚本被误认成畸形候选后
阻断回退。这样可以恢复按 UA 返回不同订阅格式的来源，同时不会增加正常订阅或仅被
`node-type` 过滤的订阅请求次数；GitHub Raw 地址也不会进行这种重复拉取。

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
