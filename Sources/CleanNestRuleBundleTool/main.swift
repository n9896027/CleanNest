import Foundation
import CleanNestCore

enum RuleBundleToolError: LocalizedError {
    case usage
    case invalidDestination
    case destinationExists
    case signingFailed(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "用法：CleanNestRuleBundleTool <输出.bundle> --sign <代码签名身份>"
        case .invalidDestination:
            return "输出必须是尚不存在的绝对 .bundle 路径。"
        case .destinationExists:
            return "输出位置已存在；工具不会覆盖已有规则包。"
        case .signingFailed(let detail):
            return "规则包签名失败：\(detail)"
        }
    }
}

@main
struct CleanNestRuleBundleTool {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 3,
              arguments[1] == "--sign",
              !arguments[2].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RuleBundleToolError.usage
        }
        let destination = URL(fileURLWithPath: arguments[0], isDirectory: true).standardizedFileURL
        guard (arguments[0] as NSString).isAbsolutePath,
              destination.pathExtension.lowercased() == "bundle",
              destination.deletingLastPathComponent().path != "/" else {
            throw RuleBundleToolError.invalidDestination
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw RuleBundleToolError.destinationExists
        }

        let contents = destination.appendingPathComponent("Contents", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: resources,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o755)]
            )
            let catalog = AgentRuleCatalog.builtIn
            try catalog.validate()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(catalog)
            try data.write(
                to: resources.appendingPathComponent("AgentRules.json"),
                options: [.atomic]
            )

            let plist: [String: Any] = [
                "CFBundleIdentifier": "com.zone.cleannest.agentrules",
                "CFBundleName": "CleanNest Agent Rules",
                "CFBundlePackageType": "BNDL",
                "CFBundleShortVersionString": catalog.revision,
                "CFBundleVersion": "1"
            ]
            let plistData = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            try plistData.write(to: contents.appendingPathComponent("Info.plist"), options: [.atomic])

            try sign(destination, identity: arguments[2])
            print("已生成并签名：\(destination.path)")
            print("规则修订：\(catalog.revision)")
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private static func sign(_ bundle: URL, identity: String) throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = [
            "--force",
            "--options", "runtime",
            "--timestamp",
            "--sign", identity,
            bundle.path
        ]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw RuleBundleToolError.signingFailed(
                String(data: data, encoding: .utf8) ?? "codesign 状态 \(process.terminationStatus)"
            )
        }
    }
}
