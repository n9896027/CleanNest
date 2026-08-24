import Foundation

public enum BatteryAvailability: String, Codable, Equatable, Sendable {
    case present
    case noInternalBattery
    case unreadable
}

public struct BatteryProbeResult: Equatable, Sendable {
    public let availability: BatteryAvailability
    public let level: Double?
    public let status: String
    public let detail: String

    public init(
        availability: BatteryAvailability,
        level: Double?,
        status: String,
        detail: String
    ) {
        self.availability = availability
        self.level = level
        self.status = status
        self.detail = detail
    }
}

public enum PowerSourceProbe {
    public static func sample() -> BatteryProbeResult {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "batt"]
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
            process.waitUntilExit()
            let standardOutput = String(
                decoding: output.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
            let standardError = String(
                decoding: error.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
            return interpret(
                output: standardOutput,
                error: standardError,
                exitCode: process.terminationStatus
            )
        } catch {
            return BatteryProbeResult(
                availability: .unreadable,
                level: nil,
                status: "电池读取失败",
                detail: "系统电源工具未能启动：\(error.localizedDescription)。这不是完全磁盘访问权限问题。"
            )
        }
    }

    public static func interpret(
        output: String,
        error: String = "",
        exitCode: Int32 = 0
    ) -> BatteryProbeResult {
        guard exitCode == 0 else {
            let detail = error.trimmingCharacters(in: .whitespacesAndNewlines)
            return BatteryProbeResult(
                availability: .unreadable,
                level: nil,
                status: "电池读取失败",
                detail: detail.isEmpty
                    ? "系统电源工具返回状态 \(exitCode)。这通常不是文件访问权限问题。"
                    : "系统电源工具返回：\(String(detail.prefix(240)))"
            )
        }

        let normalized = output.lowercased()
        let hasBattery = normalized.contains("internalbattery")
            || normalized.contains("apple smart battery")
        guard hasBattery else {
            return BatteryProbeResult(
                availability: .noInternalBattery,
                level: nil,
                status: "没有内置电池",
                detail: "系统没有检测到内置电池。台式 Mac 显示这一状态是正常情况，不需要授予文件访问权限。"
            )
        }

        let level = firstBatteryPercentage(in: output)
        let status: String
        if normalized.contains("discharging") {
            status = "使用电池"
        } else if normalized.contains("finishing charge") {
            status = "即将充满"
        } else if normalized.contains("charging") {
            status = "正在充电"
        } else if normalized.contains("charged") {
            status = "已充满"
        } else if normalized.contains("ac attached") || normalized.contains("ac power") {
            status = "已连接电源"
        } else {
            status = "检测到电池"
        }
        return BatteryProbeResult(
            availability: .present,
            level: level,
            status: status,
            detail: level.map { "系统电源接口检测到内置电池，当前电量 \(Int($0.rounded()))%。" }
                ?? "系统电源接口检测到内置电池，但本次没有读到电量百分比。"
        )
    }

    private static func firstBatteryPercentage(in value: String) -> Double? {
        guard let expression = try? NSRegularExpression(pattern: #"\b(\d{1,3})%"#) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = expression.firstMatch(in: value, range: range),
              let capture = Range(match.range(at: 1), in: value),
              let percentage = Double(value[capture]),
              (0...100).contains(percentage) else { return nil }
        return percentage
    }
}
