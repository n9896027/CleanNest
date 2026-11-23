# 本地化覆盖状态

CleanNest 的源码语言是简体中文。正式对外宣称“完整支持”的语言必须同时满足：String Catalog 有非空翻译、格式占位符一致、主要页面没有回落到简体中文、窄窗口与长文案没有截断关键动作，并完成键盘与 VoiceOver 人工回归。

## 当前自动审计

`Tools/LocalizationAudit.swift` 对 `Resources/Localizable.xcstrings` 做结构、三语言非空值和格式占位符校验，并以 Swift 词法扫描检查直接显示的中文字符串；扫描能区分注释，处理嵌套插值和跨行调用，Unicode 汉字范围不会把中文标点误报为缺口：

```bash
swift Tools/LocalizationAudit.swift Resources/Localizable.xcstrings Sources/CleanNest --strict-source --verbose
```

截至 0.12.2（52）本机 Debug 候选：

- String Catalog：2672 个条目；简体中文、English、繁體中文三种语言均有 2672 个非空值。
- 三语言的 `%@`、`%d` 等格式占位符与源文案一致。
- 源码直接 UI 检查未发现未进入 Catalog 的静态中文字符串：0 条。
- 源码直接 UI 检查未发现仍需改造的运行时插值中文字符串：0 条。
- 已修复指标、年龄、扫描完整度、维护诊断、模型状态、活动与学习事件等变量显示路径的语言回落，避免静态键齐全但运行时组合文案仍回落源语言。
- 0.12.2 新增自动检查设置、更新确认、下载与校验进度、失败原因和安装器按钮均进入 Catalog；真实简体中文更新流程已完成只读及下载验收，但其他语言仍需按版本人工复核。
- 2026-11-23 完整 XCTest：299 项，0 失败，1 项按既有条件跳过。

这表示自动源码覆盖门已通过，不代表三语言人工验收已经完成。900 px 窄窗口、长文案、明暗色、键盘与 VoiceOver 仍须按版本逐项实测；未执行的项目保持未通过。日文和韩文仅提供 README，不在 App 完整本地化声明内。

## 三语言截图复核

2026-11-20 第三轮已生成并复核当前 `build/ui-regression/` 根目录的 33 张 900×700 截图（每语言 11 页）及三张联系表，并额外复核英文、繁体的磁盘与维护单张截图。此前由变量显示路径造成的英文中文回落、繁体简体回落已消失。

这些截图只覆盖演示数据的初始视口，不覆盖滚动区域、展开面板、完整明暗色组合、键盘或 VoiceOver；它们是与自动源码门互补的候选证据，不能替代 `docs/VERIFICATION-0.11.0.md` 的 UI-01～UI-08 人工验收。

## 发布门

- 普通 CI 会验证 Catalog 三语言条目非空且格式占位符一致；本机候选脚本额外打印源码覆盖诊断。
- `CLEANNEST_REQUIRE_STRICT_LOCALIZATION=1 scripts/verify-release-candidate.sh` 会在任何直接 UI 缺口存在时失败。
- 只有严格源码门通过，并完成 900 px 窄窗口、长文案、键盘和 VoiceOver 人工回归后，README/Release 才能改成“完整支持”。

这个状态页区分“自动检查与初始视口截图已通过”和“用户界面已完成人工验收”，避免把 Catalog 数量或截图数量冒充真实使用质量。
