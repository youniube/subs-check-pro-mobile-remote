# 配置热重载五批修复交接文档

> 写给下一次 Codex 会话或新接手者。
> 状态快照：2026-07-29 08:25（Asia/Shanghai）
> 工作区：`F:\codex\subscheck`

## 一页结论

配置热重载五批修复已经全部编码、生成补丁、通过干净基线应用、完成构建并部署到当前运行环境。

最初的问题是：WebUI 已把 Cron 保存为 `0 5,19 * * *`，但运行中的调度器仍使用旧表达式 `30 5 * * *`，所以错误地显示次日 `05:30`，跳过了当天 `19:00`。根因不是 Cron 语法，而是旧代码只比较重新加载后的全局配置，没有比较调度器真正已应用的配置。

当前运行态已经直接确认：

| 项目 | 当前值 |
| --- | --- |
| 活跃版本 | `v2.6.8+custom.history.ua2.loopback1.cleantags1.silentarchive1.remotefilter1.cronreload1.configstate1.substore1.addrout1.configsem1.subrace1` |
| 活跃核心 SHA256 | `E35EF630C97F299910CDBE4EB349279DB6371B29DA7E3E9D30927D91D1C6B8FD` |
| 检测状态 | `checking=false` |
| 配置状态 | `applied` |
| 配置版本 | 已应用/期望 `1/1` |
| 待重启字段 | 0 |
| 下次启动字段 | 0 |
| 实际调度器模式 | `cron` |
| 实际 Cron | `0 5,19 * * *` |
| 实际下次执行 | `2026-07-29T19:00:00+08:00` |
| Sub-Store | `running`，版本 `1/1` |
| WebUI | `127.0.0.1:8199` |
| Sub-Store | `127.0.0.1:8299` |

五批修复没有剩余代码阻塞，Cron 现场验收和 Windows Race Detector
也已完成。Git 交付状态以仓库中的提交、PR、`portable-v*` 标签和对应 GitHub Actions
结果为准，不再把会迅速过期的“尚未提交”状态固化在交接快照中。仍需单独处理的是：

1. 没有为了验收主动做“检测中保存真实配置”实验，避免产生未授权外部副作用；
2. 项目原有的“超大远程清单可能压垮核心/Tunnel”风险不属于本次五批修复。

## 新会话开始后的前 10 分钟

1. 完整阅读：

   - `AGENTS.md`
   - `MEMORY.md`
   - `HANDOFF.md`
   - `CONFIG-HOT-RELOAD-FIX-PLAN.md`

2. 查看并保护当前未提交工作：

   ```powershell
   git status --short --branch
   git diff --check
   ```

3. 运行安全默认验收：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1
   ```

   默认验收不会把真实 API Key 发到公网 Tunnel。只有显式增加
   `-IncludePublicAuthenticatedCheck` 才会发送公网鉴权请求。

4. 不要输出以下内容：

   - `runtime/config/config.yaml` 的完整内容；
   - API Key；
   - 订阅 URL；
   - Tunnel 凭据；
   - Sub-Store 私有后端路径。

5. 不要停止或修改 Sparkle/Mihomo，不要开启 TUN。subs-check-pro 使用独立端口并默认直连。

6. 不要使用 `git reset --hard`、`git checkout --` 或其他覆盖当前未提交改动的命令。

## 修复前的问题与第一性原理判断

### 表面问题

WebUI 显示配置保存成功，但运行行为可能仍是旧值。Cron 已经证实存在这个问题，因此用户有理由怀疑其他配置也可能“界面是新值、运行还是旧值”。

### 全量审计结果

- WebUI 有 89 个唯一表单控件。
- 展开嵌套结构后共有 96 个完整 YAML 字段路径。
- 修复前有 10 个明确的热重载或保存语义缺陷。
- 更普遍的根因是共享 `GlobalConfig` 被原地覆盖，检测协程没有固定配置快照。

已确认的典型缺陷包括：

- Cron 文件值已更新，但运行定时器仍是旧值；
- Sub-Store 配置回调同步进入长期运行函数，保存请求可能阻塞；
- Sub-Store 的端口、路径、两个 Cron、Push 和代理环境可能继续使用旧值；
- `listen-port` 被错误当成纯端口拼接，生成重复主机名 URL；
- `output-dir` 已变，但 HTTP 静态/分享路由仍缓存旧目录；
- `github-token` 在两个页签重复，未编辑页签可能用旧值覆盖新值；
- 修改 API Key 后，前端可能立即进入无法解释的 401；
- 保存更新 Cron 时可能错误触发只应在程序启动时执行的更新检查。

### 修复原则

配置保存和配置生效是两个状态，必须分别表达：

1. 磁盘配置是“期望状态”；
2. 运行组件有自己的“已应用状态”；
3. 一轮检测必须固定使用同一份不可变快照；
4. 长期服务必须由专用管理器异步协调；
5. 不能安全热切换的字段必须明确显示“需要重启”，不能假装已生效。

字段最终分为：

| 类型 | 行为 | 示例 |
| --- | --- | --- |
| 立即生效 | 发布后下一次请求读取新值 | `api-key`、`share-password` |
| 下轮生效 | 当前检测继续使用旧快照，下轮使用新快照 | 检测、订阅、存储、通知字段 |
| 托管服务重配 | 异步重建调度器或子进程 | Cron、Sub-Store |
| 下次启动 | 保存成功，但行为只在真实启动流程发生 | `update-on-startup` |
| 需要重启 | 磁盘保存，运行态明确保留旧值 | `listen-port` |

`enable-web-ui` 采用动态访问门，不需要重启；`output-dir` 的 HTTP 路由改为按请求读取已应用目录。

## 第一批：配置快照、统一应用器与真实状态

### 已完成

- 增加期望配置、已应用配置和本轮检测配置三类快照；
- 所有快照使用深拷贝，避免共享 map/slice 被后续修改；
- 当前检测开始时固定配置，直到该轮结束；
- 检测期间保存新配置时进入等待状态，本轮不混入新参数；
- 文件监听和 WebUI 保存走同一条串行应用路径；
- 增加期望版本、已应用版本和配置状态；
- 无效 YAML 或解析失败不会覆盖当前运行配置；
- API 能返回：
  - `applied`
  - `pending`
  - `restart_required`
  - `next_startup`
  - 调度器实际状态
  - Sub-Store 实际状态

### 为什么这样做

根因不是某一个字段漏写监听回调，而是运行协程直接读取一个会被随时覆盖的共享对象。继续逐字段补回调只会留下新的竞态。

### 对用户的影响

- 检测中可以继续保存配置；
- 当前检测不会前半段用旧参数、后半段用新参数；
- 界面会明确告诉用户新配置何时生效；
- 错误配置不会破坏当前正在运行的正确配置。

### 实现与测试

- 核心补丁：`patches/subs-check-pro-v2.6.8-config-runtime-state.patch`
- 覆盖配置深拷贝、版本推进、检测中延迟应用、解析失败保留旧配置和并发顺序测试。

## 第二批：异步单实例 Sub-Store 管理器

### 已完成

- 新增唯一的 `subStoreManager`；
- 配置回调只提交期望规格，不再同步运行 Node 长任务；
- 使用容量为 1 的合并邮箱，快速连续修改只保留最新期望状态；
- Sub-Store 规格不可变，包含：
  - 端口；
  - 路径；
  - 同步 Cron；
  - 生产 Cron；
  - Push 服务；
  - Mihomo 覆写 URL 对应的代理环境；
  - 输出目录；
  - 配置目录；
- 生命周期严格串行：
  - 取消旧服务；
  - 等待退出；
  - 超时后按旧规格 Kill Node；
  - 启动新服务；
- 配置状态能报告 Sub-Store 的期望/已应用版本、端口和运行状态。

### 为什么这样做

Node 是长期子进程，不能让保存配置的 HTTP 请求进入它的运行循环。单一管理器保证任何时刻只有一个所有者负责停止和启动，避免重复 Node、孤儿进程和文件占用竞态。

### 对用户的影响

- 保存 Sub-Store 配置不会卡在“保存中”；
- 修改端口、路径、Cron、Push 或代理模式后，运行中的 Node 会真正重配；
- 快速连续保存最终只运行最后一次配置。

### 实现与测试

- 核心补丁：`patches/subs-check-pro-v2.6.8-substore-runtime-manager.patch`
- 测试覆盖：
  - 保存回调快速返回；
  - 快速连续重配不产生重叠 Runner；
  - 全部运行规格字段参与比较；
  - 正常停止失败时执行 Kill 兜底；
  - 100 轮并发压力测试通过。

## 第三批：监听地址、内部 URL 与动态输出目录

### 已完成

- 增加唯一监听地址解析器，支持：
  - `8199`
  - `:8199`
  - `127.0.0.1:8199`
  - `[::1]:8199`
- 所有内部 HTTP URL 统一使用解析后的数值端口和 IPv4 回环；
- 消除 `http://127.0.0.1:127.0.0.1:<port>/...`；
- `listen-port` 修改后明确标记需要重启；
- `output-dir` 改为可热切换；
- 静态文件、分享文件、受保护文件和分析报告路由每次请求读取当前已应用目录；
- 分享路径增加更安全的目录穿越保护；
- Sub-Store 生成的 `subUserinfo/subInfoUrl` 会按正确地址重写；
- 扫描当前运行产物，没有发现仍需迁移的重复主机名脏记录。

### 为什么这样做

监听地址是“地址”，不是“端口字符串”。手工拼接必然在 host-qualified 配置下出错。输出写入位置和 HTTP 下载位置也必须来自同一个运行态，否则用户会看到“文件已生成但手机下载不到”的分裂状态。

### 对用户的影响

- Sub-Store 流量信息和内部订阅 URL 恢复正确；
- 修改输出目录后，写入和手机访问同时切换；
- 修改监听端口不会突然切断当前手机会话，而是明确提示重启。

### 实现与测试

- 核心补丁：`patches/subs-check-pro-v2.6.8-runtime-address-output.patch`
- 测试覆盖四种监听格式、内部 URL、动态输出路由和路径保护。

## 第四批：WebUI 保存语义与配置字段策略

### 已完成

- WebUI 路由始终注册，通过动态门控制 `enable-web-ui`；
- 当前只有 `listen-port` 被列为必须重启；
- `update-on-startup` 明确列为下次启动生效；
- 启动更新检查与运行中 Cron 重配拆开：
  - `SetupUpdateTasks()` 只在真实启动流程允许执行启动检查；
  - `ReconfigureUpdateTasks()` 保存时只重建定时任务；
- API Key 修改增加 5 分钟旧密钥宽限；
- 前端先暂存新 Key，确认保存成功后再提升为当前 Key；
- 删除重复的 GitHub Token 表单控件，其他区域只引用唯一数据源；
- 保存提示能区分：
  - 已立即生效；
  - 当前检测结束后生效；
  - 服务正在重配；
  - 下次启动生效；
  - 需要重启；
- 建立机器可读字段策略：
  - 89 个唯一表单控件；
  - 96 个完整 YAML 字段路径；
- 为 WebUI JS 增加缓存版本，减少手机继续使用旧脚本的概率。

### 为什么这样做

“保存成功”只证明文件写入成功，不代表运行组件已采用新值。界面必须展示真实运行状态，否则用户无法判断是否需要等待、重启或重新登录。

### 对用户的影响

- 不会再因页签访问顺序把 GitHub Token 悄悄改回旧值；
- 修改 API Key 后不会立刻进入无解释的 401 循环；
- 修改更新 Cron 不会在保存请求中意外触发程序更新或重启；
- 用户能看懂每类配置什么时候生效。

### 实现与测试

- 核心补丁：`patches/subs-check-pro-v2.6.8-webui-config-semantics.patch`
- WebUI 补丁：`patches/subs-check-pro-webui-b8db5f51c367-config-semantics.patch`
- 测试覆盖字段策略完整性、API Key 过渡、动态 WebUI、更新任务语义和保存状态。

## 第五批：发布门禁、构建、部署与运行验收

### 已完成

- 所有新增核心/WebUI 补丁已加入 `scripts/build-custom-core.ps1`；
- 补丁在干净的上游基线提交上通过 `git apply --check`；
- 构建脚本运行：
  - WebUI 测试；
  - `app` 测试；
  - 过滤外部网络用例后的 `proxy` 测试；
  - `check` 测试；
  - Windows amd64 构建；
- 新增实际调度器状态：
  - 模式；
  - Cron 表达式；
  - 检测间隔；
  - 下次运行时间；
- `scripts/verify.ps1` 增加：
  - 所有新补丁签名；
  - 活跃版本；
  - 实际监听端口；
  - 配置期望/已应用状态；
  - 实际 Cron 和未来 `next_run`；
  - Sub-Store 运行规格；
  - 日志脱敏；
  - 公网无 Key 必须返回 401；
- 默认验收不再把真实 API Key 发送到公网；
- 部署前备份核心、配置和统计目录；
- 只停止 subs-check-pro 看护进程、核心和其 Node 子进程；
- Cloudflare Tunnel 部署前后保持同一 PID `10348`；
- Sparkle/Mihomo 未停止、未修改；
- 已安装 MSYS2 UCRT64 GCC 16.1.0 和 mingw-w64 CRT 14；
- Race Detector 发现并修复 Sub-Store 单槽邮箱的并发死锁；
- 修复后 `app` Race 5 轮、Sub-Store 专项 Race 20 轮及 `proxy`、`check` Race 均通过；
- 新核心部署后完整 `verify.ps1` 通过。

### 构建与部署证据

- 构建产物：

  `runtime/bin/subs-check-pro-custom-v2.6.8.exe`

- 当前活跃文件：

  `runtime/bin/subs-check-pro.exe`

- 两者部署时 SHA256：

  `E35EF630C97F299910CDBE4EB349279DB6371B29DA7E3E9D30927D91D1C6B8FD`

- 部署前备份：

  `runtime/backups/config-hot-reload-20260728-1655/`

  内含旧核心、配置和统计数据。

- Race 修复部署前备份：

  `runtime/backups/substore-mailbox-race-20260729-0825/`

### 未做的现场动作

没有主动触发一次真实节点检测，也没有为了测试“检测中保存配置”去改真实生产配置。原因是这些动作会访问第三方订阅、可能发送通知并改写分析历史，超出纯修复验收的无副作用边界。

单元测试已经覆盖检测中快照切换。真实 Cron 已在
2026-07-28 19:00 和 2026-07-29 05:00 两次准时启动；05:00
这一轮在 07:05 完成，运行状态随后报告下一次为当天 19:00。

## 补丁顺序和文件地图

构建时必须保持 `scripts/build-custom-core.ps1` 中的顺序，因为后续补丁建立在前面补丁产生的源码结构上。

本次配置热重载直接相关核心补丁：

1. `patches/subs-check-pro-v2.6.8-cron-hot-reload.patch`
2. `patches/subs-check-pro-v2.6.8-config-runtime-state.patch`
3. `patches/subs-check-pro-v2.6.8-substore-runtime-manager.patch`
4. `patches/subs-check-pro-v2.6.8-runtime-address-output.patch`
5. `patches/subs-check-pro-v2.6.8-webui-config-semantics.patch`
6. `patches/subs-check-pro-v2.6.8-substore-mailbox-race.patch`

本次 WebUI 补丁：

1. `patches/subs-check-pro-webui-b8db5f51c367-config-semantics.patch`

相关入口：

- 总体计划与执行结果：`CONFIG-HOT-RELOAD-FIX-PLAN.md`
- 核心构建：`scripts/build-custom-core.ps1`
- 运行验收：`scripts/verify.ps1`
- 长期架构记忆：`MEMORY.md`
- 用户说明：`README.md`

注意：构建脚本还会应用节点重命名、分析报告、健康历史、UA 回退、历史复检、内部标签清理和沉默订阅档案等旧补丁。不能为了单独验证热重载而删除这些既有补丁。

## 当前 Git 状态

分支和提交：

- 分支：`codex/upgrade-custom-core-v2.6.8`
- HEAD：`0ef99e9`
- 跟踪：`origin/codex/upgrade-custom-core-v2.6.8`

2026-07-29 08:25 的未提交状态：

```text
 M MEMORY.md
 M README.md
 M scripts/build-custom-core.ps1
 M scripts/verify.ps1
?? CONFIG-HOT-RELOAD-FIX-PLAN.md
?? HANDOFF.md
?? patches/subs-check-pro-v2.6.8-config-runtime-state.patch
?? patches/subs-check-pro-v2.6.8-cron-hot-reload.patch
?? patches/subs-check-pro-v2.6.8-runtime-address-output.patch
?? patches/subs-check-pro-v2.6.8-silent-subscription-archive.patch
?? patches/subs-check-pro-v2.6.8-substore-runtime-manager.patch
?? patches/subs-check-pro-v2.6.8-webui-config-semantics.patch
?? patches/subs-check-pro-v2.6.8-substore-mailbox-race.patch
?? patches/subs-check-pro-webui-b8db5f51c367-config-semantics.patch
?? runtime/backups/
```

这里混合了本次五批修复和之前已经部署但尚未提交的沉默订阅档案工作。接手者必须按任务相关性审查 diff，不能假设全部改动都由一个功能产生，也不能覆盖任何现有改动。

## 补充验收结果

### Cron 现场验收

- 2026-07-28 19:00:00 准时启动；
- 2026-07-29 05:00:00 再次准时启动；
- 05:00 这一轮在 07:05:37 完成；
- 完成后日志记录下一次检测为 2026-07-29 19:00；
- 已排除旧的 05:30 调度器仍在运行。

### Windows Race Detector

- MSYS2 安装于 `F:\tools\msys64`；
- GCC 为 UCRT64 16.1.0；
- `libsynchronization.a` 检查通过；
- GCC 路径已加入当前用户 PATH；
- Race 测试发现旧 `Submit` 可能在并发接收后阻塞读取空邮箱；
- 修复补丁为 `patches/subs-check-pro-v2.6.8-substore-mailbox-race.patch`；
- 修复后 Sub-Store 专项 20 轮、完整 `app` 5 轮以及 `proxy`、`check` 均无 Race 报告。

## 当前卡点

### 1. Git 交付尚未收口

- 改动未提交；
- 未推送；
- 没有对应 PR；
- 没有这批变更的 GitHub Actions 结果。

运行环境已经部署成功，不等于源码已经形成可恢复、可审查的正式交付。

### 2. 没有做真实“检测中保存配置”现场实验

这是有意保留的验收项，不是代码缺失。真实实验可能：

- 访问大量第三方订阅；
- 发送通知；
- 改写统计；
- 触发历史累计；
- 在现有超大远程清单风险下影响 Tunnel。

如用户要求现场验证，应先设计小规模、禁通知、可恢复的测试配置，并备份原配置。

### 3. 超大远程清单保护仍未实现

这是本项目当前独立的 P0 稳定性风险：

- 曾出现去重后约 17.6 万节点；
- 单响应正文约 65 MB；
- 发生 Go `0xc0000005`；
- 同一检测期间 Cloudflare Tunnel 曾约 9 分钟不可用。

五批热重载修复没有解决输入规模保护。后续应在昂贵解析和测速前增加：

1. 远程清单链接数上限；
2. 单订阅响应正文大小上限；
3. 去重后候选节点总数上限；
4. 超限中止不累计沉默历史；
5. 日志只记数量，不泄漏 URL。

### 4. 安全和升级仍待处理

- API Key 较短，后续应改强密钥或增加 Cloudflare Access；
- 上游 v2.6.9 已发布，但当前补丁和交付未收口前不要抢先升级；
- 某机场订阅使用字面量 `%0A` 分隔约 803 个 URI，仍需机场修复或本机规范化适配器。

## 下一步计划

### 阶段 A：Cron 与 Race 验收（已完成）

- 19:00 和次日 05:00 的真实 Cron 均已确认；
- Windows GCC 已安装；
- Race 发现的 Sub-Store 邮箱死锁已修复、构建并部署；
- 完整 `verify.ps1` 已通过。

### 阶段 B：形成可审查的 Git 交付

1. 阅读全部 diff：

   ```powershell
   git diff --check
   git status --short
   ```

2. 再次运行完整构建：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\build-custom-core.ps1
   ```

3. 再次运行安全验收：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1
   ```

4. 建议按意图拆分提交：
   - 沉默订阅档案与远程清单过滤；
   - 配置运行态与 Cron/Sub-Store 管理器；
   - 地址、输出目录和 WebUI 配置语义；
   - 构建、验收和文档。
5. 推送分支、创建 PR、等待 Windows CI。

除非用户明确要求，不要擅自提交、推送或创建 PR。

### 阶段 C：处理超大输入保护

先做输入上限设计和测试，再修改真实运行配置。必须保证：

- 超限在大量对象、连接和 goroutine 创建前发生；
- 超限不是“沉默”，不累计健康历史；
- 错误信息说明在哪一层超限；
- 不打印完整订阅 URL；
- 正常规模行为不变。

### 阶段 D：安全加固与上游升级

1. 强化 API Key 或增加 Cloudflare Access；
2. 迁移补丁到 v2.6.9；
3. 手工适配分析报告补丁的上游冲突；
4. 重跑全部核心/WebUI/便携包测试；
5. 再评估 `%0A` 订阅规范化适配器。

## 已踩过的坑

### 配置与运行态

- 只比较磁盘/全局配置不能证明调度器已应用；必须记录运行组件自己的已应用规格。
- 检测协程不能随时读取会变化的共享配置；必须在开始时固定深拷贝。
- 保存成功不能统一显示“已生效”；必须区分下轮、服务重配、下次启动和重启。
- `listen-port` 可能是完整地址，不能手工拼到 `http://127.0.0.1:` 后。
- `output-dir` 写入方和 HTTP 读取方必须读取同一运行态。

### Sub-Store

- 不要在配置回调里同步调用长期运行函数，否则保存请求会卡死。
- 停止旧 Node 时必须使用旧运行规格，不能用新配置去寻找旧进程。
- 快速连续重配必须合并，只执行最终期望状态。
- 曾出现核心重启后旧 `node.exe` 短暂占用文件；新管理器已有等待和 Kill 兜底，仍需观察现场日志。

### 部署

- 第一次替换核心时只杀核心、不先停 `scripts/start.ps1` 看护，旧核心会在复制前被自动拉起。
- 正确顺序是先精确停止 subs-check-pro 看护进程，再停核心和其 Node，复制新核心，最后隐藏窗口重启看护。
- 不要停止 `start-tunnel.ps1` 或 cloudflared。
- 不要停止 Sparkle/Mihomo。
- 部署前确认没有检测正在运行，并先备份核心、配置和统计目录。

### 测试

- Windows Race 使用 `F:\tools\msys64\ucrt64\bin\gcc.exe`；运行前需设置
  `CGO_ENABLED=1`，不要误用 MSYS/Cygwin 环境中的编译器。
- Race 已实际发现过单槽邮箱的“检查到满、随后被接收、再阻塞读取空邮箱”死锁；
  不要把非阻塞 discard 改回直接 `<-manager.requests`。
- 上游 `proxy/isp_test.go` 有 3 个用例直接访问 `ipapi.is`，第三方超时不能作为确定性门禁；构建脚本只跳过这 3 个外部测试。
- 不要无差别运行可能调用 Apprise、S3、代理或其他外部服务的宽泛测试；优先使用构建脚本定义的安全测试集合。
- Sub-Store 压力测试曾因状态先更新、测试 Runner 稍后才递增计数而偶发 `maxActive=0`；测试已增加最多 1 秒等待。不要把这个等待删掉。
- 最终核心语义补丁必须包含 `app/substore_manager_test.go`，否则会丢失上述稳定化修复。

### PowerShell 与构建

- `scripts/verify.ps1` 必须保持纯 ASCII。Windows PowerShell 5.1 会错误解码 UTF-8 无 BOM 中的中文并产生连锁语法错误。
- 上游 v2.6.8 是 annotated tag；构建固定使用剥离后的提交
  `3c5468962e4364c3d5a61b53d90baf10385ea198`。
- Git partial clone 的 OpenSSL 设置必须持久写进临时仓库，否则 sparse checkout 后续取 blob 可能重新落回 schannel。
- 干净模块缓存下，必须先 `go mod download -json` 再读取 WebUI 模块目录，不能假设 `go list -m` 已下载依赖。
- `runtime/bin` 被 Git 忽略，构建脚本必须主动创建目标目录。
- 补丁有依赖顺序；修改早期补丁后要从干净上游基线重新应用全部后续补丁。

### 安全与隐私

- 上游会在 info 日志输出 API Key；启动脚本会持续做等长原位掩码，验收必须继续检查日志。
- `verify.ps1` 默认不得把真实 API Key 发往公网；公开入口只验证管理页可达和无 Key API 返回 401。
- 凭据只记录存放位置，任何交接或日志摘录都不能复制具体值。

### 运行环境

- `sub-urls-remote` 只接收“订阅链接清单”，普通机场订阅应放 `sub-urls` 或 Sub-Store。
- Sub-Store 配置使用纯端口 `8299`，并通过 `SUB_STORE_BACKEND_API_HOST=127.0.0.1` 约束回环。
- 不要开启 Sparkle/Mihomo TUN，否则可能形成嵌套代理并扭曲测速。
- 电脑休眠、关机、用户未登录或 Tunnel 断开时，手机入口不可用。

## 验证命令

### PowerShell 语法

```powershell
[void][scriptblock]::Create(
  (Get-Content -LiteralPath .\scripts\build-custom-core.ps1 -Raw)
)
[void][scriptblock]::Create(
  (Get-Content -LiteralPath .\scripts\verify.ps1 -Raw)
)
```

### 完整构建

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-custom-core.ps1
```

### 包含 Windows Race Detector 的完整构建

```powershell
powershell -ExecutionPolicy Bypass `
  -File .\scripts\build-custom-core.ps1 `
  -RunRaceTests
```

该开关会先验证 PATH 中的 GCC 和 `libsynchronization.a`，再运行
`app` 5 轮以及 `proxy`、`check` Race 门禁；默认构建不会运行 Race。

### 安全默认验收

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1
```

### Git 完整性

```powershell
git diff --check
git status --short --branch
```

## 回滚

部署前备份位于：

`runtime/backups/config-hot-reload-20260728-1655/`

其中包含：

- `subs-check-pro.exe`
- `config.yaml`
- `stats/`

如果新核心出现无法接受的故障：

1. 先确认精确的 subs-check-pro 看护、核心和 Node PID；
2. 只停止这些 subs-check-pro 相关进程；
3. 从备份恢复旧 `subs-check-pro.exe`；
4. 必要时恢复配置和统计文件；
5. 用隐藏窗口重新运行 `scripts/start.ps1`；
6. 运行 `scripts/verify.ps1`；
7. 确认 cloudflared、Sparkle 和 Mihomo 未被停止。

不要使用 Git 重置代替运行文件回滚。

## 凭据与运行数据位置

只记录位置，不记录内容：

- API Key：`runtime/config/config.yaml`
- Sub-Store 私有路径：`runtime/config/config.yaml`
- Tunnel 凭据：`runtime/cloudflared/credentials.json`
- Cloudflare Origin 证书：`C:\Users\tt\.cloudflared\cert.pem`
- 程序日志：`runtime/logs/`
- 检测结果：`runtime/output/`
- 对话附件：`private/conversation-assets/`

## 五批修复的完成定义

工程实现已经完成：

- 配置快照和统一应用器通过测试；
- Sub-Store 保存无阻塞、无重复 Node、运行规格一致；
- 地址、内部 URL 和动态输出目录通过专项测试；
- WebUI 89 个控件、96 个 YAML 路径都有策略；
- 新核心已构建、部署；
- `verify.ps1` 完整通过；
- 当前调度器明确报告当天 19:00。

正式交付仍需：

- 提交、推送、PR 和 CI；
- 另行解决超大输入保护。
