# 第三方项目说明

CleanNest 的 Swift Package 当前没有捆绑第三方 Swift 依赖，也不在仓库中分发 MLX 模型或 Python 环境。清理和系统状态使用内置原生引擎；历史指标链接 macOS 提供的系统 SQLite 3 动态库，哈希使用系统 CryptoKit。

以下项目是可选的外部集成或参考，由用户独立安装和运行：

| 项目 | 用途 | 许可证/条款 | 是否随 CleanNest 分发 |
| --- | --- | --- | --- |
| [mlx-lm](https://github.com/ml-explore/mlx-lm) | Apple Silicon 本机模型服务 | [MIT](https://github.com/ml-explore/mlx-lm/blob/main/LICENSE) | 否 |
| [Stats](https://github.com/exelban/stats) | 只读 AppleSMC 结构与数值解码的参考实现 | [MIT](https://github.com/exelban/stats/blob/master/LICENSE) | 仅适配后的少量源码 |
| 用户选择的 MLX 模型 | 可选本机语言模型 | 各模型发布页注明的许可证与使用条款 | 否 |

CleanNest 与上述项目的作者或维护者没有官方隶属关系。使用外部项目时请单独检查其版本、许可证、安全更新和模型条款。

## macos-sysdata 产品能力参考（不含代码）

0.9.0 调研了 [macos-sysdata](https://github.com/Jarvis322/macos-sysdata) 的公开功能说明。
截至 2026-09-07，其 [现行许可证](https://github.com/Jarvis322/macos-sysdata/blob/main/LICENSE)
明确限制把源码整合到其他产品；v0.3.7 及以前的 MIT 许可不适用于其后版本。
CleanNest 本次未复制该项目任何源码、素材或图标，也未链接或分发其二进制；
系统数据清单使用本项目既有的 FileTree / XPC 设施独立实现。双方没有官方隶属关系。

目录含义同时参考工具自己的公开说明，例如
[Docker Desktop 虚拟磁盘](https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/)
和 [Ollama 模型存储](https://docs.ollama.com/faq)。

## Stats MIT License

Copyright (c) 2019 Serhiy Mytrovtsiy

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
