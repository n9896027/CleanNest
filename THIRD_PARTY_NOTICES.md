# 第三方项目说明

CleanNest 的 Swift Package 当前没有捆绑第三方 Swift 依赖，也不在仓库中分发 Mole、MLX 模型或 Python 环境。历史指标链接 macOS 提供的系统 SQLite 3 动态库；哈希使用系统 CryptoKit。

以下项目是可选的外部集成，由用户独立安装和运行：

| 项目 | 用途 | 许可证/条款 | 是否随 CleanNest 分发 |
| --- | --- | --- | --- |
| [Mole](https://github.com/tw93/Mole) | 扫描和系统维护 CLI | [GPL-3.0](https://github.com/tw93/Mole/blob/main/LICENSE) | 否 |
| [mlx-lm](https://github.com/ml-explore/mlx-lm) | Apple Silicon 本机模型服务 | [MIT](https://github.com/ml-explore/mlx-lm/blob/main/LICENSE) | 否 |
| [Stats](https://github.com/exelban/stats) | 只读 AppleSMC 结构与数值解码的参考实现 | [MIT](https://github.com/exelban/stats/blob/master/LICENSE) | 仅适配后的少量源码 |
| 用户选择的 MLX 模型 | 可选本机语言模型 | 各模型发布页注明的许可证与使用条款 | 否 |

CleanNest 与上述项目的作者或维护者没有官方隶属关系。使用外部项目时请单独检查其版本、许可证、安全更新和模型条款。

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
