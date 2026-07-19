# 项目记忆

## 基本信息

- 项目名：subs-check-pro-mobile-remote
- 初始化日期：2026-07-17
- 技术栈：Windows 10、PowerShell 5.1、Go 二进制、Cloudflare Tunnel
- 项目用途：在常开 Windows 电脑上运行 subs-check-pro，通过手机远程添加订阅、发起测速并查看结果
- 当前工作区根目录：`F:\codex\subscheck`；2026-07-19 已从旧的 C 盘 Codex 日期目录迁移，运行配置、自启动和服务路径统一以此为准。

## 架构决策

- 使用 subs-check-pro 官方 Windows x86_64 二进制，不使用 Docker，以减少后台资源和启动依赖。
- WebUI 只监听 `127.0.0.1:8199`；手机通过 Cloudflare Tunnel 的 `https://cesusub.sbxm.eu.org` 访问，不做公网端口映射。
- subs-check-pro 默认使用 `system-proxy: direct`，避免隐式依赖本机 Sparkle/Mihomo。
- 使用当前用户启动项运行 subs-check-pro 和 cloudflared，避免管理员权限与现场 UAC；用户登录后自动启动。
- cloudflared 固定使用 IPv4 边缘地址与 HTTP/2；原因是本机到 Cloudflare 的 IPv6 `7844` 端口超时，而 IPv4 HTTP/2 链路可稳定建立。
- 已启用内置 Sub-Store；后端只监听 `127.0.0.1:8299`，并通过 Cloudflare Tunnel 的保留子域提供手机端前端和带私有路径的后端访问。
- 核心基于官方 v2.6.8 应用了自定义节点重命名补丁：格式为 `🇭🇰 香港 01 | 1x`，地区内编号补齐两位，只保留原名中大于 0 的倍率（忽略 `0x` 等无效倍率），并按数值规范化前导零（`01x` → `1x`、`00.10x` → `0.1x`）。IP 归属查询失败时，继续从原名中的国旗、开头国家代码、中文或英文国家名推断地区；能识别就重命名，无法可靠识别才保留原名。补丁位于 `patches/subs-check-pro-v2.6.8-custom-rename.patch`，复现脚本位于 `scripts/build-custom-core.ps1`，官方二进制备份位于 `runtime/bin/subs-check-pro-official-v2.6.8.exe`。自定义版本使用 SemVer 构建元数据 `v2.6.8+custom.rename`，避免把同基线补丁误判为低于官方正式版。
- 为避免官方升级覆盖自定义核心，核心自动更新已关闭；升级前需要把重命名补丁迁移到目标版本、运行相关 Go 测试并重新构建。

## 已知问题与踩坑

- 本机 Sparkle 1.26.5 使用 Mihomo 核心并监听 `127.0.0.1:7890`；Windows 系统代理指向该地址。
- 当前未发现 Sparkle/Mihomo TUN 网卡；测速期间不要开启 TUN，否则可能形成嵌套代理并扭曲结果。
- 电脑休眠、关机、用户未登录或 Cloudflare Tunnel 断开时，手机无法访问 WebUI。
- Tailscale Windows MSI 需要管理员令牌和现场 UAC 确认；当前用户只能用手机远程操作 Codex，无法处理安全桌面，因此安装已取消。
- 上游会在 info 日志记录启动配置中的 API Key；为保留成功提示，启动脚本使用 `LOG_LEVEL=info`，并每 500 毫秒对主日志中的密钥做等长原位掩码，避免破坏正在写入的文件；历史日志中的密钥也已清除。
- subs-check-pro v2.6.x 会把配置中的 `127.0.0.1:8299` 误判为非法 Sub-Store 端口；当前用纯端口 `8299` 配合 `SUB_STORE_BACKEND_API_HOST=127.0.0.1` 强制回环监听。
- 2026-07-19 上游发布 v2.6.8 后，旧的 v2.6.7 自定义核心显示 `NEW` 属于真实版本提醒，并非仅由重命名补丁造成；升级自定义基线后提醒消失。
- 手机旧配置页面执行“保存配置”会覆盖后台刚更新的端口或私有路径；后台改动后应先刷新页面再继续编辑。
- 2026-07-19 迁移时发现手机配置曾把 `sub-store-port` 漂移到 `9299`，而 Tunnel 仍转发 `8299`；现已统一恢复 `8299`，`scripts/verify.ps1` 会把端口不一致视为失败。
- `sub-urls-remote` 只接收“远程订阅链接清单”的地址，不接收普通机场订阅；普通订阅误放其中时，单行响应超过 64 KiB 会触发 `bufio.Scanner: token too long`，应放入 `sub-urls` 或 Sub-Store。
- 当前这条机场订阅返回约 803 个 VLESS URI，但使用 `%0A` 字面量分隔而不是真实换行；移入 `sub-urls` 后下载成功但主程序和 Sub-Store 都只能解析出至多一个无效节点。若机场端无法改格式，需要增加仅本机监听的自动规范化适配器。

## 用户纠正与偏好

- 用户选择 subs-check-pro，目标是用手机远程添加订阅链接并发起测速。
- 用户当前只能通过手机远程操作本机 Codex；方案应避免依赖现场点击 UAC。
- 用户将最终访问域名从已有记录的 `cesu.sbxm.eu.org` 改为 `cesusub.sbxm.eu.org`。
- 用户选择使用较短的自定义 API Key；公网入口存在弱口令风险，后续应优先改用强密钥或增加 Cloudflare Access。
- 默认中文说明，技术决策需要解释原因和对用户的影响。
- 归属查询失败的节点不能一律标成“未知”；原名含国家国旗、代码或中英文国家名时，应先据此重命名，确实没有可靠国家信息时才保留原名。

## 外部资源位置

- 项目 GitHub 仓库：https://github.com/youniube/subs-check-pro-mobile-remote
- 上游项目：https://github.com/sinspired/subs-check-pro
- Cloudflare Tunnel 地址：https://cesusub.sbxm.eu.org
- Sub-Store 前端地址：https://sub_store_for_subs_check.sbxm.eu.org
- Cloudflare Origin 证书位置：`C:\Users\tt\.cloudflared\cert.pem`。
- Tunnel 凭据位置：`runtime/cloudflared/credentials.json`。
- API Key 存放于 `runtime/config/config.yaml`，这里只记录位置，不记录值。
- Sub-Store 私有后端路径同样存放于 `runtime/config/config.yaml`，这里只记录位置，不记录值。
- 程序日志存放于 `runtime/logs/`。
- 对话中仍可取得的附件统一存放于 `private/conversation-assets/`，该目录被 Git 忽略，不上传 GitHub。

> 凭据只记录存放位置，不记录具体值；代码中可直接查到的信息不重复记录。
