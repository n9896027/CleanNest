# CleanNest 0.6.3 本机验证报告

日期：2026-08-26  
版本：0.6.3（Build 24）  
环境：当前 Apple Silicon Mac、macOS、本地稳定代码签名身份

## 结论

0.6.3 P1 已把 0.6.2 的 Agent 工作区“只读回收预览”升级为备份优先的手动决策链。用户默认不选中任何文件；可处理范围仍限于 Codex 与 Claude 默认目录内、已静置且未被打开的缓存、临时文件和日志。执行前会重新读取文件身份与打开状态，先在本机创建并校验 ZIP，再把原文件原子移出 Agent 目录。恢复遇到 Agent 后来新建的同名文件会拒绝覆盖。

会话、索引、记忆、凭据、运行时和未知 Agent 数据仍保持只读。本轮没有对真实 Agent 文件执行处理或恢复，处置链只在隔离临时目录中完成了端到端测试。

## 可重现证据

| 项目 | 实测结果 |
| --- | --- |
| 版本 | 最终 App Bundle 为 `0.6.3`（Build `24`）；App、登录项、XPC 与 MCP 源版本同步 |
| 单元测试 | 107 项全部通过，0 失败 |
| 恢复链测试 | 隔离夹具完成“身份复核 → ZIP 创建与 CRC/SHA-256 校验 → 原文件移除 → 恢复”；另有用例确认原路径出现新文件或 ZIP 被改动时拒绝恢复 |
| 集成自检 | `CleanNestSelfTest` 全部通过 |
| Release 构建 | CleanNest、只读 MCP、登录项与独立扫描服务全部完成 production 编译；最终增量主 App 编译阶段 21.81 秒 |
| 签名与嵌套结构 | 最终 App 和嵌套登录项、MCP、`CleanNestScanner.xpc` 通过严格及 deep 签名验证；使用本地稳定身份，不冒充 Developer ID 或 Apple 公证 |
| 启动版本 | 重建后自动启动的进程来自最终 `build/CleanNest.app`，Info.plist 实测为 0.6.3（24） |
| 主 App 内存 | 最终加固版启动 17 秒时 RSS 为 192,544 KiB（约 188.0 MiB）；此前同版约 2 分钟两次采样为 193,168 KiB 与 193,328 KiB，未出现 1.2 GB 级启动膨胀 |
| 原生工具账本 | 本机发现 Git、Docker CLI、Hugging Face CLI、npm 与 pip；Docker daemon 当前未返回账本，Hugging Face dry-run 没有未引用修订，npm 只读取缓存位置，pip 只读账本约为 582.9 MB HTTP 缓存和 21.8 MB wheel 缓存 |
| 仓库质量 | 3 个 plist 校验通过；`git diff --check` 通过 |

## 处置事务

1. 扫描器只发布有精确设备号、文件号、所有者、逻辑/分配体积和纳秒修改时间的候选。
2. GUI 操作层限制为每次最多 2,000 个文件、50 GB 逻辑体积，且恢复区必须与原文件同卷。
3. 第一次打开文件检查通过后，使用同卷硬链接建立暂存，再用系统 `ditto` 创建 ZIP，用系统 `unzip` 完成 CRC 校验，并记录流式 SHA-256。
4. 第二次打开文件与身份检查通过后，使用不覆盖目标的原子 rename 把原文件移入事务区；任一移动失败会反向回滚。
5. 只有备份已校验且所有文件已离开 Agent 目录后，才释放事务区原文件；ZIP 和 manifest 继续留在本机恢复区。
6. 恢复会复核 ZIP 的 SHA-256，拒绝符号链接替换的事务目录，也不会覆盖已存在但身份不同的文件；失败或中断记录会保留供检查。

## 原生开发工具边界

| 工具 | 0.6.3 行为 |
| --- | --- |
| Git worktree | 用户选择单个仓库；每次执行前重新运行 Git 官方 dry-run，只允许 prune 失效管理记录 |
| Hugging Face | 离线、关闭遥测地运行 `hf cache prune --dry-run`；确认后才运行 prune |
| Docker | 只读 `docker system df`；官方 `system prune` 没有等价 dry-run，因此不开放执行 |
| npm | 只读取 npm 返回的缓存位置；`cache verify` 会同时垃圾回收，`cache clean --force` 过于宽泛，因此不开放执行 |
| pip | 只读 `pip cache info`；`cache purge` 没有 dry-run，因此不开放执行 |

## 尚未证明

- 没有在本轮对用户真实的 Codex/Claude 文件执行清理、恢复或冲突实验；真实文件仍需由用户在 UI 中逐项确认。
- 没有执行 Git/Hugging Face 原生清理；本轮只验证预演和命令可用性。
- 没有 Docker daemon 在线时的真机账本证据，也没有 50 GB 上限、2,000 文件上限或磁盘写满场景的真机压力测试。
- APFS 实际回收量只会在一次真实、用户确认的处置前后测量；候选逻辑体积不冒充可释放空间。
- 本报告不等于 48 小时常驻、反复睡眠/唤醒或极限目录的耐久测试。
- 本地稳定签名不是 Developer ID；当前构建仍不是 Apple 公证的公开安装包。
- 当前只有本机测试和构建证据；在对应提交推送并由 GitHub runner 执行前，不把 CI / CodeQL 冒充为已通过。
