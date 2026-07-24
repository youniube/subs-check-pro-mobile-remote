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
- 核心基于官方 v2.6.8 应用了自定义节点重命名补丁：格式为 `🇭🇰 香港 01 | 1x`，地区内编号补齐两位，只保留原名中大于 0 的倍率（忽略 `0x` 等无效倍率），并按数值规范化前导零（`01x` → `1x`、`00.10x` → `0.1x`）。IP 归属查询失败时，继续从原名中的国旗、开头国家代码、明确分隔符后的国家代码（如 `::US`）、中文或英文国家名推断地区；能识别就重命名，仍无法可靠识别的节点从最终结果中删除。补丁位于 `patches/subs-check-pro-v2.6.8-custom-rename.patch`，复现脚本位于 `scripts/build-custom-core.ps1`，官方二进制备份位于 `runtime/bin/subs-check-pro-official-v2.6.8.exe`。自定义版本使用 SemVer 构建元数据 `v2.6.8+custom.history.ua2.loopback1.cleantags1`，避免把同基线补丁误判为低于官方正式版，并明确当前核心包含跨次分析、第二版 UA 兼容、历史节点回环复检与内部标签清理修复。
- 为避免官方升级覆盖自定义核心，核心自动更新已关闭；升级前需要把重命名补丁迁移到目标版本、运行相关 Go 测试并重新构建。
- 已修复官方 v2.6.8 分析报告在检测前过早清空逐订阅统计的问题：核心不再把活跃订阅写成 `成功数/0`，没有产出节点的来源会进入沉默订阅；WebUI 的“含沉默订阅”会显示数量，勾选后展开沉默列表并更新标题，同时影响复制范围。报告新增跨次订阅健康历史：只有完整检测才累计，连续 3 次没有节点通过才标记“建议核查/删除”，任意一次通过即清零，中止或因成功数上限提前结束不累计；只给人工建议，不自动删除。历史保存在 `runtime/output/stats/subs-health-history.yaml`，并区分 `0/0`（无可测节点）和 `0/N`（节点全部未通过）。核心补丁为 `patches/subs-check-pro-v2.6.8-analysis-report.patch` 与 `patches/subs-check-pro-v2.6.8-subscription-history.patch`，WebUI 补丁为对应的两个 `subs-check-pro-webui-b8db5f51c367-*.patch`。
- `scripts/build-custom-core.ps1` 使用 Git partial clone + sparse checkout，只下载 Windows amd64 所需的内嵌 Node 资产；原因是上游仓库包含约 300 MB 的多平台二进制，对当前 Windows 构建无用。用户影响是完整构建由数分钟缩短到约 40 秒，产物功能不变。
- GitHub Actions 在 Pull Request、`main`、手动触发及 `portable-v*` 标签上构建 Windows amd64 便携包；普通构建上传保留 30 天的 Artifact，标签构建额外发布 GitHub Release。构建任务仅有仓库只读权限，只有标签发布任务获得内容写权限。包内显式白名单只包含已打补丁核心、按固定 SHA256 校验的 cloudflared、模板和启动脚本，不包含真实配置、API Key、订阅、Tunnel 凭据、结果或日志。新电脑解压后运行 `setup.cmd`，无需安装 Git、Go 或 Node.js；初始化自动生成本机密钥与私有路径，可先本机运行，提供 `credentials.json` 后再启用 Tunnel。
- 普通订阅首轮没有产生结构有效节点时，核心会按 `clash.meta`、Clash Meta Android、`sing-box` 的顺序做 UA 兼容重拉，得到结构有效节点后立即停止；结构计数发生在 `node-type` 过滤前，所以正常订阅和仅被用户类型过滤的订阅仍只请求一次，GitHub Raw 跳过兼容重拉。补丁位于 `patches/subs-check-pro-v2.6.8-ua-fallback.patch`，回归测试覆盖“HTML 产生畸形假候选 → Clash YAML”恢复、首个兼容 UA 仍无有效节点时继续、正常首轮不重试、类型过滤不重拉和 GitHub 跳过。

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
- 分析报告补丁不会追溯重算 `runtime/output/stats/subs-analysis.yaml`，跨次历史也不会根据旧报告反推；部署后必须完成一次新的完整节点检测才会生成正确单次数据并从连续次数 1 开始累计。
- 上游 v2.6.8 首选 `mihomo/1.19.27` 且会把不可解析正文的 HTTP 200 当成成功，曾造成假 `0/0`。第一版 UA 修复错误地用解析器原始候选数触发回退；`clash.156987.xyz` 返回的 HTML 会因 Cloudflare 脚本被宽松解析器误报 1 个畸形候选，但结构有效数为 0，导致回退未执行。第二版改用类型过滤前、通过 `server`/`port`/`type` 校验的结构有效数触发；2026-07-20 直连验收中 `clash.meta` 响应解析出 52 个结构有效候选、订阅内去重后 31 个节点，同日完整检测最终为 `21/31`，连续沉默清零并恢复 active。不能把所有剩余 `0/0` 都归因于 UA，失效链接、空文件和确实无受支持节点的来源仍会保持 `0/0`。
- 2026-07-23 评估上游 v2.6.9：核心唯一业务修复是删除 `ClearCache` 中过早清空 `SubStats` 的语句，解决“订阅链接总数为 0”，但上游也因此不再在检测前后重置该映射，连续检测可能累积旧统计；本项目现有分析报告补丁已用“拉取缓存清理/完整状态清理”分离的方式更完整地解决。实测迁移到 v2.6.9 时，重命名、跨次历史、UA 回退、回环历史 4 个核心补丁可直接应用，分析报告核心补丁因同一行被上游删除而需手工适配；2 个 WebUI 补丁可直接应用到新版 WebUI。该版本主要新增手机触摸提示、小屏比例条修复、Sub-Store 2.36.18/前端 2.29.3 和依赖更新，属于有用但不紧急的升级。
- Git partial clone 的 `-c http.sslBackend=openssl` 只影响 clone 命令，不会自动传给后续 sparse checkout 的 promisor fetch；构建脚本现在会在临时仓库中持久设置 OpenSSL backend，避免 Windows PowerShell 无交互环境再次落回 schannel 并报凭据错误。
- 上游 `v2.6.8` 是注释标签；在干净 GitHub Actions runner 上使用 `--filter=blob:none --depth 1 --branch v2.6.8` 可能只取得标签对象而没有实际提交。构建脚本现固定拉取该标签剥离后的提交 `3c5468962e4364c3d5a61b53d90baf10385ea198`，并在应用补丁前核对 HEAD，以保证便携包构建可复现。
- 干净 Go 模块缓存中，`go list -m -f '{{.Dir}}'` 不会保证依赖已下载，可能返回空目录；构建脚本需先用 `go mod download -json` 下载 go.mod 选定的 WebUI 版本并读取其 `Dir`。该路径已用全新 `GOPATH`、`GOMODCACHE` 与 `GOCACHE` 完整构建验证。
- 上游 `proxy/isp_test.go` 的 3 个测试会直接访问 `ipapi.is`，第三方接口超时会让本地构建误报失败；构建门禁跳过这 3 个外部网络测试，仍运行其余 `proxy` 与全部 `check` 测试，包括内部标签清理回归测试。
- `keep-success-proxies: true` 会自动把已有的 `runtime/output/sub/all.yaml` 与 `history.yaml` 作为内部订阅重新检测，用户无需手工添加。上游 v2.6.8 只兼容纯端口或 `:端口`，却把本项目用于限制回环监听的 `listen-port: "127.0.0.1:8199"` 直接拼到 `http://127.0.0.1:` 后，生成非法的重复主机名 URL。现已通过 `patches/subs-check-pro-v2.6.8-loopback-history.patch` 统一提取 WebUI 与 Sub-Store 的数值端口，并固定用 IPv4 回环生成内部 URL；这既恢复上次成功与历史节点复检及其优先级标记，也保持 WebUI 只监听回环地址。
- 2026-07-24 确认：回环历史修复从 2026-07-22 10:42 启用后，`keep-success-proxies` 的内部复检分支开始真正执行；上游会给来自 `all.yaml` 和 `history.yaml` 的节点名分别追加 `|Succeed`、`|History`，这些内部优先级标签会泄漏到最终 `all.yaml`。该标签不是机场原名，也不是测速状态；如要保留历史复检能力，应在最终保存前剥离标签，而不是关闭 `keep-success-proxies`。

## 用户纠正与偏好

- 用户选择 subs-check-pro，目标是用手机远程添加订阅链接并发起测速。
- 用户当前只能通过手机远程操作本机 Codex；方案应避免依赖现场点击 UAC。
- 用户将最终访问域名从已有记录的 `cesu.sbxm.eu.org` 改为 `cesusub.sbxm.eu.org`。
- 用户选择使用较短的自定义 API Key；公网入口存在弱口令风险，后续应优先改用强密钥或增加 Cloudflare Access。
- 默认中文说明，技术决策需要解释原因和对用户的影响。
- 归属查询失败的节点不能一律标成“未知”；原名含国家国旗、开头或明确分隔符后的有效国家代码、或中英文国家名时，应先据此重命名；确实没有可靠国家信息时，从最终结果中删除，不再保留原名。
- 用户希望分析报告用于决定是否清理订阅：不能凭一次沉默下结论，应以多次完整检测的连续沉默趋势提供人工删除建议。
- 用户会用 Clash Meta UA 交叉验证 `0/0` 订阅；分析报告应尽量区分真实空订阅与 UA/响应格式造成的假 `0/0`。
- 用户不希望最终输出节点名称包含内部来源标签 `|Succeed` 或 `|History`；应保留历史复检和去重优先级，只清理名称展示。

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
