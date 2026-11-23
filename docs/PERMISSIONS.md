# macOS 权限说明

## “一次性让整个 App 访问文件”是什么

macOS 中最接近一次性授权的是“系统设置 → 隐私与安全性 → 完全磁盘访问”。它针对一个具有稳定代码身份的 App 生效，不是 CleanNest 自己能静默申请或绕过的权限。

文件夹选择器授予的是用户明确选择的位置；完全磁盘访问则可能允许读取 `Library/Containers`、`Group Containers`、`Mobile Documents` 等受保护区域。即使已授权，CleanNest 仍只扫描当前功能声明的范围。

## 推荐授权流程

1. 把最终使用的 `CleanNest.app` 放到稳定位置（建议 `/Applications`），不要一边运行一边覆盖它。
2. 在 CleanNest“设置 → 安全与权限”打开完全磁盘访问设置。
3. 在系统列表中添加并开启这个确切的 App；如列表中有旧副本，先核对路径。
4. 返回 CleanNest。App 只做一次轻量访问测试，不会连续启动外部引擎或递归扫描触发弹窗。
5. 状态显示“访问测试通过”后再分析受保护目录。

macOS 没有公开 API 能直接读取完全磁盘访问开关。CleanNest 只根据一次实际访问是成功、明确被拒绝还是无法判断来显示状态，因此“设置页已打开”不等于“授权已成功”。

电池状态来自系统电源接口，不依赖完全磁盘访问。Mac mini、Mac Studio、Mac Pro 与 iMac 没有内置电池时，CleanNest 会明确显示“没有内置电池”；只有命令或解析真正失败时才显示“读取失败”。

Agent 工作区默认检查当前用户的 `~/.codex`、`~/.claude` 和 Claude Application Support。这些路径通常不需要单独授权；如果 macOS 或文件 ACL 拒绝某个子目录，CleanNest 会标记扫描不完整并禁止它进入回收预览，不会循环弹出授权窗口。

## App 卸载与管理员认证

完全磁盘访问只解决受保护数据的读取问题，不会自动赋予 root 权限。CleanNest 卸载 App 时先复核目标仍是标准 Applications 目录中的同一 App，并检查当前账户对来源目录和废纸篓的真实写入权限。

- 如果当前管理员账户已经可以移动 `/Applications` 中的项目，CleanNest 使用同卷原子重命名直接移入当前用户废纸篓，不会因为 App 显示为 `root` 所有就制造无效认证提示。
- 如果权限确实不足或无法同卷移动，CleanNest 才请求 Finder 执行废纸篓操作；macOS 可能先询问是否允许 CleanNest 控制 Finder，再显示系统管理员认证。CleanNest 不接收、读取或保存管理员密码。
- 只有 App 本体已从原路径消失且在废纸篓中得到确认后，才会处理预览中按精确 Bundle ID 匹配的相关文件。任何取消、权限拒绝、目标变化或结果不确定都会停止后续处理。

启用 Hardened Runtime 的构建只为 GUI App 签入 `com.apple.security.automation.apple-events`，并在 Info.plist 提供 `NSAppleEventsUsageDescription`；内置只读 MCP 不带该 entitlement，也不链接 AppKit 或 Apple Events 实现。即使存在 entitlement，首次控制 Finder 仍必须由用户在 macOS 权限窗口中明确允许。

## 为什么重建后权限可能失效

TCC 会结合 App 路径、Bundle ID 和代码签名身份识别应用。ad-hoc 签名常随每次构建改变代码哈希，系统可能把新构建视为另一个应用。从旧自签名或 ad-hoc 副本升级到 Developer ID 版本时，签名身份发生变化，macOS 也可能要求重新授权；这不代表已有设置、活动、指标或恢复记录应被清除。

- CI 和临时开发构建使用 ad-hoc 签名，只用于验证，不适合作为长期授权副本。
- 本地长期使用应保持 App 路径和签名身份不变。
- 正式公开分发使用 Developer ID Application 签名并完成 Apple 公证；PKG 另使用 Developer ID Installer。
- 升级后只授权当前的 `/Applications/CleanNest.app`；先退出并移除指向旧路径或旧构建的重复权限条目，再重新测试访问。
- 不要为了保留旧权限而继续运行 `build/` 中的历史副本，也不要把权限重新授权等同于清除应用数据。

`build.sh` 可通过 `CLEANNEST_CODESIGN_IDENTITY` 指定已有签名身份；不要把证书、私钥或公证凭据写入仓库。

## 仍然无法访问

- 确认系统设置里授权的是当前运行副本，而不是 `build/` 中的旧 App。
- 完全退出所有 CleanNest 进程后重新打开稳定路径中的 App。
- 如果刚覆盖了 App Bundle，请移除旧授权条目，再把当前副本重新加入。
- 查看 CleanNest 的技术详情；不存在、I/O 错误等“不确定”状态不会被误报成权限拒绝。

更多现象见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)。
