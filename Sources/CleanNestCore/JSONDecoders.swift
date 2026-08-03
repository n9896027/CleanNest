import Foundation

private struct JSONReader {
    let object: [String: Any]

    func dictionary(_ keys: String...) -> [String: Any]? {
        for key in keys {
            if let value = object[key] as? [String: Any] { return value }
        }
        return nil
    }

    func array(_ keys: String...) -> [[String: Any]]? {
        for key in keys {
            if let value = object[key] as? [[String: Any]] { return value }
        }
        return nil
    }

    func string(_ keys: String...) -> String? {
        for key in keys {
            if let value = object[key] as? String { return value }
        }
        return nil
    }

    func double(_ keys: String...) -> Double? {
        for key in keys {
            if let value = object[key] as? NSNumber { return value.doubleValue }
            if let value = object[key] as? String, let number = Double(value) { return number }
        }
        return nil
    }

    func int(_ keys: String...) -> Int? {
        guard let value = double(keys) else { return nil }
        return Int(value.rounded())
    }

    func int64(_ keys: String...) -> Int64? {
        double(keys).flatMap { Int64($0) }
    }

    private func double(_ keys: [String]) -> Double? {
        for key in keys {
            if let value = object[key] as? NSNumber { return value.doubleValue }
            if let value = object[key] as? String, let number = Double(value) { return number }
        }
        return nil
    }
}

public enum MoleJSONDecoder {
    public static func systemSnapshot(
        from data: Data,
        memoryProbe: SystemMemoryProbeSnapshot? = nil
    ) throws -> SystemSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }

        let reader = JSONReader(object: root)
        let cpu = JSONReader(object: reader.dictionary("cpu") ?? [:])
        let memory = JSONReader(object: reader.dictionary("memory") ?? [:])
        let batteryObject = reader.array("batteries")?.first
            ?? reader.dictionary("battery", "power")
            ?? [:]
        let battery = JSONReader(object: batteryObject)
        let thermal = JSONReader(object: reader.dictionary("thermal", "temperature") ?? [:])

        let diskObject = reader.dictionary("disk")
            ?? reader.array("disks")?.first
            ?? [:]
        let disk = JSONReader(object: diskObject)

        let reportedPressure = MemoryPressureLevel(reportedValue: memory.string("pressure"))
        let pressure = memoryProbe?.pressureLevel == .unknown
            ? reportedPressure
            : memoryProbe?.pressureLevel ?? reportedPressure
        let temperature = preferredTemperature(thermal: thermal, battery: battery)

        return SystemSnapshot(
            host: reader.string("host", "hostname") ?? Host.current().localizedName ?? "这台 Mac",
            healthScore: reader.int("health_score", "healthScore"),
            cpuUsage: cpu.double("usage", "usage_percent", "total"),
            logicalCPUCount: cpu.int("logical_cpu", "logicalCPU", "cores"),
            memoryUsedBytes: memory.int64("used", "used_bytes"),
            memoryTotalBytes: memory.int64("total", "total_bytes"),
            memoryUsedPercent: memory.double("used_percent", "usage_percent", "percent"),
            memoryAvailableBytes: memory.int64("available", "available_bytes"),
            memoryCachedBytes: memory.int64("cached", "cache", "cached_bytes"),
            memoryCompressedBytes: memoryProbe?.compressedBytes,
            memorySwapUsedBytes: memory.int64("swap_used", "swapUsed", "swap_used_bytes"),
            memorySwapTotalBytes: memory.int64("swap_total", "swapTotal", "swap_total_bytes"),
            memoryPressureLevel: pressure,
            processCount: reader.int("procs", "process_count", "processes"),
            diskUsedPercent: disk.double("used_percent", "usage_percent", "percent"),
            diskFreeBytes: disk.int64("free", "free_bytes", "available"),
            batteryLevel: battery.double("level", "percent", "charge"),
            batteryStatus: batteryStatusSummary(battery),
            temperatureCelsius: temperature.value,
            temperatureSource: temperature.source,
            uptime: reader.string("uptime")
        )
    }

    private static func batteryStatusSummary(_ battery: JSONReader) -> String? {
        var parts: [String] = []

        if let rawState = battery.string("status", "state")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawState.isEmpty {
            let normalized = rawState.lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
            switch normalized {
            case "ac", "ac power", "plugged", "external power":
                parts.append("已连接电源")
            case "charging":
                parts.append("正在充电")
            case "battery", "discharging", "on battery":
                parts.append("使用电池")
            case "charged", "full", "fully charged":
                parts.append("已充满")
            case "not charging":
                parts.append("已连接电源，暂未充电")
            case "finishing charge":
                parts.append("即将充满")
            case "unknown":
                parts.append("供电状态未知")
            default:
                parts.append(rawState)
            }
        }

        if let rawHealth = battery.string("health", "condition")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawHealth.isEmpty {
            switch rawHealth.lowercased() {
            case "good", "normal":
                parts.append("健康良好")
            case "fair":
                parts.append("健康一般")
            case "poor", "bad":
                parts.append("健康较差")
            case "service recommended", "service", "check battery":
                parts.append("建议检修")
            default:
                parts.append("健康状态：\(rawHealth)")
            }
        }

        if let capacity = battery.int("capacity", "maximum_capacity", "maximumCapacity"),
           (1...100).contains(capacity) {
            parts.append("最大容量 \(capacity)%")
        }
        if let cycles = battery.int("cycle_count", "cycleCount", "cycles"), cycles >= 0 {
            parts.append("\(cycles) 次循环")
        }
        if let timeLeft = battery.string("time_left", "timeLeft")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !timeLeft.isEmpty,
           timeLeft != "0" {
            parts.append("预计剩余 \(timeLeft)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func preferredTemperature(
        thermal: JSONReader,
        battery: JSONReader
    ) -> (value: Double?, source: String?) {
        let candidates: [(Double?, String)] = [
            (thermal.double("celsius", "temperature"), "设备温度"),
            (thermal.double("cpu", "cpu_temp"), "CPU 温度"),
            (thermal.double("gpu", "gpu_temp"), "GPU 温度"),
            (thermal.double("battery", "battery_temp"), "电池温度"),
            (battery.double("temperature", "temp"), "电池温度")
        ]
        guard let match = candidates.first(where: {
            guard let value = $0.0 else { return false }
            return value > 0 && value < 150
        }) else {
            return (nil, nil)
        }
        return (match.0, match.1)
    }

    public static func diskReport(from data: Data, fallbackRoot: URL) throws -> DiskReport {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        let reader = JSONReader(object: root)

        func entries(from objects: [[String: Any]]?) -> [DiskEntry] {
            (objects ?? []).compactMap { item in
                let itemReader = JSONReader(object: item)
                guard let path = itemReader.string("path") else { return nil }
                let url = URL(fileURLWithPath: path)
                return DiskEntry(
                    name: itemReader.string("name") ?? url.lastPathComponent,
                    url: url,
                    bytes: itemReader.int64("size", "bytes", "allocated_bytes") ?? 0,
                    isDirectory: (item["is_dir"] as? Bool) ?? (item["isDirectory"] as? Bool) ?? false
                )
            }
        }

        let reportRoot = reader.string("path").map(URL.init(fileURLWithPath:)) ?? fallbackRoot
        let rows = entries(from: reader.array("entries"))
            .sorted { $0.bytes > $1.bytes }
        let largeFiles = entries(from: reader.array("large_files", "largeFiles"))
            .sorted { $0.bytes > $1.bytes }

        return DiskReport(
            root: reportRoot,
            entries: rows,
            largeFiles: largeFiles,
            totalBytes: reader.int64("total_size", "totalBytes", "size") ?? rows.reduce(0) { $0 + $1.bytes },
            totalFiles: reader.int("total_files", "totalFiles") ?? 0
        )
    }
}
