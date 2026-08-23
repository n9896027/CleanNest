import Foundation

/// Localizes dynamic UI labels while preserving runtime data and unknown keys.
/// SwiftUI already localizes string literals; shared components receive String,
/// so they use this bridge to participate in the same String Catalog.
enum CNL10n {
    static func string(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: arguments)
    }

    static func metricsDiagnostic(_ value: String) -> String {
        let retentionPrefix = "每 60 秒本机采样；保留 "
        let retentionSuffix = " 天，不上传。"
        if value.hasPrefix(retentionPrefix), value.hasSuffix(retentionSuffix) {
            let rawDays = value.dropFirst(retentionPrefix.count).dropLast(retentionSuffix.count)
            if let days = Int(rawDays) {
                return format("每 60 秒本机采样；保留 %d 天，不上传。", days)
            }
        }

        let pointsPrefix = "每 60 秒本机采样；当前显示 "
        let pointsSuffix = " 个数据点。"
        if value.hasPrefix(pointsPrefix), value.hasSuffix(pointsSuffix) {
            let rawCount = value.dropFirst(pointsPrefix.count).dropLast(pointsSuffix.count)
            if let count = Int(rawCount) {
                return format("每 60 秒本机采样；当前显示 %d 个数据点。", count)
            }
        }

        return string(value)
    }

    static func batteryStatus(_ value: String) -> String {
        value.split(separator: "·").map { rawPart in
            let part = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
            if part.hasPrefix("最大容量 "), part.hasSuffix("%"),
               let capacity = Int(part.dropFirst("最大容量 ".count).dropLast()) {
                return format("最大容量 %d%%", capacity)
            }
            if part.hasSuffix(" 次循环"),
               let cycles = Int(part.dropLast(" 次循环".count)) {
                return format("%d 次循环", cycles)
            }
            if part.hasPrefix("预计剩余 ") {
                return format("预计剩余 %@", String(part.dropFirst("预计剩余 ".count)))
            }
            return string(part)
        }.joined(separator: " · ")
    }

    static func memoryAnalysisText(_ value: String) -> String {
        let compressedPrefix = "压缩内存约 "
        let compressedSuffix = "：这是系统压缩暂时不用的数据，不是可以删除的文件缓存。"
        if value.hasPrefix(compressedPrefix), value.hasSuffix(compressedSuffix) {
            let amount = value.dropFirst(compressedPrefix.count).dropLast(compressedSuffix.count)
            return format("压缩内存约 %@：这是系统压缩暂时不用的数据，不是可以删除的文件缓存。", String(amount))
        }

        let swapPrefix = "交换空间已使用 "
        let swapSuffix = "；单次看到已有占用不代表此刻仍在频繁交换，应结合压力状态和持续卡顿判断。"
        if value.hasPrefix(swapPrefix), value.hasSuffix(swapSuffix) {
            let amount = value.dropFirst(swapPrefix.count).dropLast(swapSuffix.count)
            return format("交换空间已使用 %@；单次看到已有占用不代表此刻仍在频繁交换，应结合压力状态和持续卡顿判断。", String(amount))
        }

        let topPrefix = "本次单个内存足迹最高的是 "
        let topSeparator = "，约 "
        let topSuffix = "；可刷新后观察是否持续增长。"
        if value.hasPrefix(topPrefix), value.hasSuffix(topSuffix) {
            let body = value.dropFirst(topPrefix.count).dropLast(topSuffix.count)
            if let separatorRange = body.range(of: topSeparator) {
                let name = String(body[..<separatorRange.lowerBound])
                let amount = String(body[separatorRange.upperBound...])
                return format("本次单个内存足迹最高的是 %@，约 %@；可刷新后观察是否持续增长。", name, amount)
            }
        }

        return string(value)
    }

    static func processPurpose(_ value: String) -> String {
        let helperSuffix = "”的辅助进程；未读取命令行参数，无法确认更具体的职责。"
        if value.hasPrefix("“"), value.hasSuffix(helperSuffix) {
            let name = value.dropFirst().dropLast(helperSuffix.count)
            return format("“%@”的辅助进程；未读取命令行参数，无法确认更具体的职责。", String(name))
        }

        let appSuffix = "”的应用进程。"
        if value.hasPrefix("“"), value.hasSuffix(appSuffix) {
            let name = value.dropFirst().dropLast(appSuffix.count)
            return format("“%@”的应用进程。", String(name))
        }

        return string(value)
    }
}
