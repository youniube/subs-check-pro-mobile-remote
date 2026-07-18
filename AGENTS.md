# 项目说明

- 项目名：subs-check-pro-mobile-remote
- 初始化日期：2026-07-17
- 技术栈：Windows 10、PowerShell 5.1、Go 二进制、Cloudflare Tunnel
- 项目用途：在常开 Windows 电脑上运行 subs-check-pro，通过手机远程添加订阅、发起测速并查看结果

## 项目约束

- 开始工作前先读取本项目的 `AGENTS.md` 和 `MEMORY.md`。
- 技术决策说明“为什么”以及“对用户的影响”。
- 修改后运行与变更风险相匹配的检查或测试。
- 不覆盖用户已有且与当前任务无关的改动。
- 不修改或停止本机现有 Sparkle/Mihomo 代理；subs-check-pro 使用独立端口并默认直连。
- 凭据只记录存放位置，不写入文档或命令输出。

## 常用命令

- 安装：`powershell -ExecutionPolicy Bypass -File .\scripts\install-current-user.ps1`
- 启动：`powershell -ExecutionPolicy Bypass -File .\scripts\start.ps1`
- 测试：`powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1`
- 构建：不适用（使用官方校验过的 Windows x86_64 Release）
