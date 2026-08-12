# 更新记录

本项目采用 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 的结构，并按语义化版本思路记录用户可见变化。

## [Unreleased]

### Added

- 为 `CleanNestCore` 增加标准 Swift 单元测试，并在 CI 中收集覆盖率。
- 增加 Apple Silicon 与 Intel 的编译和测试兼容性检查。
- 增加 Pull Request 依赖审查，阻止引入中高危已知漏洞。
- 增加贡献、行为准则、支持、Issue/PR 模板及代码所有者配置。
- 增加权限、本机 AI、架构、隐私、故障排查和发布流程文档。
- 增加完整的 English、繁體中文、日本語和한국어 README，并在各语言版本中明确当前界面语言与源码发布状态。

### Changed

- 使用真实签名身份构建时启用 Hardened Runtime 和可信时间戳，为后续 Apple 公证做准备。

## [0.3.1] - 2026-08-03

### Added

- 原生 macOS SwiftUI 图形界面，覆盖总览、空间清理、应用卸载、磁盘浏览、系统状态、维护和活动记录。
- Mole CLI 自动发现、App 内 Homebrew 安装/更新及自定义路径。
- 本机 MLX/Gemma 清理分析与磁盘目录解释，含严格回环地址、脱敏请求和结构化响应校验。
- 内存压力、高占用进程说明及带身份复核的正常/强制终止确认。
- 完全磁盘访问探测、受保护目录阻断、符号链接保护和废纸篓恢复策略。
- CodeQL、Dependabot、分支保护和完整 App Bundle CI。

[Unreleased]: https://github.com/n9896027/CleanNest/compare/v0.3.1...HEAD
[0.3.1]: https://github.com/n9896027/CleanNest/releases/tag/v0.3.1
