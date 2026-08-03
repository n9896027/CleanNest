<div align="center">

# CleanNest

**看懂 Mac 空间占用，再安全清掉真正可以删除的内容。**

原生 macOS 图形客户端，整合 Mole 与本机 MLX/Gemma。扫描和分析留在本机，删除默认进入废纸篓。

[![CI](https://github.com/n9896027/CleanNest/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/n9896027/CleanNest/actions/workflows/ci.yml)
[![CodeQL](https://github.com/n9896027/CleanNest/actions/workflows/codeql.yml/badge.svg?branch=main)](https://github.com/n9896027/CleanNest/actions/workflows/codeql.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple)
![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)
[![MIT License](https://img.shields.io/badge/License-MIT-2F81F7.svg)](LICENSE)

[查看发布页](https://github.com/n9896027/CleanNest/releases) · [报告问题](https://github.com/n9896027/CleanNest/issues) · [安全报告](SECURITY.md)

</div>

![CleanNest 总览界面](docs/images/overview.png)

CleanNest 希望把“清理 Mac”从一个黑盒按钮变成可理解、可撤销的过程：先告诉你空间去了哪里、目录通常属于什么，再由你决定是否处理。它提供完整的 SwiftUI/AppKit 界面，普通使用不需要操作终端，也不会因为 AI 建议而自动删除文件。

## 为什么使用 CleanNest

| 你遇到的问题 | CleanNest 的处理方式 |
| --- | --- |
| 磁盘空间突然不足，却不知道是什么占满了 | 按目录和文件大小浏览，并用中文解释常见目录用途 |
| 缓存、下载文件和真实个人数据混在一起 | 区分可重建缓存、需复核项目与应保留内容 |
| 活动监视器信息太技术化 | 展示内存压力、交换空间和高占用进程，并解释关闭影响 |
| 卸载 App 后担心残留 | 只预览与 Bundle ID 精确匹配的相关文件 |
| 不想把文件清单发到云端 | 可选使用本机 MLX/Gemma，仅分析受限元数据 |

## 核心能力

- **清理空间**：扫描开发缓存、日志、安装包等候选项，逐项选择后移入 macOS 废纸篓。
- **磁盘浏览**：从文件夹大小出发逐层定位空间占用，并支持本机 AI 解读当前目录构成。
- **系统状态**：显示 CPU、内存、磁盘、电池、温度与健康状态；补充内存压力和进程说明。
- **进程管理**：在身份复核、系统进程保护和二次确认后请求正常退出进程，不自动强制结束。
- **应用卸载**：浏览已安装 App，预览 App 本体及精确匹配的相关文件。
- **系统维护**：按任务运行低风险维护动作，并集中记录结果。
- **Mole 集成**：自动发现 Apple Silicon 或 Intel Homebrew 安装的 `mo`，也可直接在 App 内安装或更新。
- **原生体验**：支持明暗色、自恢复权限引导、活动记录与演示模式。

## 下载与运行

> [!NOTE]
> 当前仓库尚未提供经过 Apple 公证的预编译安装包。日常使用 CleanNest 不需要终端，但现阶段从源码生成 App 仍需运行一次构建命令。后续可下载版本会发布在 [Releases](https://github.com/n9896027/CleanNest/releases)。

系统要求：

- macOS 14 Sonoma 或更高版本
- Xcode Command Line Tools（仅源码构建需要）
- Mole CLI（可选，CleanNest 可在 App 内免费安装）
- Apple Silicon Mac 与 `mlx-lm`（仅本机 AI 功能需要）

从源码构建：

```bash
git clone https://github.com/n9896027/CleanNest.git
cd CleanNest
./build.sh
open build/CleanNest.app
```

构建完成后，后续扫描、分析、清理、维护以及 Mole 安装都可以在 App 内完成。

## 本机 MLX / Gemma（可选）

CleanNest 可以连接本机 `mlx_lm.server`，为清理候选和磁盘目录补充用途解释、风险提示与查看顺序。模型不是清理引擎：规则扫描在没有 AI 时仍可正常工作，AI 失败也不会影响已有结果。

隐私和执行边界：

- 只允许显式的 `http://127.0.0.1:<端口>/v1`，不连接局域网或公网模型服务。
- 请求只包含类型、大小、时间、受限 token 和脱敏路径提示等元数据，不读取文件内容。
- 磁盘分析只采样有限数量的子项构成，不发送完整目录树。
- Swift 客户端严格验证模型返回的字段、枚举和项目身份。
- AI 只能显示建议，不能扩大扫描范围、改变勾选、关闭进程或执行删除。

在“设置 → 本机 AI 分析”中选择现有 MLX 模型目录和 `mlx_lm.server`。CleanNest 会优先复用已经运行的回环服务，也可以在 App 内启动服务；应用不会自动下载大型模型。

## 安全设计

- 不允许把 `/System`、`/Library`、用户主目录或允许范围的根目录作为清理目标。
- 原生清理只接受经过白名单校验的后代路径，并拒绝符号链接。
- 文件默认移入 macOS 废纸篓，不使用不可恢复的 `rm -rf`。
- 系统级 App 的卸载可能需要管理员授权；当前版本会明确报错，不绕过权限。
- Mole 的高风险交互命令不会通过模拟键盘自动确认。
- 每个拉取请求运行核心自检、完整 App Bundle 构建和 CodeQL 静态分析。
- GitHub Actions 使用最小权限，依赖与 Action 更新由 Dependabot 检查。

完整披露范围和报告方式见 [SECURITY.md](SECURITY.md)。

## CleanNest 与 Mole

CleanNest 是独立开发的图形客户端，不是 Mole 官方 App，也不捆绑 Mole 二进制。它通过独立本地进程调用用户自行安装的 CLI，并在设置页保留来源署名。

[Mole](https://github.com/tw93/Mole) 由 tw93 与贡献者维护，采用 GPL-3.0。CleanNest 自身源码采用 [MIT License](LICENSE)。

## 开发与验证

开发期直接运行：

```bash
swift run CleanNest
```

运行核心自检：

```bash
swift run CleanNestSelfTest
```

使用不接触真实文件的演示数据检查界面：

```bash
CLEANNEST_DEMO=1 swift run CleanNest
```

项目当前版本为 **0.3.1（Build 7）**。欢迎通过 [Issues](https://github.com/n9896027/CleanNest/issues) 提交可复现的问题或功能建议；安全问题请使用私密漏洞报告渠道。
