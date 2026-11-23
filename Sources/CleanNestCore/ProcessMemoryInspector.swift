import Darwin
import Foundation

public enum MemoryPressureLevel: String, Codable, Equatable, Sendable {
    case normal
    case warning
    case critical
    case unknown

    public init(reportedValue: String?) {
        switch reportedValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "normal", "green", "ok":
            self = .normal
        case "warn", "warning", "yellow":
            self = .warning
        case "critical", "red", "urgent":
            self = .critical
        default:
            self = .unknown
        }
    }
}

public struct SystemMemoryProbeSnapshot: Equatable, Sendable {
    public let compressedBytes: Int64?
    public let pressureLevel: MemoryPressureLevel

    public init(compressedBytes: Int64?, pressureLevel: MemoryPressureLevel) {
        self.compressedBytes = compressedBytes
        self.pressureLevel = pressureLevel
    }
}

public enum SystemMemoryProbe {
    public static func sample() -> SystemMemoryProbeSnapshot {
        SystemMemoryProbeSnapshot(
            compressedBytes: compressedMemoryBytes(),
            pressureLevel: currentPressureLevel()
        )
    }

    private static func compressedMemoryBytes() -> Int64? {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
        let (bytes, overflowed) = UInt64(statistics.compressor_page_count)
            .multipliedReportingOverflow(by: UInt64(pageSize))
        guard !overflowed else { return Int64.max }
        return clampedInt64(bytes)
    }

    private static func currentPressureLevel() -> MemoryPressureLevel {
        var rawLevel: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname(
            "kern.memorystatus_vm_pressure_level",
            &rawLevel,
            &size,
            nil,
            0
        )
        guard result == 0, size == MemoryLayout<Int32>.size else { return .unknown }
        switch rawLevel {
        case 1: return .normal
        case 2: return .warning
        case 4: return .critical
        default: return .unknown
        }
    }

    private static func clampedInt64(_ value: UInt64) -> Int64 {
        value > UInt64(Int64.max) ? Int64.max : Int64(value)
    }
}

public struct MemoryProcessSnapshot: Identifiable, Equatable, Sendable {
    public let pid: Int32
    public let parentPID: Int32
    public let name: String
    public let applicationName: String?
    public let executablePath: String?
    public let physicalFootprintBytes: Int64
    public let residentBytes: Int64
    public let ownerUserID: UInt32
    public let startSeconds: UInt64
    public let startMicroseconds: UInt64
    public let purpose: String
    public let terminationImpact: String
    public let protectionReason: String?

    public var id: String {
        "\(pid):\(startSeconds):\(startMicroseconds)"
    }

    public var canTerminate: Bool { protectionReason == nil }

    public init(
        pid: Int32,
        parentPID: Int32,
        name: String,
        applicationName: String?,
        executablePath: String?,
        physicalFootprintBytes: Int64,
        residentBytes: Int64,
        ownerUserID: UInt32,
        startSeconds: UInt64,
        startMicroseconds: UInt64,
        purpose: String,
        terminationImpact: String,
        protectionReason: String?
    ) {
        self.pid = pid
        self.parentPID = parentPID
        self.name = name
        self.applicationName = applicationName
        self.executablePath = executablePath
        self.physicalFootprintBytes = physicalFootprintBytes
        self.residentBytes = residentBytes
        self.ownerUserID = ownerUserID
        self.startSeconds = startSeconds
        self.startMicroseconds = startMicroseconds
        self.purpose = purpose
        self.terminationImpact = terminationImpact
        self.protectionReason = protectionReason
    }
}

public enum MemoryProcessTerminationResult: Equatable, Sendable {
    case terminated
    case stillRunning
    case alreadyExited
    case identityChanged
    case refused(String)
    case failed(String)
}

public struct ProcessMemoryInspector: Sendable {
    private let currentUserID: UInt32
    private let currentProcessID: Int32
    private let protectedAncestorPIDs: Set<Int32>

    public init() {
        let currentPID = getpid()
        currentUserID = UInt32(getuid())
        currentProcessID = currentPID
        protectedAncestorPIDs = Self.ancestorPIDs(startingAt: currentPID)
    }

    public func topProcesses(limit: Int = 12) -> [MemoryProcessSnapshot] {
        guard limit > 0 else { return [] }
        return allProcessIDs()
            .compactMap { process(pid: $0) }
            .sorted {
                if $0.physicalFootprintBytes == $1.physicalFootprintBytes {
                    return $0.pid < $1.pid
                }
                return $0.physicalFootprintBytes > $1.physicalFootprintBytes
            }
            .prefix(limit)
            .map { $0 }
    }

    public func processCount() -> Int? {
        let processIDs = allProcessIDs()
        return processIDs.isEmpty ? nil : processIDs.count
    }

    public func process(pid: Int32) -> MemoryProcessSnapshot? {
        guard pid > 0, let info = Self.bsdInfo(pid: pid) else { return nil }

        let path = Self.executablePath(pid: pid)
        let processName = Self.processName(pid: pid, executablePath: path)
        let application = Self.applicationInfo(executablePath: path)
        let memory = Self.memoryUsage(pid: pid)
        let protection = protectionReason(
            pid: pid,
            info: info,
            name: processName,
            executablePath: path
        )
        let explanation = Self.explanation(
            name: processName,
            application: application,
            executablePath: path,
            protectionReason: protection
        )

        return MemoryProcessSnapshot(
            pid: pid,
            parentPID: Int32(bitPattern: info.pbi_ppid),
            name: processName,
            applicationName: application?.name,
            executablePath: path,
            physicalFootprintBytes: memory.physicalFootprint,
            residentBytes: memory.resident,
            ownerUserID: UInt32(info.pbi_uid),
            startSeconds: info.pbi_start_tvsec,
            startMicroseconds: info.pbi_start_tvusec,
            purpose: explanation.purpose,
            terminationImpact: explanation.impact,
            protectionReason: protection
        )
    }

    public func terminate(
        _ snapshot: MemoryProcessSnapshot,
        force: Bool = false
    ) -> MemoryProcessTerminationResult {
        if let reason = snapshot.protectionReason {
            return .refused(reason)
        }
        guard let current = process(pid: snapshot.pid) else { return .alreadyExited }
        guard Self.sameIdentity(snapshot, current) else { return .identityChanged }
        if let reason = current.protectionReason {
            return .refused(reason)
        }

        let signalNumber = force ? SIGKILL : SIGTERM
        errno = 0
        guard Darwin.kill(snapshot.pid, signalNumber) == 0 else {
            switch errno {
            case ESRCH:
                return .alreadyExited
            case EPERM:
                return .failed("当前用户没有权限结束这个进程。")
            default:
                let detail = String(cString: strerror(errno))
                return .failed("结束进程失败：\(detail)")
            }
        }

        let deadline = DispatchTime.now().uptimeNanoseconds + 3_000_000_000
        while DispatchTime.now().uptimeNanoseconds < deadline {
            usleep(50_000)
            guard let observed = process(pid: snapshot.pid) else { return .terminated }
            guard Self.sameIdentity(snapshot, observed) else { return .identityChanged }
        }
        return .stillRunning
    }

    private func allProcessIDs() -> [Int32] {
        let estimatedCount = proc_listallpids(nil, 0)
        guard estimatedCount > 0 else { return [] }

        var capacity = max(Int(estimatedCount) + 64, 256)
        let maximumCapacity = 65_536
        while capacity <= maximumCapacity {
            var buffer = [pid_t](repeating: 0, count: capacity)
            let returnedCount = buffer.withUnsafeMutableBytes { bytes in
                proc_listallpids(bytes.baseAddress, Int32(bytes.count))
            }
            guard returnedCount >= 0 else { return [] }
            if Int(returnedCount) < capacity || capacity == maximumCapacity {
                let validCount = min(Int(returnedCount), capacity)
                var processIDs: [Int32] = []
                processIDs.reserveCapacity(validCount)
                for index in 0..<validCount where buffer[index] > 0 {
                    processIDs.append(Int32(buffer[index]))
                }
                return processIDs
            }
            capacity = min(capacity * 2, maximumCapacity)
        }
        return []
    }

    private func protectionReason(
        pid: Int32,
        info: proc_bsdinfo,
        name: String,
        executablePath: String?
    ) -> String? {
        if pid <= 1 { return "这是 macOS 核心进程，禁止结束。" }
        if pid == currentProcessID { return "这是 CleanNest 自身，禁止从应用内结束。" }
        if protectedAncestorPIDs.contains(pid) {
            return "这是启动 CleanNest 的上级进程，禁止结束。"
        }
        if UInt32(info.pbi_uid) != currentUserID {
            return "该进程不属于当前登录用户，CleanNest 不会尝试结束。"
        }
        if info.pbi_flags & UInt32(PROC_FLAG_SYSTEM) != 0 {
            return "这是 macOS 标记的系统进程，禁止结束。"
        }
        if Self.isCriticalService(name: name, executablePath: executablePath) {
            return "这是 macOS 关键服务或桌面组件，禁止结束。"
        }
        return nil
    }

    private static func sameIdentity(
        _ expected: MemoryProcessSnapshot,
        _ observed: MemoryProcessSnapshot
    ) -> Bool {
        expected.pid == observed.pid
            && expected.ownerUserID == observed.ownerUserID
            && expected.startSeconds == observed.startSeconds
            && expected.startMicroseconds == observed.startMicroseconds
            && expected.executablePath == observed.executablePath
    }

    private static func ancestorPIDs(startingAt currentPID: Int32) -> Set<Int32> {
        var result = Set<Int32>()
        var visited = Set<Int32>()
        var cursor = currentPID

        while cursor > 1, visited.insert(cursor).inserted {
            guard let info = bsdInfo(pid: cursor) else { break }
            let parent = Int32(bitPattern: info.pbi_ppid)
            guard parent > 0, parent != cursor else { break }
            result.insert(parent)
            cursor = parent
        }
        result.insert(0)
        result.insert(1)
        return result
    }

    private static func bsdInfo(pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let expectedSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        let copied = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, expectedSize)
        }
        guard copied == expectedSize, info.pbi_pid == UInt32(bitPattern: pid) else { return nil }
        return info
    }

    private static func memoryUsage(pid: Int32) -> (physicalFootprint: Int64, resident: Int64) {
        var usage = rusage_info_v4()
        let usageResult = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }

        var taskInfo = proc_taskinfo()
        let expectedTaskSize = Int32(MemoryLayout<proc_taskinfo>.size)
        let taskResult = withUnsafeMutablePointer(to: &taskInfo) {
            proc_pidinfo(pid, PROC_PIDTASKINFO, 0, $0, expectedTaskSize)
        }

        let rusageResident = usageResult == 0 ? clampedInt64(usage.ri_resident_size) : 0
        let taskResident = taskResult == expectedTaskSize ? clampedInt64(taskInfo.pti_resident_size) : 0
        let resident = taskResident > 0 ? taskResident : rusageResident
        let reportedFootprint = usageResult == 0 ? clampedInt64(usage.ri_phys_footprint) : 0
        return (reportedFootprint > 0 ? reportedFootprint : resident, resident)
    }

    private static func executablePath(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = buffer.withUnsafeMutableBufferPointer {
            proc_pidpath(pid, $0.baseAddress, UInt32($0.count))
        }
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func processName(pid: Int32, executablePath: String?) -> String {
        var buffer = [CChar](repeating: 0, count: 1_024)
        let length = buffer.withUnsafeMutableBufferPointer {
            proc_name(pid, $0.baseAddress, UInt32($0.count))
        }
        if length > 0 {
            let name = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        if let path = executablePath, !path.isEmpty {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return "进程 \(pid)"
    }

    private struct ApplicationInfo {
        let name: String
        let isHelper: Bool
    }

    private static func applicationInfo(executablePath: String?) -> ApplicationInfo? {
        guard let executablePath else { return nil }
        let components = URL(fileURLWithPath: executablePath).pathComponents
        guard let appIndex = components.firstIndex(where: { $0.lowercased().hasSuffix(".app") }) else {
            return nil
        }
        let component = components[appIndex]
        let name = String(component.dropLast(4))
        guard !name.isEmpty else { return nil }
        let laterComponents = components.dropFirst(appIndex + 1)
        let isHelper = laterComponents.contains { $0.lowercased().hasSuffix(".app") }
            || laterComponents.contains("Helpers")
            || laterComponents.contains("XPCServices")
        return ApplicationInfo(name: name, isHelper: isHelper)
    }

    private static func explanation(
        name: String,
        application: ApplicationInfo?,
        executablePath: String?,
        protectionReason: String?
    ) -> (purpose: String, impact: String) {
        let loweredName = name.lowercased()
        if loweredName.hasPrefix("python") {
            return (
                "Python 运行时；常见于本机 AI、数据处理或开发脚本。为保护隐私，CleanNest 未读取命令行参数，因此不能确认具体项目。",
                protectionReason == nil
                    ? "结束后，依赖它的本机模型、自动化或 Python 任务会中断；若它占用很多内存，请先确认本机 AI 当前没有在分析。"
                    : "受保护，不提供结束操作。"
            )
        }
        if loweredName.contains("webkit") {
            return (
                "WebKit 网页内容进程；通常由浏览器或 App 内嵌网页启动，同一个 App 可能有多个。",
                protectionReason == nil
                    ? "结束后，对应网页或内嵌界面可能关闭、变空白或自动重新载入，未提交的网页内容可能丢失。"
                    : "受保护，不提供结束操作。"
            )
        }
        if loweredName == "node" || loweredName.hasPrefix("node.") {
            return (
                "Node.js JavaScript 运行时；常见于开发工具、桌面 App 辅助服务或本地自动化。",
                protectionReason == nil
                    ? "结束后，依赖它的开发服务或自动化任务会中断；如果用途不明确，建议先不要结束。"
                    : "受保护，不提供结束操作。"
            )
        }
        switch loweredName {
        case "finder":
            return ("macOS 的文件管理器 Finder。", "受系统保护，不提供结束操作。")
        case "dock":
            return ("macOS 的 Dock 与应用切换桌面组件。", "受系统保护，不提供结束操作。")
        case "systemuiserver":
            return ("macOS 菜单栏系统状态组件。", "受系统保护，不提供结束操作。")
        default:
            break
        }

        if let application {
            if application.isHelper {
                return (
                    "“\(application.name)”的辅助进程；未读取命令行参数，无法确认更具体的职责。",
                    protectionReason == nil
                        ? "结束后“\(application.name)”的相关功能可能中断，应用也可能自动重新启动它。"
                        : "受保护，不提供结束操作。"
                )
            }
            return (
                "“\(application.name)”的应用进程。",
                protectionReason == nil
                    ? "结束后“\(application.name)”会关闭，未保存内容可能丢失。"
                    : "受保护，不提供结束操作。"
            )
        }

        if executablePath?.lowercased().contains("/.mlx-env/") == true {
            return (
                "位于本机 MLX 虚拟环境中的进程；仅凭可执行文件路径无法确认它正在加载哪个模型。",
                protectionReason == nil
                    ? "结束后，依赖它的本机模型或 Python 任务会停止，正在进行的分析会中断。"
                    : "受保护，不提供结束操作。"
            )
        }

        if protectionReason != nil {
            return (
                "macOS 系统或登录会话进程；未读取命令行参数，具体职责未知。",
                "受保护，不提供结束操作。"
            )
        }
        return (
            "未读取命令行参数，无法确认该进程的具体用途。",
            "结束后依赖它的任务会立即中断；如果用途不明确，建议先不要结束。"
        )
    }

    private static func isCriticalService(name: String, executablePath: String?) -> Bool {
        let criticalNames: Set<String> = [
            "kernel_task", "launchd", "loginwindow", "windowserver",
            "runningboardd", "tccd", "cfprefsd", "distnoted",
            "coreservicesd", "pboard", "sharedfilelistd", "usernoted",
            "powerd", "securityd", "trustd", "coreaudiod", "bluetoothd",
            "mds", "mds_stores", "finder", "dock", "systemuiserver",
            "controlcenter", "notificationcenter"
        ]
        if criticalNames.contains(name.lowercased()) { return true }

        guard let loweredPath = executablePath?.lowercased() else { return false }
        let protectedPathFragments = [
            "/system/library/coreservices/finder.app/",
            "/system/library/coreservices/dock.app/",
            "/system/library/coreservices/systemuiserver.app/",
            "/system/library/coreservices/controlcenter.app/",
            "/system/library/coreservices/notificationcenter.app/"
        ]
        return protectedPathFragments.contains { loweredPath.contains($0) }
    }

    private static func clampedInt64(_ value: UInt64) -> Int64 {
        value > UInt64(Int64.max) ? Int64.max : Int64(value)
    }
}
