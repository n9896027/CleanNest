# CleanNest 0.8.4 验证报告（总览页重构）

日期：2026-08-30
版本：0.8.4（Build 42）
分支：`agent/0.8.4-overview-redesign`（叠在 `agent/0.8.3-learning-copy` 上）
性质：本机开发里程碑，未创建 GitHub tag 或 Release

## 结论

按"简洁图形界面、少文字术语"的方向重构总览页信息层级。零逻辑变更（任务数据源、动作入口、状态采样全部复用）；全量测试 193 项通过；本机已替换 0.8.4（42）并截图确认。

## 问题诊断

原总览页把"审计证据"和"下一步动作"混在同一层级：

- 每张任务卡携带"来源/最后验证/影响/为什么现在"四列——是审计栏，不是任务卡；
- "现在最值得做"并列三张等重的卡，没有"最"；
- "只读状态快照"用一整行防御性说明（"这些数字只用于判断，不是按钮"）回答用户从没问过的问题；
- "常用任务"带防御性副标题。

## 改动清单（`Sources/CleanNest/OverviewView.swift`）

- **主行动卡（hero）**：`priorityTasks.first` 单独成卡——大图标 + 标题 + 状态 pill + 一句话 + 胶囊大按钮；窄窗口自动换为纵向布局（ViewThatFits）。
- **次要事项紧凑行**：其余任务一行一条（小图标 + 标题 + pill + chevron），长文 detail 不再占据总览首屏。
- **状态小节**："只读状态快照"卡 + 免责声明 + "只读" pill 全部删除，改为小节标题"状态" + 三块既有指标块（可用空间/清理扫描/内存压力，视觉不变）。
- **常用任务**：副标题删除。
- **数据结构**：`PriorityTask` 去掉 source/verifiedAt/impact/reason 四个字段；删除 taskFacts/taskFact/verificationText/focusSource/focusVerifiedAt/focusImpact/focusReason 等不再使用的辅助函数；无障碍标签同步精简（不再朗读四列审计信息）。

## 验证

- `swift test`（Xcode 工具链）：193 项，0 失败，1 按设计跳过。
- `./build.sh release` + `codesign --verify --deep --strict`：通过。
- 本机替换后截图确认（0.8.4 (42)）：hero 卡"还没有清理清单"+ 蓝色胶囊按钮"扫描可清理内容"；两条次要紧凑行；"状态"三指标块无免责声明；"常用任务"无副标题；"最近结果"保持。
- 沿用 0.8.2 教训：构建前用进程轮询确认旧实例完全退出（`while pgrep ...; do sleep 1; done`）。

## 边界与后续

- 任务优先级判断逻辑（FocusState 规则）未改，只改了呈现。
- "最近结果"的口径说明（"累计成果独立保存；清空明细不会归零…"）仍在，属事实性提示，保留。
- 真实 48 小时常驻、三语言 UI 门、Developer ID/公证与此前相同，未过门。
