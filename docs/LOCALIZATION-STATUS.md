# 本地化覆盖状态

CleanNest 的源码语言是简体中文。正式对外宣称“完整支持”的语言必须同时满足：String Catalog 有非空翻译、主要页面没有回落到简体中文、窄窗口与长文案没有截断关键动作，并完成键盘与 VoiceOver 人工回归。

## 当前自动审计

`Tools/LocalizationAudit.swift` 对 `Resources/Localizable.xcstrings` 做结构校验，并可额外检查 SwiftUI 直接显示的中文字符串：

```bash
swift Tools/LocalizationAudit.swift Resources/Localizable.xcstrings Sources/CleanNest
```

截至 0.7.9 候选：

- String Catalog：795 个条目；简体中文、English、繁體中文三种语言均有 795 个非空值。
- 源码直接 UI 检查仍发现 194 个未进入 Catalog 的静态中文字符串。
- 另有 73 个带运行时插值的中文字符串需要逐条改成可验证的格式化本地化，不能只用机器替换占位符。

因此，English 与繁體中文目前是“已有较大范围翻译、仍会局部回落中文”，不是完整覆盖。日文和韩文仅提供 README，不在 App 完整本地化声明内。

## 发布门

- 普通 CI 会验证 Catalog 三语言条目均非空；本机候选脚本额外打印源码覆盖诊断。
- `CLEANNEST_REQUIRE_STRICT_LOCALIZATION=1 scripts/verify-release-candidate.sh` 会在任何直接 UI 缺口存在时失败。
- 只有严格源码门通过，并完成 900 px 窄窗口、长文案、键盘和 VoiceOver 人工回归后，README/Release 才能改成“完整支持”。

这个状态页有意保留真实缺口，避免把“Catalog 里有翻译”冒充“用户在整个 App 都能看到完整翻译”。
