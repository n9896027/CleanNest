# CleanNest 0.7.3 本机验证报告

日期：2026-08-27  
版本：0.7.3（Build 30）  
范围：应用卸载依赖地图、逐项决定、失败关闭状态机与恢复位置

## 结论

0.7.3 的本机源码里程碑通过。应用卸载现在先建立有证据等级的只读依赖图，再按六阶段状态机处理 App 本体和用户明确选择的精确相关文件。只要本体没有由系统确认进入废纸篓，相关文件执行门就保持关闭，变更数为零。

这不是对真实个人 App 的破坏性验收，也不是 GitHub Release。自动化只在临时目录使用受约束的回收替身；界面验证使用合成 Figma 数据。构建使用本机稳定签名，不具备 Developer ID 和 Apple 公证信任链。

## 已验证行为

| 路径 | 证据 | 结果 |
| --- | --- | --- |
| 成功 | 临时 App、精确 Bundle ID 相关文件、受约束回收器 | 本体确认成功后才开放相关文件；返回两类恢复位置 |
| 用户取消 | `NSUserCancelledError` 路由测试 | 本体保持原位，相关文件零变更 |
| 认证失败 | `NSFileWriteNoPermissionError` 路由测试 | 明确归类为认证拒绝，相关文件零变更 |
| App 身份变化 | 扫描后替换临时目标的设备/文件身份测试 | 身份重验失败并关闭处置门 |
| Finder 自动化拒绝 | Apple Event `-1743` 错误域路由测试 | 与系统认证失败分开说明，相关文件零变更 |

## 所有权与动作边界

- 精确 Bundle ID、精确名称或明确持久化后缀可形成 App 所有节点；用户可逐项选择是否在本体成功后处理。
- App 内嵌的登录项与扩展只显示关系，随 App 本体一起移动，不单独处置。
- App Group、系统容器、系统 launchd 配置、用户守护配置和仅名称相似的项目保持只读。
- 相关文件执行器再次校验允许根、普通文件类型、设备号、文件号、所有者和修改时间；失败项不移动并可重试。

## 自动化结果

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
  - 136 项测试，0 失败。
  - 其中新增 4 项依赖图/卸载门测试。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run CleanNestSelfTest`
  - 自检通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./build.sh release`
  - App、登录项、扫描服务和 MCP 以 0.7.3（Build 30）构建。
  - `plutil` 与嵌套 `codesign --verify --deep --strict` 通过。

## 界面证据

使用 `CLEANNEST_DEMO=1` 启动本机 App，辅助功能树确认：

- 签名、Launch Services 注册路径和稳定身份证据可读。
- 六阶段状态可读。
- App 所有、随本体、共享、系统管理项目分组可读。
- 单个缓存项目取消勾选后，预计相关文件数量同步从 1 变为 0；这验证了逐项决定是真实交互，不是静态说明。

没有在界面测试中点击真实卸载，也没有移动用户个人文件。

## 仍未完成

- 尚未取得 Developer ID 签名和 Apple 公证。
- 尚未在专用可牺牲测试账号中完成真实 App 的五条端到端系统授权路径；当前证据是临时文件系统行为、原生错误域路由、状态门单元测试和合成 UI。
- 尚未创建远端 PR、合并或发布；这些动作需要单独授权。

