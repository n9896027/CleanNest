# 参与贡献

感谢你愿意改进 CleanNest。这个项目会读取磁盘元数据并提供清理入口，因此正确性、可解释性和可恢复性优先于功能数量。

## 开始之前

- 普通缺陷和小改动可以直接提交 Pull Request。
- 涉及新扫描范围、删除行为、管理员权限、网络地址或第三方二进制的大改动，请先开 Issue 说明边界。
- 安全漏洞不要公开提交，请按 [SECURITY.md](SECURITY.md) 使用 GitHub 私密漏洞报告。
- 截图、日志和测试数据必须移除用户名、绝对路径、令牌及个人文件名。

## 开发环境

- macOS 14 或更高版本
- 当前稳定版 Xcode（推荐）或带完整测试框架的 Xcode Command Line Tools
- Swift 5.9 或更高版本

克隆后不需要下载 Swift 包依赖：

```bash
swift test
swift run CleanNestSelfTest
CLEANNEST_CODESIGN_IDENTITY="-" ./build.sh release
```

使用演示数据检查界面，不会扫描或修改真实文件：

```bash
CLEANNEST_DEMO=1 swift run CleanNest
```

## 不可破坏的安全约束

- AI 输出只能注释本次请求中的 token，不能产生路径、命令、勾选或删除动作。
- 原生清理必须限制在允许根目录的严格后代，并拒绝符号链接。
- 删除默认进入废纸篓；不得引入不可恢复的递归删除。
- 完全磁盘访问只能根据实际访问结果描述，不能把“已打开系统设置”当成授权成功。
- 进程关闭必须复核 PID 身份并保护系统/关键进程，强制结束需要额外确认。
- 外部模型端点只能是显式的 `http://127.0.0.1:<端口>/v1`，且不得跟随重定向。

更改这些边界时，请同时增加单元测试和 `CleanNestSelfTest` 的回归检查。

## Pull Request 要求

- 一个 PR 解决一个清晰问题，说明用户可见变化和风险。
- 写明实际运行过的测试；不能运行的检查需说明原因。
- UI 改动附上无隐私信息的前后截图。
- 更新用户行为时同步 README、相关 `docs/` 文件和 `CHANGELOG.md` 的 `Unreleased` 段落。
- 不提交构建产物、模型文件、凭据、开发者证书或公证配置。

维护者会优先使用 squash 或 rebase 合并，以保持线性历史。
