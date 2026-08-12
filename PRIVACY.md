# 隐私说明

最后更新：2026-08-03。

CleanNest 是本机 macOS 工具。当前开源版本没有账号系统、广告、遥测、崩溃上报或项目自建云服务。

## 读取什么

只有在对应功能需要时，CleanNest 才读取：

- 文件或目录的名称、路径、类型、大小和修改时间等元数据；
- 已安装 App 的 Bundle 信息及精确匹配的相关目录；
- CPU、内存、交换空间、磁盘、电池、温度和进程等系统状态；
- 用户明确选择的 Mole 可执行文件、MLX 服务程序与模型目录。

磁盘 AI 和清理 AI 不读取文件正文。完全磁盘访问会扩大 macOS 允许本 App 读取的范围，但不会改变 CleanNest 的扫描规则或自动产生删除动作。

## 保存在哪里

- 设置项由 macOS `UserDefaults` 保存，包括开发者模式、本机 AI 开关、回环服务地址以及用户选择的本地路径。
- 最近最多 100 条操作结果保存于用户 `Application Support/CleanNest/activity.json`。
- 模型、Mole 与扫描结果不会上传到 CleanNest 服务器；项目不存在这样的服务器。

卸载 App 不一定自动移除上述偏好和活动记录。可在 Finder 的“前往文件夹”中打开 `~/Library/Application Support/CleanNest` 后删除活动记录；偏好由 macOS 管理，通常位于用户 Library 的 Preferences 范围。

## 网络访问

- 本机 AI 客户端只接受 `http://127.0.0.1:<端口>/v1`，使用临时会话，不保存 Cookie/凭据、不使用代理并拒绝 HTTP 重定向。
- 点击 Mole 项目链接会由浏览器打开 GitHub。
- 在 App 内选择 Homebrew 安装或更新 Mole 时，Homebrew 会访问自己的软件源；其网络与隐私行为由 Homebrew 和 Mole 项目负责。
- CleanNest 不会自动下载 MLX 模型。你自行使用的模型仓库、Python 包管理器或本机服务有各自的条款。

## 删除与进程操作

- 原生文件处理默认移入 macOS 废纸篓，是否清空由用户决定。
- AI 结果不能勾选项目、执行命令、关闭进程或删除文件。
- 关闭进程前会显示确认，并复核进程身份；系统与关键进程受保护。

如发现实现与本文不一致，请按 [SECURITY.md](SECURITY.md) 私密报告可能的数据泄露，普通文案或界面问题可提交 Issue。
