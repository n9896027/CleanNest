import Foundation

/// Maps native macOS probes to the system-status model without inventing values
/// that the platform did not provide.
public enum NativeSystemSnapshotBuilder {
    public static func makeSnapshot(
        monitor: NativeMonitorSample,
        memoryProbe: SystemMemoryProbeSnapshot?,
        batteryProbe: BatteryProbeResult?,
        processCount: Int?,
        host: String,
        logicalCPUCount: Int,
        uptimeSeconds: TimeInterval?
    ) -> SystemSnapshot {
        let memoryAvailableBytes: Int64?
        if let total = monitor.memoryTotalBytes, let used = monitor.memoryUsedBytes {
            memoryAvailableBytes = max(0, total - used)
        } else {
            memoryAvailableBytes = nil
        }

        let batteryLevel = monitor.batteryLevel
            ?? (batteryProbe?.availability == .present ? batteryProbe?.level : nil)
        let batteryStatus = monitor.batteryStatus
            ?? (batteryProbe?.availability == .present ? batteryProbe?.status : nil)
        let temperatureCelsius = monitor.temperatureCelsius ?? monitor.batteryTemperatureCelsius
        let temperatureSource = monitor.temperatureCelsius != nil
            ? monitor.temperatureSource
            : monitor.batteryTemperatureSource
        let pressureLevel = memoryProbe?.pressureLevel == .unknown || memoryProbe == nil
            ? monitor.memoryPressureLevel
            : memoryProbe?.pressureLevel ?? .unknown

        return SystemSnapshot(
            host: host,
            healthScore: nil,
            cpuUsage: monitor.cpuUsage,
            logicalCPUCount: logicalCPUCount > 0 ? logicalCPUCount : nil,
            memoryUsedBytes: monitor.memoryUsedBytes,
            memoryTotalBytes: monitor.memoryTotalBytes,
            memoryUsedPercent: monitor.memoryUsedPercent,
            memoryAvailableBytes: memoryAvailableBytes,
            memoryCachedBytes: nil,
            memoryCompressedBytes: memoryProbe?.compressedBytes,
            memorySwapUsedBytes: nil,
            memorySwapTotalBytes: nil,
            memoryPressureLevel: pressureLevel,
            processCount: processCount.flatMap { $0 >= 0 ? $0 : nil },
            diskUsedPercent: monitor.diskUsedPercent,
            diskFreeBytes: monitor.diskFreeBytes,
            batteryLevel: batteryLevel,
            batteryStatus: batteryStatus,
            temperatureCelsius: temperatureCelsius,
            temperatureSource: temperatureSource,
            uptime: uptimeSeconds.flatMap(formatUptime),
            sampledAt: monitor.sampledAt
        )
    }

    public static func formatUptime(_ seconds: TimeInterval) -> String? {
        guard seconds.isFinite, seconds >= 0 else { return nil }
        let totalMinutes = Int(seconds / 60)
        let days = totalMinutes / 1_440
        let hours = (totalMinutes % 1_440) / 60
        let minutes = totalMinutes % 60
        if days > 0 {
            return hours > 0 ? "\(days) 天 \(hours) 小时" : "\(days) 天"
        }
        if hours > 0 {
            return minutes > 0 ? "\(hours) 小时 \(minutes) 分钟" : "\(hours) 小时"
        }
        return "\(minutes) 分钟"
    }
}
