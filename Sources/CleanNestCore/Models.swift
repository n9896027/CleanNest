import Foundation

public struct EngineInstallation: Equatable, Sendable {
    public let executable: URL
    public let version: String?

    public init(executable: URL, version: String? = nil) {
        self.executable = executable
        self.version = version
    }
}

public struct CommandResult: Equatable, Sendable {
    public let executable: URL
    public let arguments: [String]
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String
    public let duration: TimeInterval

    public init(
        executable: URL,
        arguments: [String],
        exitCode: Int32,
        standardOutput: String,
        standardError: String,
        duration: TimeInterval
    ) {
        self.executable = executable
        self.arguments = arguments
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.duration = duration
    }
}

public enum CleanupKind: String, CaseIterable, Codable, Sendable {
    case developer = "开发缓存"
    case packageManager = "包管理器缓存"
    case logs = "旧日志"
    case installer = "安装包"
    case appCache = "应用缓存"
    case leftover = "应用残留"

    public var symbolName: String {
        switch self {
        case .developer: return "hammer"
        case .packageManager: return "shippingbox"
        case .logs: return "doc.text"
        case .installer: return "externaldrive.badge.xmark"
        case .appCache: return "square.stack.3d.up"
        case .leftover: return "app.badge"
        }
    }
}

public struct CleanupCandidate: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let url: URL
    public let kind: CleanupKind
    public let allocatedBytes: Int64
    public let modifiedAt: Date?
    public let isRecommended: Bool
    public let detail: String

    public init(
        id: String? = nil,
        name: String,
        url: URL,
        kind: CleanupKind,
        allocatedBytes: Int64,
        modifiedAt: Date?,
        isRecommended: Bool,
        detail: String
    ) {
        self.id = id ?? url.standardizedFileURL.path
        self.name = name
        self.url = url
        self.kind = kind
        self.allocatedBytes = allocatedBytes
        self.modifiedAt = modifiedAt
        self.isRecommended = isRecommended
        self.detail = detail
    }
}

public struct InstalledApplication: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let bundleIdentifier: String?
    public let version: String?
    public let url: URL
    public let allocatedBytes: Int64
    public let modifiedAt: Date?
    public let fileIdentity: ApplicationFileIdentity?

    public init(
        name: String,
        bundleIdentifier: String?,
        version: String?,
        url: URL,
        allocatedBytes: Int64,
        modifiedAt: Date?,
        fileIdentity: ApplicationFileIdentity? = nil
    ) {
        self.id = url.standardizedFileURL.path
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.url = url
        self.allocatedBytes = allocatedBytes
        self.modifiedAt = modifiedAt
        self.fileIdentity = fileIdentity
    }
}

public struct DiskEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let url: URL
    public let bytes: Int64
    public let isDirectory: Bool

    public init(name: String, url: URL, bytes: Int64, isDirectory: Bool) {
        self.id = url.standardizedFileURL.path
        self.name = name
        self.url = url
        self.bytes = bytes
        self.isDirectory = isDirectory
    }
}

public struct DiskReport: Equatable, Sendable {
    public let root: URL
    public let entries: [DiskEntry]
    public let largeFiles: [DiskEntry]
    public let totalBytes: Int64
    public let totalFiles: Int

    public init(root: URL, entries: [DiskEntry], largeFiles: [DiskEntry], totalBytes: Int64, totalFiles: Int) {
        self.root = root
        self.entries = entries
        self.largeFiles = largeFiles
        self.totalBytes = totalBytes
        self.totalFiles = totalFiles
    }
}

public struct SystemSnapshot: Equatable, Sendable {
    public let host: String
    public let healthScore: Int?
    public let cpuUsage: Double?
    public let logicalCPUCount: Int?
    public let memoryUsedBytes: Int64?
    public let memoryTotalBytes: Int64?
    public let memoryUsedPercent: Double?
    public let memoryAvailableBytes: Int64?
    public let memoryCachedBytes: Int64?
    public let memoryCompressedBytes: Int64?
    public let memorySwapUsedBytes: Int64?
    public let memorySwapTotalBytes: Int64?
    public let memoryPressureLevel: MemoryPressureLevel
    public let processCount: Int?
    public let diskUsedPercent: Double?
    public let diskFreeBytes: Int64?
    public let batteryLevel: Double?
    public let batteryStatus: String?
    public let temperatureCelsius: Double?
    public let temperatureSource: String?
    public let uptime: String?
    public let sampledAt: Date

    public init(
        host: String,
        healthScore: Int?,
        cpuUsage: Double?,
        logicalCPUCount: Int?,
        memoryUsedBytes: Int64?,
        memoryTotalBytes: Int64?,
        memoryUsedPercent: Double?,
        memoryAvailableBytes: Int64?,
        memoryCachedBytes: Int64?,
        memoryCompressedBytes: Int64?,
        memorySwapUsedBytes: Int64?,
        memorySwapTotalBytes: Int64?,
        memoryPressureLevel: MemoryPressureLevel,
        processCount: Int?,
        diskUsedPercent: Double?,
        diskFreeBytes: Int64?,
        batteryLevel: Double?,
        batteryStatus: String?,
        temperatureCelsius: Double?,
        temperatureSource: String?,
        uptime: String?,
        sampledAt: Date = Date()
    ) {
        self.host = host
        self.healthScore = healthScore
        self.cpuUsage = cpuUsage
        self.logicalCPUCount = logicalCPUCount
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.memoryUsedPercent = memoryUsedPercent
        self.memoryAvailableBytes = memoryAvailableBytes
        self.memoryCachedBytes = memoryCachedBytes
        self.memoryCompressedBytes = memoryCompressedBytes
        self.memorySwapUsedBytes = memorySwapUsedBytes
        self.memorySwapTotalBytes = memorySwapTotalBytes
        self.memoryPressureLevel = memoryPressureLevel
        self.processCount = processCount
        self.diskUsedPercent = diskUsedPercent
        self.diskFreeBytes = diskFreeBytes
        self.batteryLevel = batteryLevel
        self.batteryStatus = batteryStatus
        self.temperatureCelsius = temperatureCelsius
        self.temperatureSource = temperatureSource
        self.uptime = uptime
        self.sampledAt = sampledAt
    }
}

public struct MemoryAnalysis: Equatable, Sendable {
    public let level: MemoryPressureLevel
    public let title: String
    public let detail: String
    public let notes: [String]

    public init(level: MemoryPressureLevel, title: String, detail: String, notes: [String]) {
        self.level = level
        self.title = title
        self.detail = detail
        self.notes = notes
    }
}

public enum MemoryAnalyzer {
    public static func analyze(
        snapshot: SystemSnapshot,
        processes: [MemoryProcessSnapshot]
    ) -> MemoryAnalysis {
        let title: String
        let detail: String
        switch snapshot.memoryPressureLevel {
        case .normal:
            title = "当前内存供应正常"
            detail = "macOS 仍有足够内存可供应用使用，无需为了降低“已用”百分比而关闭 App。"
        case .warning:
            title = "内存压力值得留意"
            detail = "系统正在更积极地压缩或换出内存。若同时感觉卡顿，可先保存工作，再退出暂时不用的应用。"
        case .critical:
            title = "当前内存供应紧张"
            detail = "系统可能出现明显卡顿。请先保存工作，再从下方确认并退出不需要的高占用进程。"
        case .unknown:
            title = "本次压力状态数据不足"
            detail = "已读取容量和进程占用，但没有取得可靠的内存压力等级，因此不会仅凭百分比判断异常。"
        }

        var notes = [
            "内存占用高不等于内存不足。macOS 会主动利用空闲内存做缓存，并在其他 App 需要时回收。",
            "下方进程数值是单次采样的内存足迹近似值；共享内存、压缩内存和统一内存的计算方式不同，进程相加不会等于系统已用内存。"
        ]
        if let compressed = snapshot.memoryCompressedBytes, compressed > 0 {
            notes.append(
                "压缩内存约 \(CleanNestFormatting.bytes(compressed))：这是系统压缩暂时不用的数据，不是可以删除的文件缓存。"
            )
        }
        if let swapUsed = snapshot.memorySwapUsedBytes, swapUsed > 0 {
            notes.append(
                "交换空间已使用 \(CleanNestFormatting.bytes(swapUsed))；单次看到已有占用不代表此刻仍在频繁交换，应结合压力状态和持续卡顿判断。"
            )
        }
        if let top = processes.first {
            let displayName = top.applicationName ?? top.name
            notes.append(
                "本次单个内存足迹最高的是 \(displayName)，约 \(CleanNestFormatting.bytes(top.physicalFootprintBytes))；可刷新后观察是否持续增长。"
            )
        }

        return MemoryAnalysis(
            level: snapshot.memoryPressureLevel,
            title: title,
            detail: detail,
            notes: notes
        )
    }
}

public enum TrashFailureKind: String, Equatable, Sendable {
    case validation
    case targetChanged
    case authorizationCancelled
    case permissionDenied
    case operationFailed
    case missingResult
}

public struct TrashOutcome: Identifiable, Sendable {
    public let id = UUID()
    public let source: URL
    public let trashedURL: URL?
    public let errorDescription: String?
    public let failureKind: TrashFailureKind?
    public let technicalDescription: String?

    public var succeeded: Bool { errorDescription == nil }

    public init(
        source: URL,
        trashedURL: URL?,
        errorDescription: String?,
        failureKind: TrashFailureKind? = nil,
        technicalDescription: String? = nil
    ) {
        self.source = source
        self.trashedURL = trashedURL
        self.errorDescription = errorDescription
        self.failureKind = failureKind
        self.technicalDescription = technicalDescription
    }
}

public enum MaintenanceAction: String, CaseIterable, Identifiable, Sendable {
    case quickLook = "重建快速预览缓存"
    case finder = "重新启动 Finder"
    case dock = "重新启动 Dock"

    public var id: String { rawValue }

    public var symbolName: String {
        switch self {
        case .quickLook: return "eye"
        case .finder: return "face.smiling"
        case .dock: return "dock.rectangle"
        }
    }

    public var explanation: String {
        switch self {
        case .quickLook: return "解决文件缩略图或空格预览不更新的问题。"
        case .finder: return "重载桌面和文件窗口，打开的窗口会自动恢复。"
        case .dock: return "重载程序坞与启动台，不会退出正在运行的 App。"
        }
    }

    public var executable: URL {
        switch self {
        case .quickLook: return URL(fileURLWithPath: "/usr/bin/qlmanage")
        case .finder, .dock: return URL(fileURLWithPath: "/usr/bin/killall")
        }
    }

    public var arguments: [String] {
        switch self {
        case .quickLook: return ["-r", "cache"]
        case .finder: return ["Finder"]
        case .dock: return ["Dock"]
        }
    }
}
