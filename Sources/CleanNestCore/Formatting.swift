import Foundation

public enum CleanNestFormatting {
    public static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: max(0, value))
    }

    public static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f%%", value)
    }

    public static func age(from date: Date?, relativeTo now: Date = Date()) -> String {
        guard let date else { return "时间未知" }
        let interval = max(0, now.timeIntervalSince(date))
        let days = Int(interval / 86_400)
        if days == 0 { return "今天" }
        if days < 30 { return "\(days) 天前" }
        if days < 365 { return "\(days / 30) 个月前" }
        return "\(days / 365) 年前"
    }
}

/// 单一版本来源：App、扫描服务、登录项与 MCP 的用户可见版本号。
/// 发版时同步更新此处与三份 Resources/*Info.plist。
public enum CleanNestVersion {
    public static let current = "0.12.3"
    public static let build = "53"
}
