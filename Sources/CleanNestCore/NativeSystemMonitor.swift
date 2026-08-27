import Darwin
import Foundation
import IOKit
import IOKit.ps
import SystemConfiguration

public enum MenuBarMetric: String, CaseIterable, Codable, Identifiable, Sendable {
    case cpu
    case memory
    case temperature
    case network
    case disk
    case gpu
    case fan
    case battery

    public var id: String { rawValue }
}

public enum NativeMetricHealthLevel: Int, Comparable, Codable, Sendable {
    case normal
    case warning
    case critical

    public static func < (lhs: NativeMetricHealthLevel, rhs: NativeMetricHealthLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum NativeThermalState: String, Codable, Sendable {
    case nominal
    case fair
    case serious
    case critical
    case unknown

    var healthLevel: NativeMetricHealthLevel {
        switch self {
        case .nominal, .unknown: return .normal
        case .fair: return .warning
        case .serious, .critical: return .critical
        }
    }
}

public enum MenuBarMetricStyle: String, CaseIterable, Codable, Sendable {
    case text
    case graph
}

public enum MenuBarPresentationMode: String, CaseIterable, Codable, Sendable {
    case compact
    case separate
}

public enum MenuBarTemperatureUnit: String, CaseIterable, Codable, Sendable {
    case celsius
    case fahrenheit
}

public enum MenuBarRefreshInterval: Int, CaseIterable, Codable, Sendable {
    case oneSecond = 1
    case twoSeconds = 2
    case fiveSeconds = 5
    case tenSeconds = 10
}

public enum MenuBarNetworkMode: String, CaseIterable, Codable, Sendable {
    case automatic
    case physicalAggregate
    case specific
}

public struct MenuBarMetricPreference: Codable, Equatable, Sendable {
    public let metric: MenuBarMetric
    public var isEnabled: Bool
    public var style: MenuBarMetricStyle

    public init(metric: MenuBarMetric, isEnabled: Bool, style: MenuBarMetricStyle) {
        self.metric = metric
        self.isEnabled = isEnabled
        self.style = style
    }
}

public struct MenuBarMonitorConfiguration: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var metrics: [MenuBarMetricPreference]
    public var presentationMode: MenuBarPresentationMode
    public var compactMetric: MenuBarMetric
    public var temperatureUnit: MenuBarTemperatureUnit
    public var refreshInterval: MenuBarRefreshInterval
    public var networkMode: MenuBarNetworkMode
    public var selectedNetworkInterface: String?
    public var globalHotKeyEnabled: Bool

    public init(
        isEnabled: Bool,
        metrics: [MenuBarMetricPreference],
        presentationMode: MenuBarPresentationMode = .compact,
        compactMetric: MenuBarMetric = .cpu,
        temperatureUnit: MenuBarTemperatureUnit = .celsius,
        refreshInterval: MenuBarRefreshInterval = .twoSeconds,
        networkMode: MenuBarNetworkMode = .physicalAggregate,
        selectedNetworkInterface: String? = nil,
        globalHotKeyEnabled: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.metrics = metrics
        self.presentationMode = presentationMode
        self.compactMetric = compactMetric
        self.temperatureUnit = temperatureUnit
        self.refreshInterval = refreshInterval
        self.networkMode = networkMode
        self.selectedNetworkInterface = selectedNetworkInterface
        self.globalHotKeyEnabled = globalHotKeyEnabled
    }

    public static let defaults = MenuBarMonitorConfiguration(
        isEnabled: true,
        metrics: [
            MenuBarMetricPreference(metric: .cpu, isEnabled: true, style: .text),
            MenuBarMetricPreference(metric: .memory, isEnabled: true, style: .text),
            MenuBarMetricPreference(metric: .temperature, isEnabled: true, style: .text),
            MenuBarMetricPreference(metric: .network, isEnabled: true, style: .text),
            MenuBarMetricPreference(metric: .disk, isEnabled: true, style: .text),
            MenuBarMetricPreference(metric: .gpu, isEnabled: false, style: .text),
            MenuBarMetricPreference(metric: .fan, isEnabled: true, style: .text),
            MenuBarMetricPreference(metric: .battery, isEnabled: false, style: .text)
        ],
        presentationMode: .compact,
        compactMetric: .cpu,
        temperatureUnit: .celsius,
        refreshInterval: .twoSeconds,
        networkMode: .physicalAggregate,
        selectedNetworkInterface: nil,
        globalHotKeyEnabled: true
    )

    public var normalized: MenuBarMonitorConfiguration {
        var seen = Set<MenuBarMetric>()
        let orderedSaved = metrics.filter { seen.insert($0.metric).inserted }
        let savedMetrics = Set(orderedSaved.map(\.metric))
        let completed = orderedSaved + MenuBarMetric.allCases
            .filter { !savedMetrics.contains($0) }
            .map { Self.defaults.preference(for: $0) }
        let enabled = completed.filter(\.isEnabled).map(\.metric)
        let validCompactMetric = enabled.contains(compactMetric)
            ? compactMetric
            : (enabled.first ?? .cpu)
        return MenuBarMonitorConfiguration(
            isEnabled: isEnabled,
            metrics: completed,
            presentationMode: presentationMode,
            compactMetric: validCompactMetric,
            temperatureUnit: temperatureUnit,
            refreshInterval: refreshInterval,
            networkMode: networkMode,
            selectedNetworkInterface: selectedNetworkInterface?.isEmpty == false
                ? selectedNetworkInterface
                : nil,
            globalHotKeyEnabled: globalHotKeyEnabled
        )
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case metrics
        case presentationMode
        case compactMetric
        case temperatureUnit
        case refreshInterval
        case networkMode
        case selectedNetworkInterface
        case globalHotKeyEnabled
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled)
            ?? Self.defaults.isEnabled
        metrics = try values.decodeIfPresent([MenuBarMetricPreference].self, forKey: .metrics)
            ?? Self.defaults.metrics
        presentationMode = try values.decodeIfPresent(
            MenuBarPresentationMode.self,
            forKey: .presentationMode
        ) ?? Self.defaults.presentationMode
        compactMetric = try values.decodeIfPresent(MenuBarMetric.self, forKey: .compactMetric)
            ?? Self.defaults.compactMetric
        temperatureUnit = try values.decodeIfPresent(
            MenuBarTemperatureUnit.self,
            forKey: .temperatureUnit
        ) ?? Self.defaults.temperatureUnit
        refreshInterval = try values.decodeIfPresent(
            MenuBarRefreshInterval.self,
            forKey: .refreshInterval
        ) ?? Self.defaults.refreshInterval
        networkMode = try values.decodeIfPresent(MenuBarNetworkMode.self, forKey: .networkMode)
            ?? Self.defaults.networkMode
        selectedNetworkInterface = try values.decodeIfPresent(
            String.self,
            forKey: .selectedNetworkInterface
        )
        globalHotKeyEnabled = try values.decodeIfPresent(Bool.self, forKey: .globalHotKeyEnabled)
            ?? Self.defaults.globalHotKeyEnabled
    }

    public func preference(for metric: MenuBarMetric) -> MenuBarMetricPreference {
        metrics.first(where: { $0.metric == metric })
            ?? MenuBarMetricPreference(metric: metric, isEnabled: false, style: .text)
    }

    public mutating func setEnabled(_ enabled: Bool, for metric: MenuBarMetric) {
        update(metric) { $0.isEnabled = enabled }
    }

    public mutating func setStyle(_ style: MenuBarMetricStyle, for metric: MenuBarMetric) {
        update(metric) { $0.style = style }
    }

    public mutating func move(_ metric: MenuBarMetric, by offset: Int) {
        guard let source = metrics.firstIndex(where: { $0.metric == metric }) else { return }
        let destination = min(metrics.count - 1, max(0, source + offset))
        guard source != destination else { return }
        let value = metrics.remove(at: source)
        metrics.insert(value, at: destination)
    }

    private mutating func update(
        _ metric: MenuBarMetric,
        change: (inout MenuBarMetricPreference) -> Void
    ) {
        if let index = metrics.firstIndex(where: { $0.metric == metric }) {
            change(&metrics[index])
        } else {
            var value = Self.defaults.preference(for: metric)
            change(&value)
            metrics.append(value)
        }
    }
}

public struct NativeMonitorSample: Equatable, Sendable {
    public let sampledAt: Date
    public let cpuUsage: Double?
    public let cpuUserPercent: Double?
    public let cpuSystemPercent: Double?
    public let cpuIdlePercent: Double?
    public let memoryUsedPercent: Double?
    public let memoryUsedBytes: Int64?
    public let memoryTotalBytes: Int64?
    public let memoryPressureLevel: MemoryPressureLevel
    public let diskUsedPercent: Double?
    public let diskFreeBytes: Int64?
    public let diskReadBytesPerSecond: Double?
    public let diskWriteBytesPerSecond: Double?
    public let networkDownloadBytesPerSecond: Double?
    public let networkUploadBytesPerSecond: Double?
    public let networkInterfaceName: String?
    public let availableNetworkInterfaces: [String]
    public let gpuUsage: Double?
    public let gpuRendererUsage: Double?
    public let gpuTilerUsage: Double?
    public let temperatureCelsius: Double?
    public let temperatureSource: String?
    public let batteryTemperatureCelsius: Double?
    public let batteryTemperatureSource: String?
    public let fanRPM: Double?
    public let fanCount: Int?
    public let fanSpeedsRPM: [Double]
    public let fanLoadPercent: Double?
    public let batteryLevel: Double?
    public let batteryStatus: String?
    public let batteryIsCharging: Bool?
    public let batteryTimeRemainingMinutes: Int?
    public let thermalState: NativeThermalState

    public init(
        sampledAt: Date,
        cpuUsage: Double?,
        cpuUserPercent: Double? = nil,
        cpuSystemPercent: Double? = nil,
        cpuIdlePercent: Double? = nil,
        memoryUsedPercent: Double?,
        memoryUsedBytes: Int64?,
        memoryTotalBytes: Int64?,
        memoryPressureLevel: MemoryPressureLevel,
        diskUsedPercent: Double?,
        diskFreeBytes: Int64?,
        diskReadBytesPerSecond: Double? = nil,
        diskWriteBytesPerSecond: Double? = nil,
        networkDownloadBytesPerSecond: Double?,
        networkUploadBytesPerSecond: Double?,
        networkInterfaceName: String?,
        availableNetworkInterfaces: [String] = [],
        gpuUsage: Double?,
        gpuRendererUsage: Double?,
        gpuTilerUsage: Double?,
        temperatureCelsius: Double?,
        temperatureSource: String?,
        batteryTemperatureCelsius: Double? = nil,
        batteryTemperatureSource: String? = nil,
        fanRPM: Double?,
        fanCount: Int?,
        fanSpeedsRPM: [Double] = [],
        fanLoadPercent: Double? = nil,
        batteryLevel: Double? = nil,
        batteryStatus: String? = nil,
        batteryIsCharging: Bool? = nil,
        batteryTimeRemainingMinutes: Int? = nil,
        thermalState: NativeThermalState = .unknown
    ) {
        self.sampledAt = sampledAt
        self.cpuUsage = cpuUsage
        self.cpuUserPercent = cpuUserPercent
        self.cpuSystemPercent = cpuSystemPercent
        self.cpuIdlePercent = cpuIdlePercent
        self.memoryUsedPercent = memoryUsedPercent
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.memoryPressureLevel = memoryPressureLevel
        self.diskUsedPercent = diskUsedPercent
        self.diskFreeBytes = diskFreeBytes
        self.diskReadBytesPerSecond = diskReadBytesPerSecond
        self.diskWriteBytesPerSecond = diskWriteBytesPerSecond
        self.networkDownloadBytesPerSecond = networkDownloadBytesPerSecond
        self.networkUploadBytesPerSecond = networkUploadBytesPerSecond
        self.networkInterfaceName = networkInterfaceName
        self.availableNetworkInterfaces = availableNetworkInterfaces
        self.gpuUsage = gpuUsage
        self.gpuRendererUsage = gpuRendererUsage
        self.gpuTilerUsage = gpuTilerUsage
        self.temperatureCelsius = temperatureCelsius
        self.temperatureSource = temperatureSource
        self.batteryTemperatureCelsius = batteryTemperatureCelsius
        self.batteryTemperatureSource = batteryTemperatureSource
        self.fanRPM = fanRPM
        self.fanCount = fanCount
        self.fanSpeedsRPM = fanSpeedsRPM
        self.fanLoadPercent = fanLoadPercent
        self.batteryLevel = batteryLevel
        self.batteryStatus = batteryStatus
        self.batteryIsCharging = batteryIsCharging
        self.batteryTimeRemainingMinutes = batteryTimeRemainingMinutes
        self.thermalState = thermalState
    }

    public func value(for metric: MenuBarMetric) -> Double? {
        switch metric {
        case .cpu: return cpuUsage
        case .memory: return memoryUsedPercent
        case .temperature: return temperatureCelsius ?? batteryTemperatureCelsius
        case .network:
            guard networkDownloadBytesPerSecond != nil || networkUploadBytesPerSecond != nil else {
                return nil
            }
            return (networkDownloadBytesPerSecond ?? 0) + (networkUploadBytesPerSecond ?? 0)
        case .disk: return diskUsedPercent
        case .gpu: return gpuUsage
        case .fan: return fanRPM
        case .battery: return batteryLevel
        }
    }

    public func healthLevel(for metric: MenuBarMetric) -> NativeMetricHealthLevel {
        switch metric {
        case .memory:
            switch memoryPressureLevel {
            case .normal, .unknown: return .normal
            case .warning: return .warning
            case .critical: return .critical
            }
        case .temperature:
            return temperatureHealthLevel()
        case .disk:
            guard let diskUsedPercent else { return .normal }
            if diskUsedPercent >= 97 { return .critical }
            if diskUsedPercent >= 90 { return .warning }
            return .normal
        case .fan:
            guard fanCount.map({ $0 > 0 }) == true, fanRPM != nil else { return .normal }
            let temperatureLevel = temperatureHealthLevel()
            if temperatureLevel == .critical { return .critical }
            if temperatureLevel == .warning { return .warning }
            // Match the rounded whole-percent value shown in the UI so a visible
            // "85%" never remains unmarked because the sensor returned 84.x%.
            if let fanLoadPercent, fanLoadPercent.rounded() >= 85 { return .warning }
            if fanLoadPercent == nil, let fanRPM, fanRPM >= 5_500 { return .warning }
            return .normal
        case .battery:
            guard batteryIsCharging != true,
                  batteryStatus != "连接电源",
                  let batteryLevel else { return .normal }
            if batteryLevel <= 10 { return .critical }
            if batteryLevel <= 20 { return .warning }
            return .normal
        case .cpu, .network, .gpu:
            // High utilization or throughput is workload, not evidence of a hardware problem.
            return .normal
        }
    }

    private func temperatureHealthLevel() -> NativeMetricHealthLevel {
        var level = thermalState.healthLevel
        if let temperatureCelsius {
            if temperatureCelsius >= 95 {
                level = max(level, .critical)
            } else if temperatureCelsius >= 85 {
                level = max(level, .warning)
            }
        }
        if let batteryTemperatureCelsius {
            if batteryTemperatureCelsius >= 45 {
                level = max(level, .critical)
            } else if batteryTemperatureCelsius >= 40 {
                level = max(level, .warning)
            }
        }
        return level
    }
}

public struct NativeCPUUsageBreakdown: Equatable, Sendable {
    public let total: Double
    public let user: Double
    public let system: Double
    public let idle: Double
}

public struct NativeCPUTicks: Equatable, Sendable {
    public let user: UInt64
    public let system: UInt64
    public let idle: UInt64
    public let nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

public enum NativeMonitorMath {
    public static func cpuBreakdown(
        previous: NativeCPUTicks,
        current: NativeCPUTicks
    ) -> NativeCPUUsageBreakdown? {
        guard current.user >= previous.user,
              current.system >= previous.system,
              current.idle >= previous.idle,
              current.nice >= previous.nice else { return nil }

        let user = (current.user - previous.user) + (current.nice - previous.nice)
        let system = current.system - previous.system
        let idle = current.idle - previous.idle
        let total = user + system + idle
        guard total > 0 else { return nil }
        let scale = 100 / Double(total)
        return NativeCPUUsageBreakdown(
            total: min(100, max(0, Double(user + system) * scale)),
            user: min(100, max(0, Double(user) * scale)),
            system: min(100, max(0, Double(system) * scale)),
            idle: min(100, max(0, Double(idle) * scale))
        )
    }

    public static func cpuUsage(
        previous: NativeCPUTicks,
        current: NativeCPUTicks
    ) -> Double? {
        cpuBreakdown(previous: previous, current: current)?.total
    }

    public static func bytesPerSecond(
        previousBytes: UInt64,
        currentBytes: UInt64,
        elapsed: TimeInterval
    ) -> Double? {
        guard elapsed > 0, currentBytes >= previousBytes else { return nil }
        return Double(currentBytes - previousBytes) / elapsed
    }
}

public actor NativeSystemMonitor {
    private struct NetworkCounters {
        let sampledAt: Date
        let signature: String
        let interfaceName: String
        let availableInterfaces: [String]
        let downloadBytes: UInt64
        let uploadBytes: UInt64
    }

    private struct DiskCounters {
        let sampledAt: Date
        let readBytes: UInt64
        let writeBytes: UInt64
    }

    private var previousCPUTicks: NativeCPUTicks?
    private var previousNetworkCounters: NetworkCounters?
    private var previousDiskCounters: DiskCounters?
    private let smc: ReadOnlyAppleSMC?
    private var workingTemperatureKeys: [String]?
    private var cachedFanCount: Int?

    public init() {
        smc = ReadOnlyAppleSMC()
    }

    public func sample(
        at sampledAt: Date = Date(),
        configuration: MenuBarMonitorConfiguration = .defaults
    ) -> NativeMonitorSample {
        let currentTicks = Self.cpuTicks()
        let cpu: NativeCPUUsageBreakdown?
        if let previousCPUTicks, let currentTicks {
            cpu = NativeMonitorMath.cpuBreakdown(previous: previousCPUTicks, current: currentTicks)
        } else {
            cpu = nil
        }
        if let currentTicks { previousCPUTicks = currentTicks }

        let memory = Self.memorySample()
        let disk = Self.diskSample()
        let diskThroughput = diskThroughputSample(at: sampledAt)
        let gpu = Self.gpuSample()
        let network = networkSample(at: sampledAt, configuration: configuration)
        let temperature = temperatureSample()
        let batteryTemperature = Self.batteryTemperatureSample()
        let fan = fanSample()
        let battery = Self.batterySample()
        let thermalState = Self.thermalState()

        return NativeMonitorSample(
            sampledAt: sampledAt,
            cpuUsage: cpu?.total,
            cpuUserPercent: cpu?.user,
            cpuSystemPercent: cpu?.system,
            cpuIdlePercent: cpu?.idle,
            memoryUsedPercent: memory?.usedPercent,
            memoryUsedBytes: memory?.usedBytes,
            memoryTotalBytes: memory?.totalBytes,
            memoryPressureLevel: memory?.pressure ?? .unknown,
            diskUsedPercent: disk?.usedPercent,
            diskFreeBytes: disk?.freeBytes,
            diskReadBytesPerSecond: diskThroughput.read,
            diskWriteBytesPerSecond: diskThroughput.write,
            networkDownloadBytesPerSecond: network.download,
            networkUploadBytesPerSecond: network.upload,
            networkInterfaceName: network.interfaceName,
            availableNetworkInterfaces: network.availableInterfaces,
            gpuUsage: gpu.usage,
            gpuRendererUsage: gpu.renderer,
            gpuTilerUsage: gpu.tiler,
            temperatureCelsius: temperature.value,
            temperatureSource: temperature.source,
            batteryTemperatureCelsius: batteryTemperature.value,
            batteryTemperatureSource: batteryTemperature.source,
            fanRPM: fan.rpm,
            fanCount: fan.count,
            fanSpeedsRPM: fan.speeds,
            fanLoadPercent: fan.loadPercent,
            batteryLevel: battery.level,
            batteryStatus: battery.status,
            batteryIsCharging: battery.isCharging,
            batteryTimeRemainingMinutes: battery.timeRemainingMinutes,
            thermalState: thermalState
        )
    }

    private static func thermalState() -> NativeThermalState {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .unknown
        }
    }

    private static func cpuTicks() -> NativeCPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return NativeCPUTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }

    private static func memorySample() -> (
        usedPercent: Double,
        usedBytes: Int64,
        totalBytes: Int64,
        pressure: MemoryPressureLevel
    )? {
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
        let total = ProcessInfo.processInfo.physicalMemory
        guard total > 0 else { return nil }

        // Active + wired + compressed is a stable, local approximation of memory
        // that is not immediately reclaimable. Inactive/cache pages are excluded.
        let pages = UInt64(statistics.active_count)
            + UInt64(statistics.wire_count)
            + UInt64(statistics.compressor_page_count)
        let (rawUsed, overflowed) = pages.multipliedReportingOverflow(by: UInt64(pageSize))
        let boundedUsed = min(total, overflowed ? total : rawUsed)
        let used = Int64(clamping: boundedUsed)
        let totalBytes = Int64(clamping: total)
        let pressure = SystemMemoryProbe.sample().pressureLevel
        return (
            Double(boundedUsed) / Double(total) * 100,
            used,
            totalBytes,
            pressure
        )
    }

    private static func diskSample() -> (usedPercent: Double, freeBytes: Int64)? {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
              let size = (attributes[.systemSize] as? NSNumber)?.int64Value,
              let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value,
              size > 0 else { return nil }
        let used = max(0, size - max(0, free))
        return (Double(used) / Double(size) * 100, free)
    }

    private func diskThroughputSample(at sampledAt: Date) -> (read: Double?, write: Double?) {
        guard let currentValues = Self.diskCounters() else {
            previousDiskCounters = nil
            return (nil, nil)
        }
        let current = DiskCounters(
            sampledAt: sampledAt,
            readBytes: currentValues.read,
            writeBytes: currentValues.write
        )
        defer { previousDiskCounters = current }
        guard let previousDiskCounters else { return (0, 0) }
        let elapsed = sampledAt.timeIntervalSince(previousDiskCounters.sampledAt)
        return (
            NativeMonitorMath.bytesPerSecond(
                previousBytes: previousDiskCounters.readBytes,
                currentBytes: current.readBytes,
                elapsed: elapsed
            ),
            NativeMonitorMath.bytesPerSecond(
                previousBytes: previousDiskCounters.writeBytes,
                currentBytes: current.writeBytes,
                elapsed: elapsed
            )
        )
    }

    private static func diskCounters() -> (read: UInt64, write: UInt64)? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOBlockStorageDriver"),
            &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0
        var write: UInt64 = 0
        var found = false
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let statistics = IORegistryEntryCreateCFProperty(
                service,
                "Statistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any] {
                if let value = statistics["Bytes (Read)"] as? NSNumber {
                    read &+= value.uint64Value
                    found = true
                }
                if let value = statistics["Bytes (Write)"] as? NSNumber {
                    write &+= value.uint64Value
                    found = true
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return found ? (read, write) : nil
    }

    private func networkSample(
        at sampledAt: Date,
        configuration: MenuBarMonitorConfiguration
    ) -> (
        download: Double?,
        upload: Double?,
        interfaceName: String?,
        availableInterfaces: [String]
    ) {
        guard let current = Self.networkCounters(
            at: sampledAt,
            mode: configuration.networkMode,
            selectedInterface: configuration.selectedNetworkInterface
        ) else {
            previousNetworkCounters = nil
            return (nil, nil, nil, Self.availableNetworkInterfaceNames())
        }
        defer { previousNetworkCounters = current }
        guard let previousNetworkCounters,
              previousNetworkCounters.signature == current.signature else {
            return (0, 0, current.interfaceName, current.availableInterfaces)
        }
        let elapsed = current.sampledAt.timeIntervalSince(previousNetworkCounters.sampledAt)
        return (
            NativeMonitorMath.bytesPerSecond(
                previousBytes: previousNetworkCounters.downloadBytes,
                currentBytes: current.downloadBytes,
                elapsed: elapsed
            ),
            NativeMonitorMath.bytesPerSecond(
                previousBytes: previousNetworkCounters.uploadBytes,
                currentBytes: current.uploadBytes,
                elapsed: elapsed
            ),
            current.interfaceName,
            current.availableInterfaces
        )
    }

    private static func networkCounters(
        at sampledAt: Date,
        mode: MenuBarNetworkMode,
        selectedInterface: String?
    ) -> NetworkCounters? {
        let preferredInterface = primaryNetworkInterface()
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }

        var countersByName: [String: (download: UInt64, upload: UInt64)] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let address = cursor {
            defer { cursor = address.pointee.ifa_next }
            guard let socketAddress = address.pointee.ifa_addr,
                  Int32(socketAddress.pointee.sa_family) == AF_LINK,
                  let rawData = address.pointee.ifa_data else { continue }
            let name = String(cString: address.pointee.ifa_name)
            let flags = Int32(address.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            let data = rawData.assumingMemoryBound(to: if_data.self).pointee
            countersByName[name] = (
                UInt64(data.ifi_ibytes),
                UInt64(data.ifi_obytes)
            )
        }
        let available = countersByName.keys.sorted()
        guard !available.isEmpty else { return nil }

        let selectedNames: [String]
        switch mode {
        case .automatic:
            if let preferredInterface, countersByName[preferredInterface] != nil {
                selectedNames = [preferredInterface]
            } else if let fallback = available.first(where: { $0.hasPrefix("en") }) {
                selectedNames = [fallback]
            } else {
                selectedNames = [available[0]]
            }
        case .physicalAggregate:
            let physical = available.filter(isPhysicalNetworkInterface)
            if !physical.isEmpty {
                selectedNames = physical
            } else if let preferredInterface, countersByName[preferredInterface] != nil {
                selectedNames = [preferredInterface]
            } else {
                selectedNames = [available[0]]
            }
        case .specific:
            if let selectedInterface, countersByName[selectedInterface] != nil {
                selectedNames = [selectedInterface]
            } else {
                return nil
            }
        }

        let totals = selectedNames.reduce(into: (download: UInt64(0), upload: UInt64(0))) {
            partial, name in
            guard let value = countersByName[name] else { return }
            partial.download &+= value.download
            partial.upload &+= value.upload
        }
        let label = selectedNames.count == 1
            ? selectedNames[0]
            : selectedNames.joined(separator: " + ")
        return NetworkCounters(
            sampledAt: sampledAt,
            signature: mode.rawValue + ":" + selectedNames.joined(separator: ","),
            interfaceName: label,
            availableInterfaces: available,
            downloadBytes: totals.download,
            uploadBytes: totals.upload
        )
    }

    private static func availableNetworkInterfaceNames() -> [String] {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return [] }
        defer { freeifaddrs(addresses) }
        var result = Set<String>()
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let address = cursor {
            defer { cursor = address.pointee.ifa_next }
            guard let socketAddress = address.pointee.ifa_addr,
                  Int32(socketAddress.pointee.sa_family) == AF_LINK else { continue }
            let flags = Int32(address.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            result.insert(String(cString: address.pointee.ifa_name))
        }
        return result.sorted()
    }

    private static func isPhysicalNetworkInterface(_ name: String) -> Bool {
        name.hasPrefix("en") || name.hasPrefix("pdp_ip")
    }

    private static func primaryNetworkInterface() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "CleanNestMonitor" as CFString, nil, nil),
              let value = SCDynamicStoreCopyValue(
                store,
                "State:/Network/Global/IPv4" as CFString
              ) as? [String: Any] else { return nil }
        return value["PrimaryInterface"] as? String
    }

    private static func gpuSample() -> (usage: Double?, renderer: Double?, tiler: Double?) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iterator
        ) == KERN_SUCCESS else { return (nil, nil, nil) }
        defer { IOObjectRelease(iterator) }

        var usageValues: [Double] = []
        var rendererValues: [Double] = []
        var tilerValues: [Double] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let property = IORegistryEntryCreateCFProperty(
                service,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any] {
                if let value = number(in: property, keys: ["Device Utilization %", "GPU Activity(%)"]) {
                    usageValues.append(value)
                }
                if let value = number(in: property, keys: ["Renderer Utilization %"]) {
                    rendererValues.append(value)
                }
                if let value = number(in: property, keys: ["Tiler Utilization %"]) {
                    tilerValues.append(value)
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return (
            usageValues.max().map(clampedPercent),
            rendererValues.max().map(clampedPercent),
            tilerValues.max().map(clampedPercent)
        )
    }

    private static func number(in dictionary: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = dictionary[key] as? NSNumber { return value.doubleValue }
        }
        return nil
    }

    private static func clampedPercent(_ value: Double) -> Double {
        min(100, max(0, value))
    }

    private func temperatureSample() -> (value: Double?, source: String?) {
        guard let smc else { return (nil, nil) }
        let keys = workingTemperatureKeys ?? Self.temperatureKeysForCurrentProcessor()
        var values: [(String, Double)] = []
        for key in keys {
            if let value = smc.value(for: key), (10...120).contains(value) {
                values.append((key, value))
            }
        }
        if workingTemperatureKeys == nil, !values.isEmpty {
            workingTemperatureKeys = values.map(\.0)
        }
        guard !values.isEmpty else { return (nil, nil) }
        return (
            values.map(\.1).reduce(0, +) / Double(values.count),
            "AppleSMC CPU 核心"
        )
    }

    private func fanSample() -> (
        rpm: Double?,
        count: Int?,
        speeds: [Double],
        loadPercent: Double?
    ) {
        guard let smc else { return (nil, nil, [], nil) }
        let count: Int
        if let cachedFanCount {
            count = cachedFanCount
        } else if let reported = smc.value(for: "FNum"), reported >= 0, reported <= 16 {
            count = Int(reported.rounded())
            cachedFanCount = count
        } else {
            let probed = (0..<4).filter { smc.value(for: "F\($0)Ac") != nil }.count
            guard probed > 0 else { return (nil, nil, [], nil) }
            count = probed
            cachedFanCount = count
        }
        guard count > 0 else { return (nil, 0, [], nil) }
        var speeds: [Double] = []
        var loads: [Double] = []
        for index in 0..<count {
            guard let actual = smc.value(for: "F\(index)Ac"),
                  actual >= 0,
                  actual < 20_000 else { continue }
            speeds.append(actual)
            if let maximum = smc.value(for: "F\(index)Mx"), maximum > 0, maximum < 20_000 {
                loads.append(min(100, max(0, actual / maximum * 100)))
            }
        }
        return (speeds.max(), count, speeds, loads.max())
    }

    private static func batterySample() -> (
        level: Double?,
        status: String?,
        isCharging: Bool?,
        timeRemainingMinutes: Int?
    ) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return (nil, nil, nil, nil) }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(
                info,
                source
            )?.takeUnretainedValue() as? [String: Any],
                  (description["Type"] as? String) == "InternalBattery"
            else { continue }

            let current = (description["Current Capacity"] as? NSNumber)?.doubleValue
            let maximum = (description["Max Capacity"] as? NSNumber)?.doubleValue
            let level: Double?
            if let current, let maximum, maximum > 0 {
                level = min(100, max(0, current / maximum * 100))
            } else {
                level = nil
            }
            let charging = (description["Is Charging"] as? NSNumber)?.boolValue
            let state = description["Power Source State"] as? String
            let status: String?
            if charging == true {
                status = "正在充电"
            } else if state == "AC Power" {
                status = "连接电源"
            } else if state == "Battery Power" {
                status = "使用电池"
            } else {
                status = state
            }
            let rawMinutes: Int?
            if charging == true {
                rawMinutes = (description["Time to Full Charge"] as? NSNumber)?.intValue
            } else {
                rawMinutes = (description["Time to Empty"] as? NSNumber)?.intValue
            }
            let minutes = rawMinutes.flatMap { $0 > 0 ? $0 : nil }
            return (level, status, charging, minutes)
        }
        return (nil, "这台 Mac 没有内置电池", nil, nil)
    }

    private static func batteryTemperatureSample() -> (value: Double?, source: String?) {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else { return (nil, nil) }
        defer { IOObjectRelease(service) }
        guard let property = IORegistryEntryCreateCFProperty(
            service,
            "Temperature" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? NSNumber,
              let value = normalizedBatteryTemperature(property.doubleValue) else {
            return (nil, nil)
        }
        return (value, "IOKit 电池传感器")
    }

    static func normalizedBatteryTemperature(_ rawValue: Double) -> Double? {
        guard rawValue.isFinite else { return nil }
        let value = rawValue > 120 ? rawValue / 100 : rawValue
        guard (-20...100).contains(value) else { return nil }
        return value
    }

    private static func temperatureKeysForCurrentProcessor() -> [String] {
        let brand = processorBrand().lowercased()
        if brand.contains("m5") {
            return ["Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K", "Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d", "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y"]
        }
        if brand.contains("m4") {
            return ["Te05", "Te0S", "Te09", "Te0H", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"]
        }
        if brand.contains("m3") {
            return ["Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"]
        }
        if brand.contains("m2") {
            return ["Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"]
        }
        if brand.contains("m1") {
            return ["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"]
        }
        return ["TC0D", "TC0E", "TC0F", "TC0H", "TC0P", "TCAD"]
    }

    private static func processorBrand() -> String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0,
              size > 1 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else {
            return ""
        }
        return String(cString: buffer)
    }
}

// Read-only AppleSMC access. The struct layout and decoding strategy are adapted
// from the MIT-licensed Stats project by Serhiy Mytrovtsiy. CleanNest deliberately
// contains no SMC write method and cannot control fan modes or fan speed.
private final class ReadOnlyAppleSMC {
    private enum Command: UInt8 {
        case kernelIndex = 2
        case readBytes = 5
        case readKeyInfo = 9
    }

    private struct KeyData {
        typealias Bytes = (
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
        )

        struct Version {
            var major: UInt8 = 0
            var minor: UInt8 = 0
            var build: UInt8 = 0
            var reserved: UInt8 = 0
            var release: UInt16 = 0
        }

        struct LimitData {
            var version: UInt16 = 0
            var length: UInt16 = 0
            var cpuPLimit: UInt32 = 0
            var gpuPLimit: UInt32 = 0
            var memPLimit: UInt32 = 0
        }

        struct KeyInfo {
            var dataSize: IOByteCount32 = 0
            var dataType: UInt32 = 0
            var dataAttributes: UInt8 = 0
        }

        var key: UInt32 = 0
        var version = Version()
        var limitData = LimitData()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes = (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    private var connection: io_connect_t = 0

    init?() {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else {
            return nil
        }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    func value(for key: String) -> Double? {
        guard key.utf8.count == 4 else { return nil }
        var input = KeyData()
        var output = KeyData()
        input.key = Self.fourCC(key)
        input.data8 = Command.readKeyInfo.rawValue
        guard call(input: &input, output: &output) == KERN_SUCCESS else { return nil }

        let dataSize = Int(output.keyInfo.dataSize)
        guard dataSize > 0, dataSize <= 32 else { return nil }
        let dataType = Self.fourCCString(output.keyInfo.dataType)
        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = Command.readBytes.rawValue
        guard call(input: &input, output: &output) == KERN_SUCCESS else { return nil }
        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(dataSize)) }
        guard bytes.contains(where: { $0 != 0 }) || key == "FNum" else { return nil }

        switch dataType {
        case "ui8 ":
            return Double(bytes[0])
        case "ui16" where bytes.count >= 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32" where bytes.count >= 4:
            let value = UInt32(bytes[0]) << 24
                | UInt32(bytes[1]) << 16
                | UInt32(bytes[2]) << 8
                | UInt32(bytes[3])
            return Double(value)
        case "sp78" where bytes.count >= 2:
            let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(raw) / 256
        case "fpe2" where bytes.count >= 2:
            return Double((Int(bytes[0]) << 6) + (Int(bytes[1]) >> 2))
        case "flt " where bytes.count >= 4:
            var value: Float = 0
            withUnsafeMutableBytes(of: &value) { destination in
                destination.copyBytes(from: bytes.prefix(4))
            }
            return value.isFinite ? Double(value) : nil
        default:
            return nil
        }
    }

    private func call(input: inout KeyData, output: inout KeyData) -> kern_return_t {
        let inputSize = MemoryLayout<KeyData>.stride
        var outputSize = MemoryLayout<KeyData>.stride
        return IOConnectCallStructMethod(
            connection,
            UInt32(Command.kernelIndex.rawValue),
            &input,
            inputSize,
            &output,
            &outputSize
        )
    }

    private static func fourCC(_ value: String) -> UInt32 {
        value.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func fourCCString(_ value: UInt32) -> String {
        String(bytes: [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ], encoding: .ascii) ?? ""
    }
}
