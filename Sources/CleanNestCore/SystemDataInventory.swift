import Darwin
import Foundation

/// A curated, read-only inventory, not a reconstruction of Apple's private
/// Storage category and never a deletion allow-list. No upstream code is used.
public enum SystemDataDisposition: String, Codable, CaseIterable, Sendable {
    case rebuildable, review, ownerManaged

    public var label: String {
        switch self {
        case .rebuildable: return "可重建 · 先复核"
        case .review: return "个人数据 · 勿直接删"
        case .ownerManaged: return "由所属工具管理"
        }
    }
}

public struct SystemDataLocation: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let relativePath: String
    public let name: String
    public let owner: String
    public let purpose: String
    public let impact: String
    public let disposition: SystemDataDisposition
    public let requiresProtectedAccess: Bool

    public init(
        id: String, relativePath: String, name: String, owner: String,
        purpose: String, impact: String, disposition: SystemDataDisposition,
        requiresProtectedAccess: Bool = false
    ) {
        self.id = id
        self.relativePath = relativePath
        self.name = name
        self.owner = owner
        self.purpose = purpose
        self.impact = impact
        self.disposition = disposition
        self.requiresProtectedAccess = requiresProtectedAccess
    }

    public func url(in home: URL) -> URL {
        home.appendingPathComponent(relativePath).standardizedFileURL
    }
}

public enum SystemDataCatalog {
    // Intentionally disjoint. Never measure a parent and its children twice.
    // Overrides/custom tool locations are not inferred from arbitrary config.
    public static let locations: [SystemDataLocation] = [
        .init(id: "app-caches", relativePath: "Library/Caches", name: "应用下载与运行缓存", owner: "多个 App",
              purpose: "应用下载过或为加快运行而保存的副本；其中也可能有离线内容。",
              impact: "先退出相关 App，再到清理空间逐项复核；下次打开可能变慢、重新下载或失去离线内容。不能整目录一键删。",
              disposition: .rebuildable, requiresProtectedAccess: true),
        .init(id: "user-logs", relativePath: "Library/Logs", name: "应用日志", owner: "多个 App",
              purpose: "记录应用运行和故障的信息，不是你的文档。",
              impact: "旧记录通常不影响日常使用，但删除后无法用它排查过去的问题。正在写入的日志应保留。",
              disposition: .rebuildable),
        .init(id: "xcode-build", relativePath: "Library/Developer/Xcode/DerivedData", name: "Xcode 编译中间产物", owner: "Xcode",
              purpose: "编译缓存、索引和临时构建输出，不是项目源代码。",
              impact: "关闭构建后再复核；下一次编译和代码索引会重建，耗时可能明显增加。",
              disposition: .rebuildable),
        .init(id: "xcode-archives", relativePath: "Library/Developer/Xcode/Archives", name: "Xcode 发布归档", owner: "Xcode",
              purpose: "曾经打包的 App 和调试符号，可能用于发版或分析线上崩溃。",
              impact: "不是普通缓存。删掉旧归档可能失去对应版本的符号和安装包；应在 Xcode Organizer 中确认。",
              disposition: .review),
        .init(id: "xcode-device", relativePath: "Library/Developer/Xcode/iOS DeviceSupport", name: "真机调试支持文件", owner: "Xcode",
              purpose: "连接不同 iOS 设备版本时使用的调试支持数据。",
              impact: "移除后再次连接设备可能重新准备或下载；需要离线调试的版本应保留。",
              disposition: .ownerManaged),
        .init(id: "simulators", relativePath: "Library/Developer/CoreSimulator", name: "模拟器设备与数据", owner: "Xcode Simulator",
              purpose: "模拟器 App、设备状态和测试数据；不只是临时缓存。",
              impact: "删除设备会失去其中的数据。请先在 Xcode 中查看设备和运行时，不要直接删除整个目录。系统级运行时不在此项内。",
              disposition: .ownerManaged),
        .init(id: "ios-backups", relativePath: "Library/Application Support/MobileSync/Backup", name: "iPhone / iPad 本机备份", owner: "Finder",
              purpose: "用于恢复手机或平板的数据副本。",
              impact: "删掉会失去该次本机恢复能力。先核对设备、备份日期和其他备份，再通过 Finder 管理备份。",
              disposition: .review, requiresProtectedAccess: true),
        .init(id: "android-sdk", relativePath: "Library/Android/sdk", name: "Android SDK", owner: "Android Studio",
              purpose: "编译工具、平台和模拟器系统镜像。",
              impact: "应使用 SDK Manager 移除不再需要的版本；直接删可能让项目无法构建。",
              disposition: .ownerManaged),
        .init(id: "android-avd", relativePath: ".android/avd", name: "Android 虚拟设备", owner: "Android Studio",
              purpose: "虚拟手机的磁盘和设备内数据。",
              impact: "移除设备会丢失其中的 App 和测试数据；请在 Device Manager 中确认。",
              disposition: .ownerManaged),
        .init(id: "npm", relativePath: ".npm/_cacache", name: "npm 下载包缓存", owner: "npm",
              purpose: "安装依赖时下载并用过的软件包副本，不是项目代码或已安装的 node_modules。",
              impact: "清理后现有项目通常仍可运行；以后安装依赖可能重新联网下载，离线安装可能失败。",
              disposition: .rebuildable),
        .init(id: "pnpm-mac", relativePath: "Library/pnpm/store", name: "pnpm 共享依赖仓库", owner: "pnpm",
              purpose: "多个项目可能共享的软件包内容；路径相同不代表每份都独占磁盘块。",
              impact: "优先使用 pnpm 自己的 store prune。不要直接删除活跃项目正在引用的文件；显示占用不等于能释放的空间。",
              disposition: .ownerManaged),
        .init(id: "pnpm-local", relativePath: ".local/share/pnpm/store", name: "pnpm 备用共享仓库", owner: "pnpm",
              purpose: "部分安装方式留下的共享软件包目录。",
              impact: "优先使用 pnpm 自己的清理命令；可能与项目硬链接共享，不能按显示大小承诺释放量。",
              disposition: .ownerManaged),
        .init(id: "pip", relativePath: ".cache/pip", name: "pip 下载缓存", owner: "pip",
              purpose: "Python 包下载和构建时保存的缓存副本。",
              impact: "不会直接卸载 Python 环境；以后安装包可能重新下载或构建。",
              disposition: .rebuildable),
        .init(id: "uv", relativePath: ".cache/uv", name: "uv 下载与构建缓存", owner: "uv",
              purpose: "Python 依赖的下载和构建缓存。",
              impact: "请优先使用 uv cache clean / prune；不要在安装依赖时直接删目录。下次安装可能需要联网。",
              disposition: .ownerManaged),
        .init(id: "cargo", relativePath: ".cargo/registry", name: "Rust 包仓库", owner: "Cargo",
              purpose: "Rust 依赖的索引、下载包及解压源文件。",
              impact: "不是你的项目代码；清理可能导致重新下载、离线构建失败，正在构建时不要处理。",
              disposition: .ownerManaged),
        .init(id: "gradle", relativePath: ".gradle/caches", name: "Gradle 依赖与构建缓存", owner: "Gradle",
              purpose: "Android / JVM 项目的共享构建缓存。",
              impact: "下次构建可能重新下载和编译；先停止构建任务，再由开发工具管理。",
              disposition: .ownerManaged),
        .init(id: "maven", relativePath: ".m2/repository", name: "Maven 本地依赖仓库", owner: "Maven",
              purpose: "下载的依赖，也可能包含你仅在本机发布的包。",
              impact: "本地发布但未上传的包可能无法重新下载；不要把整仓库当作可随意丢弃的缓存。",
              disposition: .review),
        .init(id: "ollama", relativePath: ".ollama/models", name: "Ollama 模型文件", owner: "Ollama",
              purpose: "运行本地模型需要的权重和清单，不是推理后的垃圾。",
              impact: "移除后对应模型无法运行，需重新下载。先到本地模型页核对运行状态，再用 Ollama 管理。",
              disposition: .ownerManaged),
        .init(id: "huggingface", relativePath: ".cache/huggingface/hub", name: "Hugging Face 模型仓库", owner: "Hugging Face / MLX",
              purpose: "模型或数据集的下载内容，多个快照可能共享同一份权重。",
              impact: "不能因为目录名是 cache 就直接删；删除会让 MLX 等工具重新下载，离线模型可能不可用。",
              disposition: .ownerManaged),
        .init(id: "lmstudio", relativePath: ".lmstudio/models", name: "LM Studio 模型文件", owner: "LM Studio",
              purpose: "LM Studio 默认位置中保存的本地模型。",
              impact: "先确认模型未在运行，再在 LM Studio 中管理。自定义模型目录不在本次默认路径清单内。",
              disposition: .ownerManaged),
        .init(id: "docker", relativePath: "Library/Containers/com.docker.docker/Data/vms", name: "Docker 虚拟磁盘", owner: "Docker Desktop",
              purpose: "Linux 虚拟机内的镜像、容器和数据卷；磁盘文件可能是稀疏文件。",
              impact: "直接删除可能丢失容器数据库和卷。应先在 Docker 内检查用量；本页只显示分配块，不执行 prune。",
              disposition: .ownerManaged, requiresProtectedAccess: true),
        .init(id: "orbstack", relativePath: "Library/Group Containers/HUAQ24HBR6.dev.orbstack", name: "OrbStack 运行数据", owner: "OrbStack",
              purpose: "容器与 Linux 虚拟机的共享运行数据。",
              impact: "可能含数据库和个人工作文件。请由 OrbStack 管理，不把整个目录当作缓存。",
              disposition: .ownerManaged, requiresProtectedAccess: true),
        .init(id: "colima", relativePath: ".colima", name: "Colima 虚拟机数据", owner: "Colima",
              purpose: "本机容器运行环境、虚拟磁盘及配置。",
              impact: "删除可能同时丢失容器卷和配置，应由 Colima 管理。",
              disposition: .ownerManaged),
        .init(id: "lima", relativePath: ".lima", name: "Lima 虚拟机数据", owner: "Lima",
              purpose: "Linux 虚拟机的磁盘和配置。",
              impact: "可能保存工作文件；先确认实例和备份，再由 Lima 管理。",
              disposition: .ownerManaged),
        .init(id: "claude-vm", relativePath: "Library/Application Support/Claude/vm_bundles", name: "Claude 隔离运行环境", owner: "Claude",
              purpose: "用于隔离执行任务的虚拟机资源，不是聊天文字。",
              impact: "任务运行时必须保留。优先在 Agent 工作区查看活跃保护和恢复方式，移除后可能需要重新准备环境。",
              disposition: .ownerManaged, requiresProtectedAccess: true)
    ]

    public static func isValid(_ locations: [SystemDataLocation]) -> Bool {
        guard locations.count <= 64, Set(locations.map(\.id)).count == locations.count else { return false }
        let paths = locations.map { $0.relativePath.lowercased() }
        guard paths.allSatisfy({ path in
            !path.isEmpty && !path.hasPrefix("/")
                && !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
                && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
                    !$0.isEmpty && $0 != "." && $0 != ".."
                }
        }) else { return false }
        for (index, path) in paths.enumerated() {
            for other in paths.dropFirst(index + 1) {
                if path == other || path.hasPrefix(other + "/") || other.hasPrefix(path + "/") { return false }
            }
        }
        return true
    }
}

public enum SystemDataMeasurementStatus: String, Codable, Sendable {
    case measured, partial, notFound, protectedLocation, unreadable, symbolicLink, otherVolume

    public var label: String {
        switch self {
        case .measured: return "已测量"
        case .partial: return "仅测得部分"
        case .notFound: return "默认路径未找到"
        case .protectedLocation: return "待访问授权"
        case .unreadable: return "无法读取"
        case .symbolicLink: return "已跳过符号链接"
        case .otherVolume: return "已跳过其他卷"
        }
    }
}

public struct SystemDataItem: Codable, Equatable, Identifiable, Sendable {
    public let location: SystemDataLocation
    public let url: URL
    public let status: SystemDataMeasurementStatus
    public let allocatedBytes: Int64?
    public let traversal: FileTreeTraversalEvidence?
    public let latestModificationDate: Date?
    public var id: String { location.id }

    public init(location: SystemDataLocation, url: URL, status: SystemDataMeasurementStatus,
                allocatedBytes: Int64? = nil, traversal: FileTreeTraversalEvidence? = nil,
                latestModificationDate: Date? = nil) {
        self.location = location
        self.url = url
        self.status = status
        self.allocatedBytes = allocatedBytes.map { max(0, $0) }
        self.traversal = traversal
        self.latestModificationDate = latestModificationDate
    }

    /// Missing/partial measurements never masquerade as zero or a shrinkage.
    public func change(from previous: SystemDataItem?) -> Int64? {
        guard status == .measured, previous?.status == .measured,
              let previous, previous.location == location, previous.url == url,
              let current = allocatedBytes, let old = previous.allocatedBytes else { return nil }
        return current - old
    }
}

public struct SystemDataReport: Codable, Equatable, Sendable {
    public let capturedAt: Date
    public let items: [SystemDataItem]
    public let volume: DiskVolumeSnapshot?
    public var measuredBytes: Int64 { items.reduce(0) { $0 + ($1.allocatedBytes ?? 0) } }
    public var incompleteCount: Int {
        items.filter { $0.status != .measured && $0.status != .notFound }.count
    }
    public init(capturedAt: Date = Date(), items: [SystemDataItem], volume: DiskVolumeSnapshot?) {
        self.capturedAt = capturedAt
        self.items = items
        self.volume = volume
    }

    public func visibleItems(query: String, filter: SystemDataFilter, previous: SystemDataReport?) -> [SystemDataItem] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            let old = previous?.items.first { $0.id == item.id }
            let visible = item.status != .notFound && (item.allocatedBytes != 0 || item.status != .measured
                || item.change(from: old) != nil)
            let text = [item.location.name, item.location.owner, item.location.relativePath, item.location.purpose].joined(separator: " ")
            return visible && filter.includes(item) && (search.isEmpty || text.localizedStandardContains(search))
        }.sorted {
            if $0.allocatedBytes == $1.allocatedBytes { return $0.location.name < $1.location.name }
            return ($0.allocatedBytes ?? -1) > ($1.allocatedBytes ?? -1)
        }
    }
}

public enum SystemDataFilter: String, CaseIterable, Sendable {
    case all, rebuildable, managed, gaps
    public func includes(_ item: SystemDataItem) -> Bool {
        switch self {
        case .all: return true
        case .rebuildable: return item.location.disposition == .rebuildable
        case .managed: return item.location.disposition != .rebuildable
        case .gaps: return item.status != .measured && item.status != .notFound
        }
    }
}

public struct SystemDataScannerRequest: Codable, Equatable, Sendable {
    public let requestID: String
    public let homeDirectory: URL
    public let protectedAccessConfirmed: Bool
    public init(requestID: String = UUID().uuidString, homeDirectory: URL, protectedAccessConfirmed: Bool) {
        self.requestID = requestID
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.protectedAccessConfirmed = protectedAccessConfirmed
    }
}

public struct SystemDataScannerResponse: Codable, Equatable, Sendable {
    public let requestID: String
    public let report: SystemDataReport
    public init(requestID: String, report: SystemDataReport) { self.requestID = requestID; self.report = report }
}

public struct SystemDataScanner: Sendable {
    public let maximumEntriesPerLocation: Int
    public init(maximumEntriesPerLocation: Int = 100_000) {
        self.maximumEntriesPerLocation = min(100_000, max(1, maximumEntriesPerLocation))
    }

    public func scan(
        homeDirectory: URL, protectedAccessConfirmed: Bool,
        locations: [SystemDataLocation] = SystemDataCatalog.locations,
        progress: (@Sendable (Int, Int, String) -> Void)? = nil
    ) async throws -> SystemDataReport {
        try Task.checkCancellation()
        guard homeDirectory.isFileURL, SystemDataCatalog.isValid(locations) else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let limit = maximumEntriesPerLocation
        let worker = Task.detached(priority: .utility) {
            let home = homeDirectory.standardizedFileURL
            var items: [SystemDataItem] = []
            for (index, location) in locations.enumerated() {
                try Task.checkCancellation()
                progress?(index, locations.count, location.name)
                let url = location.url(in: home)
                // Gate before even stat'ing protected paths. Unknown access is
                // not permission to trigger a chain of per-container prompts.
                if location.requiresProtectedAccess && !protectedAccessConfirmed {
                    items.append(SystemDataItem(location: location, url: url, status: .protectedLocation))
                } else if let status = Self.preflight(location, home: home) {
                    items.append(SystemDataItem(location: location, url: url, status: status))
                } else {
                    let metrics = FileTree.metrics(of: url, includeLatestModificationDate: true,
                                                   maximumEntries: limit, stayOnFileSystem: true)
                    try Task.checkCancellation()
                    let evidence = metrics.traversal
                    let complete = evidence.isCompleteWithinFileSystem
                        && evidence.crossVolumeEntryCount == 0 && evidence.symbolicLinkCount == 0
                    items.append(SystemDataItem(location: location, url: url,
                        status: !evidence.rootWasReadable ? .unreadable : (complete ? .measured : .partial),
                        allocatedBytes: evidence.rootWasReadable ? metrics.allocatedBytes : nil,
                        traversal: evidence, latestModificationDate: metrics.latestModificationDate))
                }
                progress?(index + 1, locations.count, location.name)
            }
            try Task.checkCancellation()
            return SystemDataReport(items: items, volume: DiskVolumeSnapshot.capture(for: home))
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }

    /// Check intermediate components as well as the final path. FileTree's
    /// physical walk skips links below that path; this closes the static alias
    /// escape above it. These are read-only observations, never delete permits.
    private static func preflight(_ location: SystemDataLocation, home: URL) -> SystemDataMeasurementStatus? {
        var info = stat()
        guard home.path.withCString({ lstat($0, &info) }) == 0 else { return .unreadable }
        guard info.st_mode & S_IFMT == S_IFDIR else { return .symbolicLink }
        let device = info.st_dev
        var current = home
        for component in location.relativePath.split(separator: "/") {
            current.appendPathComponent(String(component))
            guard current.path.withCString({ lstat($0, &info) }) == 0 else {
                return errno == ENOENT || errno == ENOTDIR ? .notFound : .unreadable
            }
            if info.st_mode & S_IFMT == S_IFLNK { return .symbolicLink }
            if info.st_dev != device { return .otherVolume }
        }
        guard info.st_mode & S_IFMT == S_IFDIR else { return .unreadable }
        // lstat alone succeeds even when the directory cannot be enumerated.
        // Confirm readability without following a last-moment leaf symlink.
        let descriptor = current.path.withCString { open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        guard descriptor >= 0 else { return .unreadable }
        close(descriptor)
        return nil
    }
}
