# CleanNest 0.7.0 本机验证报告

日期：2026-08-27
版本：0.7.0（Build 27）
环境：Apple Silicon（arm64）、macOS 26.5.2（25F84）、Xcode 26.6、本地稳定代码签名身份
分支：`agent/0.7-series`
基线提交：`2fe1f2d`（0.6.5 本机封存）

## 结论

0.7.0 的本机里程碑验收通过。冷启动不再启动 Agent XPC 文件遍历；重型工作改为进入对应页面后才运行，离开 Agent/系统状态页后会取消任务并释放文件级快照、进程列表和短期图表。当前 Mac 上，真实冷启动、合成全页巡游和真实 Agent 首扫/重复扫描三组 `physical footprint` 均通过路线图门槛。

这是本地源码与 App 构建验证，不是 GitHub 正式 Release。本报告没有证明 Intel 真机、48 小时耐久、Developer ID 签名、Apple 公证、远端 CI 或 CodeQL 当前状态。

## 0.7.0 验收门

| 验收项 | 本机结果 |
| --- | --- |
| 冷启动不遍历 Agent | 正常启动最终 App，5 秒后主进程存在，`CleanNestScanner` / scanner service 进程不存在；总览只读取无路径的聚合摘要 |
| 冷启动 15 秒 | 98,845,800 bytes，约 **94.3 MiB**，低于 220 MiB |
| 全页巡游非扫描峰值 | 539,739,456 bytes，约 **514.7 MiB**，低于 650 MiB |
| 全页巡游回落 | 返回总览等待 60 秒后 199,394,624 bytes，约 **190.2 MiB**，低于 350 MiB |
| 真实 Agent 首次扫描 | 344,474,872 bytes，约 **328.5 MiB** |
| 真实 Agent 重复扫描 | 334,005,520 bytes，约 **318.5 MiB**，没有随第二次扫描继续增长 |
| 离开 Agent 后回落 | 返回总览等待 60 秒后 206,619,824 bytes，约 **197.0 MiB**，低于 350 MiB |
| 页面任务唯一性 | 菜单栏、指标、模型与 Agent 监测均为单一 Task 槽，重启前取消旧任务；Agent 离页和 App 退到后台会取消监测，生命周期策略有 3 项单元测试 |
| 状态发布域 | `AppStore` 的 `@Published` 从审计时 121 项降至 102 项；20 项 Agent 高频状态进入独立页面域，避免扫描刷新无关页面 |
| 长列表 | 活动、磁盘、应用残留、进程与学习规则使用惰性容器；学习规则首批 100 条、模型记录首批 50 条 |
| 辅助功能 | 最终 0.7.0 App 的辅助功能树真实显示本机学习页标题、214 条待审核/3 条已启用统计、规则名、`审核并启用`、`撤销`、`再显示 100 条`和清空入口 |
| 安全边界 | 文件令牌、XPC 扫描协议、清理/卸载/进程/模型守护执行策略未扩张 |

## 可重现证据

- [冷启动内存 JSON](evidence/0.7.0/memory-cold.json)：真实 Release App，`demoMode=false`。
- [全页巡游内存 JSON](evidence/0.7.0/memory-tour.json)：使用合成界面数据，验证渲染与页面生命周期；不冒充真实文件扫描峰值。
- [Agent 内存 JSON](evidence/0.7.0/memory-agent.json)：真实本机 Agent 扫描，`demoMode=false`。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：118 项测试，0 失败。
- `CleanNestSelfTest`：跨模块自检全部通过。
- `build.sh release`：主 App、登录项、只读 MCP 和扫描 XPC production 编译、组装与签名成功。
- App、登录项与 XPC 的实际 Bundle Info.plist 均为 `0.7.0`；主 App Build 为 `27`。
- 直接向最终 Bundle 内的 `CleanNestMCP` 发送现代 `initialize`，`serverInfo.version` 返回 `0.7.0`。
- `codesign --verify --deep --strict` 通过；本地签名指定要求为 `identifier "com.zone.cleannest"` 加本地证书根。
- `bash -n build.sh scripts/verify-memory-budget.sh`、四份 plist/entitlement lint 和 `git diff --check` 通过。
- 最终 App 重新启动后，辅助功能树真实显示 `CleanNest 0.7.0 · 构建 27` 与本地引擎就绪。

## 架构结果

1. `AppLifecyclePolicy` 将冷启动白名单和 11 个页面的前台工作负载变成可测试的值类型策略。
2. Agent 冷启动状态改为 `AgentWorkspaceSummary`；编码与持久化测试证明它不含绝对路径、打开文件、源路径、最大文件路径或动作候选。
3. Agent XPC 请求成为可取消的显式 Task；离页取消不会发布半成品。
4. 本机学习与磁盘手动决策采用按需加载，但任何修改入口都会先读取已有持久化记录，避免异步竞态把旧数据覆盖为空白。
5. 页面离开 15 秒后只释放可重建的展示数据，不清理用户历史、不删除恢复包，也不改变选择或安全策略。

## 尚未证明

- 全页巡游使用合成数据，只证明非扫描交互与渲染生命周期；真实 Agent 扫描由独立的 `agent` 场景覆盖，清理和磁盘大扫描峰值沿用各自专项门禁。
- 没有完成 48 小时常驻、多轮睡眠/唤醒、Intel 真机或所有语言 VoiceOver 回归；这些仍属于 0.7.5/0.7.9。
- 当前全局 `xcode-select` 仍指向 Command Line Tools；验证命令通过 `DEVELOPER_DIR` 显式使用完整 Xcode，没有修改用户全局工具链。
- `Yuan OS Local Code Signing` 只保持本机 TCC 身份稳定，不是 Apple Developer ID；没有公证、staple、Gatekeeper 分发验证或普通用户安装包。
- 本轮没有推送、创建 PR、合并、打 tag 或发布 GitHub Release；远端状态没有被本报告冒充为通过。
