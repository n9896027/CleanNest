# CleanNest 0.6.5 本机封存验证报告

日期：2026-08-27  
版本：0.6.5（Build 26）  
环境：当前 Apple Silicon Mac、macOS 26.5.2、完整 Xcode 工具链、本地稳定代码签名身份

## 结论

0.6.5 已完成本地源码封存：App、登录项、独立扫描服务与只读 MCP 的版本均为 0.6.5（Build 26），113 项正式测试和跨模块自检通过，Release App Bundle 完成稳定本地签名与嵌套结构验证，重启后辅助功能树已真实显示 `CleanNest 0.6.5 · 构建 26`。

这是“本机封存完成”，不是“远端发布完成”。本轮没有提交、推送、合并、创建 tag 或 GitHub Release；也没有 Developer ID 签名和 Apple 公证安装包。

## 可重现证据

| 项目 | 结果 |
| --- | --- |
| 版本源 | `Resources/Info.plist`、登录项 plist、扫描 XPC plist 均为 `0.6.5` / `26`；MCP 源版本为 `0.6.5` |
| 实际 App Bundle | 构建后三份 Info.plist 实读均为 `0.6.5`，App Build 为 `26` |
| 实际 MCP | 直接向内置 `CleanNestMCP` 发送现代 `initialize`，`serverInfo.version` 返回 `0.6.5` |
| 语法与 plist | `bash -n build.sh` 通过；App、登录项、扫描服务和 entitlement 的 `plutil -lint` 全部通过 |
| 正式测试 | 使用 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：113 项全部通过，0 失败 |
| 集成自检 | 使用完整 Xcode 工具链运行 `CleanNestSelfTest`：全部检查通过 |
| Release 构建 | CleanNest、只读 MCP、登录项与独立扫描服务完成 production 编译与 App Bundle 组装 |
| 签名 | 使用 `Yuan OS Local Code Signing`；App、MCP、登录项和 XPC 通过 strict/deep 签名验证，指定要求在发布前后一致 |
| 启动验证 | 最终进程来自 `build/CleanNest.app`；主窗口实测显示 0.6.5（Build 26），本地引擎就绪 |
| 全栏目巡检 | 总览、清理、卸载、磁盘、系统状态、系统维护、Agent、本地模型、本机学习、活动和设置完成只读巡检；未触发任何高风险动作 |
| 凭据审计 | 高置信私钥、GitHub/OpenAI/AWS token 特征扫描命中文件为 0；未将本机用户绝对路径写入当前交付文档 |
| 仓库基线扫描 | 社区/安全/发布文档信号齐全；未固定 Action 为 0，不可信上下文内联信号为 0，潜在凭据信号为 0 |
| diff 质量 | `git diff --check` 通过 |

## 内存证据与 0.7.0 阻断项

最终 0.6.5 构建冷启动后：

- 约 2 秒时 `ps` RSS 为 200,272 KiB。
- 约 39 秒、启动任务完成后 `ps` RSS 为 192,864 KiB。
- 同一时点 `vmmap` physical footprint 为约 401.5 MiB，启动峰值约 427.3 MiB。

在此前的全页巡游进程中，同一功能集的 physical footprint 约 440.1 MiB，进程历史峰值约 1.5 GiB。这证明冷启动 RSS 已不是 1.2 GiB，但也证明逐页使用后的峰值和回落仍未通过发布级预算。该项已被设为 [0.7.0](ROADMAP-0.7.md) 的 P0 门，不在本报告中冒充“已解决”。

## 全栏目结论

详细的每页功能、交互、性能和无障碍结论见 [0.6.5 全栏目审计](AUDIT-0.6.5.md)。目前最重要的三个结论是：

1. 安全和恢复边界强于产品分层；下一阶段不应优先增加新扫描器。
2. `AppStore` 和多个大型页面已达到架构与内存瓶颈，0.7.0 必须先拆分状态发布面和页面生命周期。
3. “本机学习”页在本轮辅助功能树中几乎不可读；这是已知缺口，不能被视觉截图掩盖。

## 尚未证明

- 当前 shell 的全局 `xcode-select` 仍指向不含 XCTest 的 Command Line Tools；本报告使用已安装的完整 Xcode 进行命令级选择。未全局改写用户工具链设置。
- 没有完成 48 小时常驻、多次睡眠/唤醒、页面巡游后内存自动预算或 Intel 真机 UI 验收。
- 本轮没有从 GitHub 刷新远端 CI、CodeQL、Dependency Review、告警或 ruleset 状态，不将本地结果写成远端通过。
- 当前签名身份是本地稳定签名，不是 Developer ID；没有公证、staple、Gatekeeper 分发验证或面向消费者的安装包。
- 本地分支仍有大量未提交的 0.6.4/0.6.5 实施文件；封存只完成工作树和本机产物，还没有形成可追溯的提交、PR 或 tag。

## Git 状态

- 分支：`agent/agent-workspace-0.6.4`
- 当前基础提交：`b76e6a3`
- `main` / `origin/main`：`77ca3e5`
- 本轮未提交、未推送、未合并、未创建 tag 或 Release。
