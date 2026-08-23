# macOS 权限说明

## “一次性让整个 App 访问文件”是什么

macOS 中最接近一次性授权的是“系统设置 → 隐私与安全性 → 完全磁盘访问”。它针对一个具有稳定代码身份的 App 生效，不是 CleanNest 自己能静默申请或绕过的权限。

文件夹选择器授予的是用户明确选择的位置；完全磁盘访问则可能允许读取 `Library/Containers`、`Group Containers`、`Mobile Documents` 等受保护区域。即使已授权，CleanNest 仍只扫描当前功能声明的范围。

## 推荐授权流程

1. 把最终使用的 `CleanNest.app` 放到稳定位置（建议 `/Applications`），不要一边运行一边覆盖它。
2. 在 CleanNest“设置 → 安全与权限”打开完全磁盘访问设置。
3. 在系统列表中添加并开启这个确切的 App；如列表中有旧副本，先核对路径。
4. 返回 CleanNest。App 只做一次轻量访问测试，不会连续启动 Mole 或 `du` 触发弹窗。
5. 状态显示“访问测试通过”后再分析受保护目录。

macOS 没有公开 API 能直接读取完全磁盘访问开关。CleanNest 只根据一次实际访问是成功、明确被拒绝还是无法判断来显示状态，因此“设置页已打开”不等于“授权已成功”。

电池状态来自系统电源接口，不依赖完全磁盘访问。Mac mini、Mac Studio、Mac Pro 与 iMac 没有内置电池时，CleanNest 会明确显示“没有内置电池”；只有命令或解析真正失败时才显示“读取失败”。

## 为什么重建后权限可能失效

TCC 会结合 App 路径、Bundle ID 和代码签名身份识别应用。ad-hoc 签名常随每次构建改变代码哈希，系统可能把新构建视为另一个应用。

- CI 和临时开发构建使用 ad-hoc 签名，只用于验证，不适合作为长期授权副本。
- 本地长期使用应保持 App 路径和签名身份不变。
- 正式公开分发应使用 Developer ID Application 签名并完成 Apple 公证。

`build.sh` 可通过 `CLEANNEST_CODESIGN_IDENTITY` 指定已有签名身份；不要把证书、私钥或公证凭据写入仓库。

## 仍然无法访问

- 确认系统设置里授权的是当前运行副本，而不是 `build/` 中的旧 App。
- 完全退出所有 CleanNest 进程后重新打开稳定路径中的 App。
- 如果刚覆盖了 App Bundle，请移除旧授权条目，再把当前副本重新加入。
- 查看 CleanNest 的技术详情；不存在、I/O 错误等“不确定”状态不会被误报成权限拒绝。

更多现象见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)。
