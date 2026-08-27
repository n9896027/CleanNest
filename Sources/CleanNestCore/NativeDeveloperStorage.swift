import Foundation

public enum NativeDeveloperStorageTool: String, CaseIterable, Codable, Identifiable, Sendable {
    case gitWorktree
    case docker
    case huggingFace
    case npm
    case pip

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gitWorktree: return "Git worktree"
        case .docker: return "Docker"
        case .huggingFace: return "Hugging Face"
        case .npm: return "npm"
        case .pip: return "pip"
        }
    }
}

public enum NativeDeveloperStorageState: String, Codable, Equatable, Sendable {
    case ready
    case needsSelection
    case unavailable
    case notInstalled

    public var displayName: String {
        switch self {
        case .ready: return "原生预览已就绪"
        case .needsSelection: return "需要选择范围"
        case .unavailable: return "暂时不可用"
        case .notInstalled: return "本机未安装"
        }
    }
}

public struct NativeDeveloperStorageEntry: Identifiable, Codable, Equatable, Sendable {
    public let tool: NativeDeveloperStorageTool
    public let state: NativeDeveloperStorageState
    public let executablePath: String?
    public let scopePath: String?
    public let summary: String
    public let detail: String
    public let preview: String?
    public let supportsNativeCleanup: Bool
    public let cleanupRisk: String

    public var id: String { tool.rawValue }

    public init(
        tool: NativeDeveloperStorageTool,
        state: NativeDeveloperStorageState,
        executablePath: String?,
        scopePath: String? = nil,
        summary: String,
        detail: String,
        preview: String? = nil,
        supportsNativeCleanup: Bool,
        cleanupRisk: String
    ) {
        self.tool = tool
        self.state = state
        self.executablePath = executablePath
        self.scopePath = scopePath
        self.summary = summary
        self.detail = detail
        self.preview = preview
        self.supportsNativeCleanup = supportsNativeCleanup
        self.cleanupRisk = cleanupRisk
    }
}

public struct NativeDeveloperStorageSnapshot: Codable, Equatable, Sendable {
    public let capturedAt: Date
    public let entries: [NativeDeveloperStorageEntry]

    public init(capturedAt: Date, entries: [NativeDeveloperStorageEntry]) {
        self.capturedAt = capturedAt
        self.entries = entries
    }
}

/// Uses each tool's documented CLI instead of guessing private cache layouts.
/// Inspection never invokes a mutating command.
public struct NativeDeveloperStorageInspector: Sendable {
    public init() {}

    public func inspect(gitRepository: URL? = nil) async -> NativeDeveloperStorageSnapshot {
        async let git = inspectGit(repository: gitRepository)
        async let docker = inspectDocker()
        async let huggingFace = inspectHuggingFace()
        async let npm = inspectNPM()
        async let pip = inspectPIP()
        return await NativeDeveloperStorageSnapshot(
            capturedAt: Date(),
            entries: [git, docker, huggingFace, npm, pip]
        )
    }

    private func inspectGit(repository: URL?) async -> NativeDeveloperStorageEntry {
        guard let executable = Self.locateExecutable(
            names: ["git"],
            additionalPaths: ["/usr/bin/git"]
        ) else {
            return missing(.gitWorktree)
        }
        guard let repository else {
            return NativeDeveloperStorageEntry(
                tool: .gitWorktree,
                state: .needsSelection,
                executablePath: executable.path,
                summary: "选择一个 Git 仓库后再预演",
                detail: "Git 的 worktree 管理信息属于具体仓库；CleanNest 不会遍历整台 Mac 猜测仓库。",
                supportsNativeCleanup: true,
                cleanupRisk: "只清理由 Git 判定为缺失且达到过期条件的 worktree 管理记录，不删除仍存在的工作树目录。"
            )
        }
        let scope = repository.standardizedFileURL
        let runner = CommandRunner()
        do {
            let rootResult = try await runner.run(
                executable: executable,
                arguments: ["-C", scope.path, "rev-parse", "--show-toplevel"],
                timeout: 6
            )
            guard rootResult.exitCode == 0 else {
                return unavailable(
                    .gitWorktree,
                    executable: executable,
                    scope: scope,
                    summary: "所选目录不是可读取的 Git 工作树",
                    result: rootResult,
                    risk: "不会在仓库身份未确认时运行 prune。"
                )
            }
            let list = try await runner.run(
                executable: executable,
                arguments: ["-C", scope.path, "worktree", "list", "--porcelain"],
                timeout: 8
            )
            let dryRun = try await runner.run(
                executable: executable,
                arguments: ["-C", scope.path, "worktree", "prune", "--dry-run", "--verbose"],
                timeout: 8
            )
            guard list.exitCode == 0, dryRun.exitCode == 0 else {
                return unavailable(
                    .gitWorktree,
                    executable: executable,
                    scope: scope,
                    summary: "Git worktree 预演失败",
                    result: dryRun.exitCode == 0 ? list : dryRun,
                    risk: "预演失败时不会开放执行。"
                )
            }
            let worktreeCount = list.standardOutput.components(separatedBy: "\nworktree ").count
            let preview = Self.boundedText(dryRun.standardOutput)
            return NativeDeveloperStorageEntry(
                tool: .gitWorktree,
                state: .ready,
                executablePath: executable.path,
                scopePath: scope.path,
                summary: "Git 报告 \(max(1, worktreeCount)) 个工作树",
                detail: preview.isEmpty ? "没有达到 prune 条件的失效管理记录。" : "Git 已列出可清理的失效管理记录。",
                preview: preview.isEmpty ? nil : preview,
                supportsNativeCleanup: true,
                cleanupRisk: "prune 只删除缺失工作树的 Git 管理信息；便携磁盘上的工作树应先用 Git lock 保护。"
            )
        } catch {
            return unavailable(
                .gitWorktree,
                executable: executable,
                scope: scope,
                summary: "Git worktree 检查没有完成",
                error: error,
                risk: "检查失败时不会开放执行。"
            )
        }
    }

    private func inspectDocker() async -> NativeDeveloperStorageEntry {
        guard let executable = Self.locateExecutable(
            names: ["docker"],
            additionalPaths: [
                "/Applications/Docker.app/Contents/Resources/bin/docker",
                "/usr/local/bin/docker",
                "/opt/homebrew/bin/docker"
            ]
        ) else {
            return missing(.docker)
        }
        let runner = CommandRunner()
        do {
            let result = try await runner.run(
                executable: executable,
                arguments: ["system", "df", "--format", "json"],
                timeout: 10
            )
            guard result.exitCode == 0 else {
                return unavailable(
                    .docker,
                    executable: executable,
                    summary: "Docker CLI 已安装，但 daemon 未返回磁盘账本",
                    result: result,
                    risk: "Docker system prune 没有 dry-run；0.6.3 只显示 df，不开放一键执行。"
                )
            }
            let preview = Self.boundedText(result.standardOutput)
            return NativeDeveloperStorageEntry(
                tool: .docker,
                state: .ready,
                executablePath: executable.path,
                summary: "Docker 磁盘账本已读取",
                detail: "来自 docker system df；没有读取镜像内容或容器日志。",
                preview: preview.isEmpty ? nil : preview,
                supportsNativeCleanup: false,
                cleanupRisk: "system prune 会删除停止的容器、未使用网络、悬空镜像和构建缓存，且官方没有 dry-run。"
            )
        } catch {
            return unavailable(
                .docker,
                executable: executable,
                summary: "Docker 磁盘账本没有完成",
                error: error,
                risk: "不在 daemon 状态未知时执行 prune。"
            )
        }
    }

    private func inspectHuggingFace() async -> NativeDeveloperStorageEntry {
        guard let executable = Self.locateExecutable(
            names: ["hf"],
            additionalPaths: [
                "/opt/homebrew/bin/hf",
                "/usr/local/bin/hf",
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/hf").path
            ]
        ) else {
            return missing(.huggingFace)
        }
        let runner = CommandRunner()
        do {
            let list = try await runner.run(
                executable: executable,
                arguments: ["cache", "ls", "--format", "json", "--limit", "20"],
                environment: Self.huggingFaceOfflineEnvironment,
                timeout: 15
            )
            let dryRun = try await runner.run(
                executable: executable,
                arguments: ["cache", "prune", "--dry-run"],
                environment: Self.huggingFaceOfflineEnvironment,
                timeout: 20
            )
            guard list.exitCode == 0, dryRun.exitCode == 0 else {
                return unavailable(
                    .huggingFace,
                    executable: executable,
                    summary: "Hugging Face 缓存预演失败",
                    result: dryRun.exitCode == 0 ? list : dryRun,
                    risk: "dry-run 失败时不会开放 prune。"
                )
            }
            let preview = Self.boundedText(dryRun.standardOutput)
            return NativeDeveloperStorageEntry(
                tool: .huggingFace,
                state: .ready,
                executablePath: executable.path,
                summary: "已检查最多 20 个缓存仓库",
                detail: preview.isEmpty ? "没有未引用修订需要清理。" : "hf cache prune dry-run 已生成删除预演。",
                preview: preview.isEmpty ? Self.boundedText(list.standardOutput) : preview,
                supportsNativeCleanup: true,
                cleanupRisk: "只使用 hf cache prune；被移除的未引用修订以后可能需要重新下载。"
            )
        } catch {
            return unavailable(
                .huggingFace,
                executable: executable,
                summary: "Hugging Face 缓存检查没有完成",
                error: error,
                risk: "检查失败时不会开放执行。"
            )
        }
    }

    private func inspectNPM() async -> NativeDeveloperStorageEntry {
        guard let executable = Self.locateExecutable(
            names: ["npm"],
            additionalPaths: ["/opt/homebrew/bin/npm", "/usr/local/bin/npm"]
        ) else {
            return missing(.npm)
        }
        let runner = CommandRunner()
        do {
            let result = try await runner.run(
                executable: executable,
                arguments: ["config", "get", "cache"],
                environment: ["NO_UPDATE_NOTIFIER": "1"],
                timeout: 8
            )
            guard result.exitCode == 0 else {
                return unavailable(
                    .npm,
                    executable: executable,
                    summary: "npm 缓存位置读取失败",
                    result: result,
                    risk: "npm cache verify 会执行垃圾回收，不冒充只读预演。"
                )
            }
            let cachePath = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            return NativeDeveloperStorageEntry(
                tool: .npm,
                state: .ready,
                executablePath: executable.path,
                scopePath: cachePath.isEmpty ? nil : cachePath,
                summary: "npm 已返回当前缓存位置",
                detail: "npm 没有内容级只读预演 API；verify 会同时垃圾回收，clean 会清空缓存。",
                preview: cachePath.isEmpty ? nil : cachePath,
                supportsNativeCleanup: false,
                cleanupRisk: "0.6.3 改用上方备份优先通道处理确定的 npm 临时文件，不直接调用 cache clean --force。"
            )
        } catch {
            return unavailable(
                .npm,
                executable: executable,
                summary: "npm 缓存检查没有完成",
                error: error,
                risk: "检查失败时不执行 cache clean。"
            )
        }
    }

    private func inspectPIP() async -> NativeDeveloperStorageEntry {
        guard let executable = Self.locateExecutable(
            names: ["python3", "python"],
            additionalPaths: ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
        ) else {
            return missing(.pip)
        }
        let runner = CommandRunner()
        do {
            let result = try await runner.run(
                executable: executable,
                arguments: ["-m", "pip", "cache", "info"],
                environment: ["PIP_DISABLE_PIP_VERSION_CHECK": "1"],
                timeout: 10
            )
            guard result.exitCode == 0 else {
                return unavailable(
                    .pip,
                    executable: executable,
                    summary: "Python 可用，但 pip cache info 不可用",
                    result: result,
                    risk: "pip cache purge 没有 dry-run；不会在预览失败时执行。"
                )
            }
            return NativeDeveloperStorageEntry(
                tool: .pip,
                state: .ready,
                executablePath: executable.path,
                summary: "pip 缓存账本已读取",
                detail: "来自 python -m pip cache info；只显示位置、数量和体积。",
                preview: Self.boundedText(result.standardOutput),
                supportsNativeCleanup: false,
                cleanupRisk: "pip cache purge 会清空 wheel 与 HTTP 缓存且没有 dry-run；0.6.3 不开放一键清空。"
            )
        } catch {
            return unavailable(
                .pip,
                executable: executable,
                summary: "pip 缓存检查没有完成",
                error: error,
                risk: "检查失败时不执行 purge。"
            )
        }
    }

    private func missing(_ tool: NativeDeveloperStorageTool) -> NativeDeveloperStorageEntry {
        NativeDeveloperStorageEntry(
            tool: tool,
            state: .notInstalled,
            executablePath: nil,
            summary: "本机没有发现 \(tool.displayName) CLI",
            detail: "CleanNest 不会为了此功能自动安装命令行工具。",
            supportsNativeCleanup: false,
            cleanupRisk: "没有可验证的原生接口时保持只读。"
        )
    }

    private func unavailable(
        _ tool: NativeDeveloperStorageTool,
        executable: URL,
        scope: URL? = nil,
        summary: String,
        result: CommandResult,
        risk: String
    ) -> NativeDeveloperStorageEntry {
        let detail = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        return NativeDeveloperStorageEntry(
            tool: tool,
            state: .unavailable,
            executablePath: executable.path,
            scopePath: scope?.path,
            summary: summary,
            detail: detail.isEmpty ? "原生命令退出状态 \(result.exitCode)。" : Self.boundedText(detail),
            supportsNativeCleanup: false,
            cleanupRisk: risk
        )
    }

    private func unavailable(
        _ tool: NativeDeveloperStorageTool,
        executable: URL,
        scope: URL? = nil,
        summary: String,
        error: Error,
        risk: String
    ) -> NativeDeveloperStorageEntry {
        NativeDeveloperStorageEntry(
            tool: tool,
            state: .unavailable,
            executablePath: executable.path,
            scopePath: scope?.path,
            summary: summary,
            detail: error.localizedDescription,
            supportsNativeCleanup: false,
            cleanupRisk: risk
        )
    }

    private static func locateExecutable(
        names: [String],
        additionalPaths: [String]
    ) -> URL? {
        let environmentDirectories = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let standardDirectories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path
        ]
        let direct = additionalPaths.map { URL(fileURLWithPath: $0).standardizedFileURL }
        let generated = (environmentDirectories + standardDirectories).flatMap { directory in
            names.map { URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent($0) }
        }
        var seen = Set<String>()
        return (direct + generated).first { candidate in
            seen.insert(candidate.path).inserted
                && FileManager.default.isExecutableFile(atPath: candidate.path)
        }
    }

    private static func boundedText(_ raw: String) -> String {
        let normalized = raw
            .replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).prefix(20)
        let value = lines.joined(separator: "\n")
        return String(value.prefix(4_000))
    }

    private static let huggingFaceOfflineEnvironment = [
        "HF_HUB_OFFLINE": "1",
        "HF_HUB_DISABLE_TELEMETRY": "1",
        "DO_NOT_TRACK": "1"
    ]
}
