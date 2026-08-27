import CryptoKit
import Foundation

public enum DiskEvidenceFileKind: String, CaseIterable, Codable, Sendable {
    case image
    case video
    case audio
    case document
    case archive
    case installer
    case sourceCode
    case database
    case log
    case other
}

public struct DiskEvidenceTypeBucket: Codable, Equatable, Sendable {
    public let kind: DiskEvidenceFileKind
    public let fileCount: Int
    public let allocatedBytes: Int64

    public init(kind: DiskEvidenceFileKind, fileCount: Int, allocatedBytes: Int64) {
        self.kind = kind
        self.fileCount = fileCount
        self.allocatedBytes = allocatedBytes
    }
}

public struct DiskEvidenceAgeDistribution: Codable, Equatable, Sendable {
    public let recentBytes: Int64
    public let monthBytes: Int64
    public let quarterBytes: Int64
    public let olderBytes: Int64
    public let unknownBytes: Int64

    public init(
        recentBytes: Int64 = 0,
        monthBytes: Int64 = 0,
        quarterBytes: Int64 = 0,
        olderBytes: Int64 = 0,
        unknownBytes: Int64 = 0
    ) {
        self.recentBytes = recentBytes
        self.monthBytes = monthBytes
        self.quarterBytes = quarterBytes
        self.olderBytes = olderBytes
        self.unknownBytes = unknownBytes
    }
}

public enum DiskCleanupDisposition: String, Codable, CaseIterable, Sendable {
    case reviewCandidate
    case inspectFurther
    case manageInOwnerApp
    case keep
}

public enum DiskDecisionConfidence: String, Codable, CaseIterable, Sendable {
    case high
    case medium
    case low
}

public struct DiskCleanupDecision: Equatable, Sendable {
    public let disposition: DiskCleanupDisposition
    public let confidence: DiskDecisionConfidence
    public let headline: String
    public let whyLarge: String
    public let impact: String
    public let recovery: String
    public let nextStep: String
    public let evidence: [String]

    public init(
        disposition: DiskCleanupDisposition,
        confidence: DiskDecisionConfidence,
        headline: String,
        whyLarge: String,
        impact: String,
        recovery: String,
        nextStep: String,
        evidence: [String]
    ) {
        self.disposition = disposition
        self.confidence = confidence
        self.headline = headline
        self.whyLarge = whyLarge
        self.impact = impact
        self.recovery = recovery
        self.nextStep = nextStep
        self.evidence = evidence
    }
}

public struct DiskEvidenceEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let relativeHint: String
    public let allocatedBytes: Int64
    public let isDirectory: Bool
    public let observedFileCount: Int
    public let observedBytes: Int64
    public let scanWasLimited: Bool
    public let latestModificationDate: Date?
    public let ageDistribution: DiskEvidenceAgeDistribution
    public let typeDistribution: [DiskEvidenceTypeBucket]
    public let category: DiskAIContentCategory
    public let cleanupBoundary: DiskAICleanupBoundary
    public let minimumRisk: DiskAIRisk
    public let purpose: String
    public let likelyOwner: String?
    public let provenance: String
    public let regeneration: String
    public let growthBytes: Int64?

    public init(
        id: String,
        name: String,
        relativeHint: String,
        allocatedBytes: Int64,
        isDirectory: Bool,
        observedFileCount: Int,
        observedBytes: Int64,
        scanWasLimited: Bool,
        latestModificationDate: Date?,
        ageDistribution: DiskEvidenceAgeDistribution,
        typeDistribution: [DiskEvidenceTypeBucket],
        category: DiskAIContentCategory,
        cleanupBoundary: DiskAICleanupBoundary,
        minimumRisk: DiskAIRisk,
        purpose: String,
        likelyOwner: String?,
        provenance: String,
        regeneration: String,
        growthBytes: Int64?
    ) {
        self.id = id
        self.name = name
        self.relativeHint = relativeHint
        self.allocatedBytes = allocatedBytes
        self.isDirectory = isDirectory
        self.observedFileCount = observedFileCount
        self.observedBytes = observedBytes
        self.scanWasLimited = scanWasLimited
        self.latestModificationDate = latestModificationDate
        self.ageDistribution = ageDistribution
        self.typeDistribution = typeDistribution
        self.category = category
        self.cleanupBoundary = cleanupBoundary
        self.minimumRisk = minimumRisk
        self.purpose = purpose
        self.likelyOwner = likelyOwner
        self.provenance = provenance
        self.regeneration = regeneration
        self.growthBytes = growthBytes
    }

    public var cleanupDecision: DiskCleanupDecision {
        DiskCleanupDecisionEngine.decision(for: self)
    }
}

public enum DiskCleanupDecisionEngine {
    public static func decision(for entry: DiskEvidenceEntry) -> DiskCleanupDecision {
        let disposition = disposition(for: entry)
        let confidence = confidence(for: entry)
        let actionText: (headline: String, impact: String, nextStep: String)

        switch disposition {
        case .reviewCandidate:
            actionText = (
                "可作为逐项复核候选",
                impact(for: entry),
                "先进入下一层或在 Finder 中核对具体项目；确认后只通过 CleanNest 的安全清理范围移到废纸篓。"
            )
        case .inspectFurther:
            actionText = (
                "当前层不能整体处理",
                "这个目录可能混有可重建内容与仍在使用的数据，整体处理会放大误伤范围。",
                "继续进入下一层，直到用途和所属应用足够明确；当前目录保持只读。"
            )
        case .manageInOwnerApp:
            actionText = (
                "应在所属 App 内管理",
                "直接处理可能让应用丢失登录状态、数据库、模型、离线内容或同步状态。",
                entry.likelyOwner.map { "优先打开 \($0) 的存储、下载或缓存设置。" }
                    ?? "优先在所属 App 的存储、下载或缓存设置中管理。"
            )
        case .keep:
            actionText = (
                "建议保留",
                "现有元数据不足以证明它可重建，或本机规则已确认其中可能包含用户/系统关键数据。",
                "保持不动；如需继续调查，只做下钻查看或在 Finder 中确认来源。"
            )
        }

        return DiskCleanupDecision(
            disposition: disposition,
            confidence: confidence,
            headline: actionText.headline,
            whyLarge: whyLarge(for: entry),
            impact: actionText.impact,
            recovery: entry.regeneration,
            nextStep: actionText.nextStep,
            evidence: evidenceSignals(for: entry)
        )
    }

    private static func disposition(for entry: DiskEvidenceEntry) -> DiskCleanupDisposition {
        if entry.cleanupBoundary == .protected || entry.minimumRisk == .high {
            return .keep
        }
        switch entry.category {
        case .userContent, .cloudDocuments, .systemData, .unknown:
            return .keep
        case .appSandboxData, .appSupportData:
            return .manageInOwnerApp
        case .cache, .logs, .developerArtifacts, .installerOrArchive:
            return entry.cleanupBoundary == .reviewable ? .reviewCandidate : .inspectFurther
        case .packageManagerData:
            return entry.cleanupBoundary == .reviewable ? .reviewCandidate : .inspectFurther
        }
    }

    private static func confidence(for entry: DiskEvidenceEntry) -> DiskDecisionConfidence {
        if entry.category == .unknown || entry.observedFileCount == 0 { return .low }
        if entry.scanWasLimited || entry.likelyOwner == nil { return .medium }
        return .high
    }

    private static func whyLarge(for entry: DiskEvidenceEntry) -> String {
        switch entry.category {
        case .cache:
            return "应用运行、预览、安装或下载后会保留可重建副本；长期不清理时，不同版本和重复下载会持续累积。"
        case .logs:
            return "应用持续写入运行与诊断记录；异常重试、长时间运行或保留策略过宽时会逐渐增长。"
        case .developerArtifacts:
            return "编译产物、索引、模拟器数据或依赖构建会按项目和架构重复生成，多个版本可并存。"
        case .packageManagerData:
            return "安装或更新依赖时下载的包、仓库元数据、内容寻址缓存与工具运行时会保留，以便后续复用。"
        case .installerOrArchive:
            return "安装包、磁盘映像和归档通常是一次下载形成的大文件，使用后不会自动消失。"
        case .appSandboxData:
            return "应用把数据库、离线内容、缓存与用户状态集中保存在沙盒中；持续使用会共同增长。"
        case .appSupportData:
            return "应用模型、资源、数据库、插件和缓存可能存放在同一支持目录，不能仅凭总大小拆分用途。"
        case .cloudDocuments:
            return "同步服务可能保留本地下载副本、版本与待上传内容；占用与云端可见大小不一定相同。"
        case .userContent:
            return "这里主要由用户保存或应用导出的内容构成；元数据不能可靠判断哪些仍有价值。"
        case .systemData:
            return "系统与多个应用共同维护索引、数据库或共享资源；大小会随系统和应用活动变化。"
        case .unknown:
            return "当前目录身份与内容类型证据不足，无法可靠说明增长来源。"
        }
    }

    private static func impact(for entry: DiskEvidenceEntry) -> String {
        switch entry.category {
        case .cache:
            return "不会卸载现有 App 或工具，但下一次启动、安装或访问相同内容时可能重新计算或下载。"
        case .logs:
            return "新日志仍会生成；旧记录在排查历史故障时可能无法替代。"
        case .developerArtifacts:
            return "源代码通常不受影响，但下一次构建、索引或启动模拟器会更慢。"
        case .packageManagerData:
            return "缓存可重新下载；若其中混有全局工具、运行时或已安装依赖，处理整个目录会破坏开发环境。"
        case .installerOrArchive:
            return "已安装应用通常不受影响，但会失去离线重装或归档副本。"
        default:
            return "当前类别不适合从磁盘浏览页直接处理，应继续确认所属应用和具体子项。"
        }
    }

    private static func evidenceSignals(for entry: DiskEvidenceEntry) -> [String] {
        var signals = [
            "本机目录规则：\(entry.category.rawValue)",
            "动作边界：\(entry.cleanupBoundary.rawValue)；最低风险：\(entry.minimumRisk.rawValue)",
            "观察到 \(entry.observedFileCount) 个文件，共 \(entry.observedBytes) 字节"
        ]
        if let owner = entry.likelyOwner { signals.append("可能所属：\(owner)") }
        if let topType = entry.typeDistribution.first {
            signals.append("主要文件类型：\(topType.kind.rawValue)，\(topType.fileCount) 个")
        }
        if let growth = entry.growthBytes, growth != 0 {
            signals.append(growth > 0 ? "较上次增加 \(growth) 字节" : "较上次减少 \(abs(growth)) 字节")
        }
        if entry.scanWasLimited {
            signals.append("抽样达到安全上限，结论不代表目录内全部文件")
        }
        return signals
    }
}

public struct DiskEvidenceReport: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let generatedAt: Date
    public let rootHint: String
    public let entries: [DiskEvidenceEntry]
    public let comparisonGeneratedAt: Date?

    public init(
        schemaVersion: Int = Self.schemaVersion,
        generatedAt: Date = Date(),
        rootHint: String,
        entries: [DiskEvidenceEntry],
        comparisonGeneratedAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.rootHint = rootHint
        self.entries = entries
        self.comparisonGeneratedAt = comparisonGeneratedAt
    }
}

public struct DiskEvidenceProgress: Codable, Equatable, Sendable {
    public let completed: Int
    public let total: Int
    public let currentName: String

    public init(completed: Int, total: Int, currentName: String) {
        self.completed = completed
        self.total = total
        self.currentName = currentName
    }

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(completed) / Double(total)))
    }
}

public struct DiskEvidenceOptions: Equatable, Sendable {
    public let maximumTopLevelEntries: Int
    public let maximumFilesPerEntry: Int

    public init(maximumTopLevelEntries: Int = 16, maximumFilesPerEntry: Int = 8_000) {
        self.maximumTopLevelEntries = min(max(maximumTopLevelEntries, 1), 64)
        self.maximumFilesPerEntry = min(max(maximumFilesPerEntry, 100), 100_000)
    }
}

public struct DiskEvidenceIndexer: Sendable {
    public let options: DiskEvidenceOptions

    public init(options: DiskEvidenceOptions = DiskEvidenceOptions()) {
        self.options = options
    }

    public func build(
        report: DiskReport,
        previous: DiskEvidenceReport? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        progress: (@Sendable (DiskEvidenceProgress) -> Void)? = nil
    ) async throws -> DiskEvidenceReport {
        let options = self.options
        let worker = Task.detached(priority: .utility) {
            let entries = Array(
                report.entries
                    .filter { $0.bytes >= 0 }
                    .sorted {
                        if $0.bytes == $1.bytes { return $0.name < $1.name }
                        return $0.bytes > $1.bytes
                    }
                    .prefix(options.maximumTopLevelEntries)
            )
            let previousByID = Dictionary(uniqueKeysWithValues: (previous?.entries ?? []).map { ($0.id, $0) })
            var evidence: [DiskEvidenceEntry] = []
            evidence.reserveCapacity(entries.count)

            for (index, entry) in entries.enumerated() {
                try Task.checkCancellation()
                progress?(
                    DiskEvidenceProgress(
                        completed: index,
                        total: entries.count,
                        currentName: Self.sanitize(entry.name, maximumLength: 120)
                    )
                )
                let fingerprint = Self.fingerprint(for: entry.url)
                let current = Self.inspect(
                    entry,
                    fingerprint: fingerprint,
                    previousBytes: previousByID[fingerprint]?.allocatedBytes,
                    root: report.root,
                    homeDirectory: homeDirectory,
                    maximumFiles: options.maximumFilesPerEntry
                )
                evidence.append(current)
            }
            progress?(
                DiskEvidenceProgress(
                    completed: entries.count,
                    total: entries.count,
                    currentName: ""
                )
            )
            return DiskEvidenceReport(
                rootHint: Self.redactedHint(for: report.root, relativeTo: report.root, homeDirectory: homeDirectory),
                entries: evidence,
                comparisonGeneratedAt: previous?.generatedAt
            )
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    public static func fingerprint(for url: URL) -> String {
        let normalized = url.standardizedFileURL.resolvingSymlinksInPath().path
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private struct MutableAge {
        var recent: Int64 = 0
        var month: Int64 = 0
        var quarter: Int64 = 0
        var older: Int64 = 0
        var unknown: Int64 = 0

        mutating func add(bytes: Int64, modifiedAt: Date?, now: Date) {
            guard let modifiedAt else {
                unknown += bytes
                return
            }
            let age = max(0, now.timeIntervalSince(modifiedAt))
            if age <= 7 * 86_400 {
                recent += bytes
            } else if age <= 30 * 86_400 {
                month += bytes
            } else if age <= 90 * 86_400 {
                quarter += bytes
            } else {
                older += bytes
            }
        }

        var value: DiskEvidenceAgeDistribution {
            DiskEvidenceAgeDistribution(
                recentBytes: recent,
                monthBytes: month,
                quarterBytes: quarter,
                olderBytes: older,
                unknownBytes: unknown
            )
        }
    }

    private struct MutableTypeBucket {
        var files = 0
        var bytes: Int64 = 0
    }

    private static func inspect(
        _ entry: DiskEntry,
        fingerprint: String,
        previousBytes: Int64?,
        root: URL,
        homeDirectory: URL,
        maximumFiles: Int
    ) -> DiskEvidenceEntry {
        let policy = DiskAISafetyPolicy.policy(for: entry.url, homeDirectory: homeDirectory)
        let now = Date()
        var observedFiles = 0
        var observedBytes: Int64 = 0
        var latestModificationDate: Date?
        var age = MutableAge()
        var types: [DiskEvidenceFileKind: MutableTypeBucket] = [:]
        var scanWasLimited = false

        func consume(_ url: URL, values: URLResourceValues) {
            guard values.isRegularFile == true else { return }
            let bytes = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            observedFiles += 1
            observedBytes += max(0, bytes)
            let modified = values.contentModificationDate
            age.add(bytes: max(0, bytes), modifiedAt: modified, now: now)
            if let modified {
                latestModificationDate = latestModificationDate.map { max($0, modified) } ?? modified
            }
            let kind = fileKind(for: url)
            var bucket = types[kind] ?? MutableTypeBucket()
            bucket.files += 1
            bucket.bytes += max(0, bytes)
            types[kind] = bucket
        }

        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey
        ]
        if entry.isDirectory {
            let enumerator = FileManager.default.enumerator(
                at: entry.url,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsPackageDescendants],
                errorHandler: { _, _ in true }
            )
            let batchSize = 256
            var exhausted = enumerator == nil
            while !exhausted, !scanWasLimited, !Task.isCancelled {
                autoreleasepool {
                    for _ in 0..<batchSize {
                        guard !Task.isCancelled,
                              let child = enumerator?.nextObject() as? URL else {
                            exhausted = true
                            break
                        }
                        guard let values = try? child.resourceValues(forKeys: keys) else { continue }
                        if values.isSymbolicLink == true {
                            enumerator?.skipDescendants()
                            continue
                        }
                        consume(child, values: values)
                        if observedFiles >= maximumFiles {
                            scanWasLimited = true
                            break
                        }
                    }
                }
            }
        } else if let values = try? entry.url.resourceValues(forKeys: keys) {
            consume(entry.url, values: values)
        }

        let descriptions = semanticDescription(for: entry.url, policy: policy)
        let distribution = types.map {
            DiskEvidenceTypeBucket(kind: $0.key, fileCount: $0.value.files, allocatedBytes: $0.value.bytes)
        }.sorted {
            if $0.allocatedBytes == $1.allocatedBytes { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.allocatedBytes > $1.allocatedBytes
        }
        return DiskEvidenceEntry(
            id: fingerprint,
            name: sanitize(entry.name, maximumLength: 160),
            relativeHint: redactedHint(for: entry.url, relativeTo: root, homeDirectory: homeDirectory),
            allocatedBytes: max(0, entry.bytes),
            isDirectory: entry.isDirectory,
            observedFileCount: observedFiles,
            observedBytes: observedBytes,
            scanWasLimited: scanWasLimited,
            latestModificationDate: latestModificationDate,
            ageDistribution: age.value,
            typeDistribution: distribution,
            category: policy.category,
            cleanupBoundary: policy.boundary,
            minimumRisk: policy.minimumRisk,
            purpose: descriptions.purpose,
            likelyOwner: descriptions.owner,
            provenance: descriptions.provenance,
            regeneration: descriptions.regeneration,
            growthBytes: previousBytes.map { max(0, entry.bytes) - max(0, $0) }
        )
    }

    private static func semanticDescription(
        for url: URL,
        policy: DiskAIInputPolicy
    ) -> (purpose: String, owner: String?, provenance: String, regeneration: String) {
        let components = url.standardizedFileURL.pathComponents
        let owner = likelyOwner(from: components)
        switch policy.category {
        case .cache:
            return (
                "应用或工具为了加快后续访问而保留的可重建数据。",
                owner,
                owner.map { "通常由 \($0) 在使用或下载过程中产生。" } ?? "通常由对应应用或开发工具在运行时产生。",
                "移除后通常会重新生成或重新下载，代价是下一次启动或安装更慢。"
            )
        case .logs:
            return (
                "应用和系统记录的运行、诊断或错误日志。",
                owner,
                owner.map { "通常由 \($0) 的运行或诊断过程产生。" } ?? "通常由应用或系统诊断过程产生。",
                "新日志会继续生成，但旧日志在排查问题时可能不可替代。"
            )
        case .developerArtifacts:
            return (
                "编译、索引、模拟器或开发工具生成的中间产物。",
                owner,
                "来自本机开发工作流，不是已安装应用本体。",
                "通常可由源代码和工具重新生成，但会增加下一次构建耗时。"
            )
        case .packageManagerData:
            return (
                "包管理器保存的下载缓存、仓库或已安装依赖数据。",
                owner,
                "由 Homebrew、npm、pnpm、pip 等包管理器下载或生成。",
                "缓存通常可重新下载；已安装依赖或全局工具不能仅凭目录名称整体移除。"
            )
        case .installerOrArchive:
            return (
                "安装包、磁盘映像或压缩归档。",
                owner,
                "通常来自浏览器、包管理器或手动下载。",
                "只有确认来源仍可获取且不再需要离线安装时，才适合作为候选。"
            )
        case .appSandboxData:
            return (
                "应用沙盒中的设置、数据库、缓存和用户数据混合内容。",
                owner,
                owner.map { "由沙盒应用 \($0) 管理。" } ?? "由对应沙盒应用管理。",
                "其中部分数据不可重建，应在所属 App 内管理，不能整体清理。"
            )
        case .appSupportData:
            return (
                "应用运行所需的支持文件，可能同时包含数据库、模型、资源与缓存。",
                owner,
                owner.map { "通常由 \($0) 安装或运行时创建。" } ?? "通常由对应应用安装或运行时创建。",
                "是否可重建取决于所属应用；当前目录只供继续检查。"
            )
        case .cloudDocuments:
            return (
                "云盘或应用同步的文档与离线副本。",
                owner,
                "由云端同步服务和对应应用共同管理。",
                "本地删除可能同步到其他设备，必须在所属服务中确认。"
            )
        case .userContent:
            return (
                "用户创建、下载或保存的个人内容。",
                owner,
                "来源无法仅靠元数据可靠判断。",
                "通常不可自动重建，应逐项确认并优先保留。"
            )
        case .systemData:
            return (
                "macOS 或多个应用共同使用的系统级数据。",
                owner,
                "由系统服务或多个组件管理。",
                "不能仅凭体积判断为可清理，应保持只读。"
            )
        case .unknown:
            return (
                "当前规则无法可靠确认用途。",
                owner,
                "缺少稳定的目录来源证据。",
                "未知内容默认保留，并建议继续进入查看。"
            )
        }
    }

    private static func likelyOwner(from components: [String]) -> String? {
        let markers = ["Containers", "Group Containers", "Application Support", "Caches", "Logs"]
        for marker in markers {
            guard let index = components.lastIndex(of: marker), components.indices.contains(index + 1) else { continue }
            let value = sanitize(components[index + 1], maximumLength: 120)
            if !value.isEmpty { return value }
        }
        return nil
    }

    private static func fileKind(for url: URL) -> DiskEvidenceFileKind {
        let ext = url.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "gif", "heic", "tif", "tiff", "webp", "svg"].contains(ext) { return .image }
        if ["mov", "mp4", "m4v", "mkv", "avi", "webm"].contains(ext) { return .video }
        if ["mp3", "m4a", "wav", "aac", "flac", "ogg"].contains(ext) { return .audio }
        if ["pdf", "doc", "docx", "pages", "txt", "rtf", "md", "xls", "xlsx", "numbers", "ppt", "pptx", "key"].contains(ext) { return .document }
        if ["zip", "tar", "gz", "tgz", "7z", "rar", "xz", "bz2"].contains(ext) { return .archive }
        if ["dmg", "pkg", "iso"].contains(ext) { return .installer }
        if ["swift", "m", "mm", "h", "c", "cc", "cpp", "rs", "go", "py", "js", "ts", "tsx", "jsx", "java", "kt", "sh", "zsh", "json", "yaml", "yml", "toml"].contains(ext) { return .sourceCode }
        if ["db", "sqlite", "sqlite3", "realm"].contains(ext) { return .database }
        if ["log", "trace", "crash"].contains(ext) { return .log }
        return .other
    }

    private static func redactedHint(
        for url: URL,
        relativeTo root: URL,
        homeDirectory: URL
    ) -> String {
        let path = url.standardizedFileURL.path
        let home = homeDirectory.standardizedFileURL.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + String(path.dropFirst(home.count)) }

        let rootPath = root.standardizedFileURL.path
        if path == rootPath { return sanitize(root.lastPathComponent.isEmpty ? "/" : root.lastPathComponent, maximumLength: 220) }
        if path.hasPrefix(rootPath + "/") {
            let relative = String(path.dropFirst(rootPath.count + 1))
            let prefix = root.lastPathComponent.isEmpty ? "" : root.lastPathComponent + "/"
            return sanitize(prefix + relative, maximumLength: 220)
        }
        return sanitize(url.lastPathComponent, maximumLength: 220)
    }

    private static func sanitize(_ value: String, maximumLength: Int) -> String {
        let clean = value.unicodeScalars.map { scalar -> String in
            CharacterSet.controlCharacters.contains(scalar) ? " " : String(scalar)
        }.joined()
        let trimmed = clean.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return String(trimmed.prefix(maximumLength))
    }
}

public enum DiskEvidencePersistence {
    public static func load(from url: URL) throws -> DiskEvidenceReport? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let report = try JSONDecoder().decode(DiskEvidenceReport.self, from: data)
        guard report.schemaVersion == DiskEvidenceReport.schemaVersion else { return nil }
        return report
    }

    public static func save(_ report: DiskEvidenceReport, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(report)
        try data.write(to: url, options: .atomic)
    }
}

public struct DiskEvidenceHistorySnapshot: Codable, Equatable, Sendable {
    public let evidence: DiskEvidenceReport
    public let coverage: DiskScanCoverage
    public let classifiedBytes: Int64

    public init(
        evidence: DiskEvidenceReport,
        coverage: DiskScanCoverage,
        classifiedBytes: Int64
    ) {
        self.evidence = evidence
        self.coverage = coverage
        self.classifiedBytes = max(0, classifiedBytes)
    }

    public var generatedAt: Date { evidence.generatedAt }
    public var isReliableForGrowth: Bool { !coverage.hasKnownLimitOrReadGap }
}

public struct DiskEvidenceHistoryRoot: Codable, Equatable, Sendable {
    public let id: String
    public let snapshots: [DiskEvidenceHistorySnapshot]

    public init(id: String, snapshots: [DiskEvidenceHistorySnapshot]) {
        self.id = id
        self.snapshots = Array(snapshots.sorted { $0.generatedAt < $1.generatedAt }.suffix(2))
    }
}

/// Keeps exactly the last two completed, bounded aggregate reports per root.
/// Root identities are SHA-256 fingerprints; no absolute path is persisted.
public struct DiskEvidenceHistoryStore: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let maximumRoots = 12

    public var schemaVersion: Int
    public private(set) var roots: [String: DiskEvidenceHistoryRoot]

    public init(
        schemaVersion: Int = Self.schemaVersion,
        roots: [String: DiskEvidenceHistoryRoot] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.roots = roots
    }

    public func latestReliable(for root: URL) -> DiskEvidenceHistorySnapshot? {
        roots[DiskEvidenceIndexer.fingerprint(for: root)]?.snapshots.reversed()
            .first(where: \.isReliableForGrowth)
    }

    public func snapshots(for root: URL) -> [DiskEvidenceHistorySnapshot] {
        roots[DiskEvidenceIndexer.fingerprint(for: root)]?.snapshots ?? []
    }

    public mutating func append(_ snapshot: DiskEvidenceHistorySnapshot, for root: URL) {
        let id = DiskEvidenceIndexer.fingerprint(for: root)
        var values = roots[id]?.snapshots ?? []
        values.removeAll { $0.generatedAt == snapshot.generatedAt }
        values.append(snapshot)
        roots[id] = DiskEvidenceHistoryRoot(id: id, snapshots: values)

        guard roots.count > Self.maximumRoots else { return }
        let retained = roots.values.sorted {
            ($0.snapshots.last?.generatedAt ?? .distantPast)
                > ($1.snapshots.last?.generatedAt ?? .distantPast)
        }.prefix(Self.maximumRoots)
        roots = Dictionary(uniqueKeysWithValues: retained.map { ($0.id, $0) })
    }
}

public enum DiskEvidenceHistoryPersistence {
    public static func load(from url: URL) throws -> DiskEvidenceHistoryStore {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return DiskEvidenceHistoryStore()
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let store = try JSONDecoder().decode(DiskEvidenceHistoryStore.self, from: data)
        guard store.schemaVersion == DiskEvidenceHistoryStore.schemaVersion else {
            return DiskEvidenceHistoryStore()
        }
        return store
    }

    public static func save(_ store: DiskEvidenceHistoryStore, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(store).write(to: url, options: .atomic)
    }
}
