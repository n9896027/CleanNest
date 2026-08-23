# 第三方项目说明

CleanNest 的 Swift Package 当前没有捆绑第三方 Swift 依赖，也不在仓库中分发 Mole、MLX 模型或 Python 环境。历史指标链接 macOS 提供的系统 SQLite 3 动态库；哈希使用系统 CryptoKit。

以下项目是可选的外部集成，由用户独立安装和运行：

| 项目 | 用途 | 许可证/条款 | 是否随 CleanNest 分发 |
| --- | --- | --- | --- |
| [Mole](https://github.com/tw93/Mole) | 扫描和系统维护 CLI | [GPL-3.0](https://github.com/tw93/Mole/blob/main/LICENSE) | 否 |
| [mlx-lm](https://github.com/ml-explore/mlx-lm) | Apple Silicon 本机模型服务 | [MIT](https://github.com/ml-explore/mlx-lm/blob/main/LICENSE) | 否 |
| 用户选择的 MLX 模型 | 可选本机语言模型 | 各模型发布页注明的许可证与使用条款 | 否 |

CleanNest 与上述项目的作者或维护者没有官方隶属关系。使用外部项目时请单独检查其版本、许可证、安全更新和模型条款。
