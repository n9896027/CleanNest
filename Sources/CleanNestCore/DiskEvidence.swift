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
}

public struct DiskEvidenceReport: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let generatedAt: Date
    public let rootHint: String
    public let entries: [DiskEvidenceEntry]

    public init(
        schemaVersion: Int = Self.schemaVersion,
        generatedAt: Date = Date(),
        rootHint: String,
        entries: [DiskEvidenceEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.rootHint = rootHint
        self.entries = entries
    }
}

public struct DiskEvidenceProgress: Equatable, Sendable {
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
                entries: evidence
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
            while let child = enumerator?.nextObject() as? URL {
                if Task.isCancelled { break }
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
