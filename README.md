# CleanNest

CleanNest 是一个可自行修改的原生 macOS 清理与维护客户端。它提供鼠标可操作的 SwiftUI 界面，并把 Mole CLI 作为可选、可替换的本地引擎；没有订阅，也不上传文件清单。

## 当前能力

- 自动发现 Apple Silicon / Intel Homebrew 安装的 `mo`
- 在 App 内安装或更新 Mole CLI，不要求用户输入终端命令
- 读取 `mo status --json`，显示 CPU、内存、磁盘、电池、温度与健康状态
- 原生探测内存压力、压缩内存、交换空间及高占用进程，并提供中文解释
- 在身份复核、系统进程保护和二次确认下请求退出指定进程；不会自动升级为强制结束
- 读取 `mo analyze --json`，以原生列表展示磁盘占用
- 原生扫描开发缓存、日志和安装包，所有删除默认移入废纸篓
- 可选连接本机 `mlx_lm.server`，用 Gemma 对扫描元数据做二次解释、风险标记与清理排序
- 浏览已安装 App，并预览基于 Bundle ID 精确匹配的残留文件
- 运行低风险维护动作，集中展示结果与操作历史
- 明暗色自适应、权限引导、错误恢复与演示模式

## 构建

只需要 macOS Command Line Tools：

```bash
cd CleanNest
chmod +x build.sh
./build.sh
open build/CleanNest.app
```

开发期也可以运行：

```bash
swift run CleanNest
```

运行核心自检：

```bash
swift run CleanNestSelfTest
```

界面验收可使用产品级演示数据：

```bash
CLEANNEST_DEMO=1 swift run CleanNest
```

## 安全边界

- CleanNest 不会删除 `/System`、`/Library`、用户主目录或允许范围的根目录。
- 原生清理只接受经过白名单校验的后代路径，并拒绝符号链接。
- 删除通过 macOS 废纸篓完成；不使用 `rm -rf`。
- 系统级 App 的卸载可能仍需要管理员授权；当前版本会明确报错，不会绕过权限。
- Mole CLI 的高风险交互命令不会通过模拟键盘自动确认。
- MLX 连接只允许显式的 `http://127.0.0.1:<端口>/v1`，不会转发到局域网或公网。
- AI 请求只包含短期 token、类型、大小、时间、脱敏路径提示等元数据，不读取或上传文件内容。
- AI 返回值执行严格字段、枚举和 token 白名单校验；它只能显示建议，不能扩大扫描集合、改变勾选或绕过废纸篓规则。

## 本机 MLX（可选）

在“设置 → 本机 AI 分析”中选择已有的 MLX 模型目录和 `mlx_lm.server`。CleanNest 会优先复用已经运行的回环服务；如果服务尚未运行，也可以直接在 App 内启动，不需要终端。应用不会自动下载大型模型。

当前客户端使用 MLX-LM 的 `/v1/chat/completions` 文本接口。由于本地服务不保证 JSON Schema 约束，CleanNest 会在 Swift 端严格验证全部响应；验证失败时只隐藏 AI 建议，普通规则扫描仍然有效。

## 开源与命名

CleanNest 不捆绑 Mole 二进制，也不是 Mole 官方 App。Mole CLI 由 tw93 与贡献者维护，采用 GPL-3.0；其项目与商标说明见 <https://github.com/tw93/Mole>。CleanNest 通过独立进程调用用户自行安装的 CLI，并在设置页保留来源署名。

## 安全与贡献

每个拉取请求都会在 GitHub Actions 中运行 Swift 核心自检、完整 App Bundle 构建和 CodeQL 静态分析；依赖与 Action 更新由 Dependabot 定期检查。

发现可能导致越界删除、错误结束进程、权限绕过或本机数据外传的问题时，请不要公开披露。报告方式和支持范围见 [SECURITY.md](SECURITY.md)。
