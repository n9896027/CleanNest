import Darwin
import Foundation

public enum LocalModelSupervisorKind: String, Codable, Sendable {
    case userLaunchAgent
    case systemLaunchAgent
    case systemLaunchDaemon
    case launchdUnknown

    public var displayName: String {
        switch self {
        case .userLaunchAgent: return "用户 LaunchAgent"
        case .systemLaunchAgent: return "系统 LaunchAgent"
        case .systemLaunchDaemon: return "系统 LaunchDaemon"
        case .launchdUnknown: return "launchd 服务"
        }
    }
}

public struct LocalModelSupervisorSnapshot: Identifiable, Equatable, Codable, Sendable {
    public let label: String
    public let domain: String
    public let kind: LocalModelSupervisorKind
    public let sourcePath: String?
    public let sourceDeviceID: UInt64?
    public let sourceFileID: UInt64?
    public let programName: String?
    public let keepAlive: Bool
    public let runAtLoad: Bool
    public let isLoaded: Bool
    public let isDisabled: Bool
    public let processID: Int32?
    public let isOwnedByCurrentUser: Bool
    public let platform: LocalModelPlatform

    public init(
        label: String,
        domain: String,
        kind: LocalModelSupervisorKind,
        sourcePath: String?,
        sourceDeviceID: UInt64? = nil,
        sourceFileID: UInt64? = nil,
        programName: String?,
        keepAlive: Bool,
        runAtLoad: Bool,
        isLoaded: Bool,
        isDisabled: Bool,
        processID: Int32?,
        isOwnedByCurrentUser: Bool,
        platform: LocalModelPlatform
    ) {
        self.label = label
        self.domain = domain
        self.kind = kind
        self.sourcePath = sourcePath
        self.sourceDeviceID = sourceDeviceID
        self.sourceFileID = sourceFileID
        self.programName = programName
        self.keepAlive = keepAlive
        self.runAtLoad = runAtLoad
        self.isLoaded = isLoaded
        self.isDisabled = isDisabled
        self.processID = processID
        self.isOwnedByCurrentUser = isOwnedByCurrentUser
        self.platform = platform
    }

    public var id: String { "\(domain)/\(label)" }

    public var serviceTarget: String { "\(domain)/\(label)" }

    public var displaySourcePath: String? {
        guard let sourcePath else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if sourcePath == home { return "~" }
        if sourcePath.hasPrefix(home + "/") {
            return "~" + sourcePath.dropFirst(home.count)
        }
        return sourcePath
    }

    public var restartDescription: String {
        if keepAlive && runAtLoad { return "KeepAlive · 登录时启动" }
        if keepAlive { return "KeepAlive 会自动重启" }
        if runAtLoad { return "登录时自动启动" }
        return isLoaded ? "由 launchd 管理" : "已安装但未载入"
    }

    public var canDisableAndStop: Bool {
        kind == .userLaunchAgent
            && isOwnedByCurrentUser
            && sourcePath != nil
            && processID != nil
            && !isDisabled
            && LocalModelSupervisorControlPolicy.isSafeLabel(label)
    }

    public var canEnable: Bool {
        kind == .userLaunchAgent
            && isOwnedByCurrentUser
            && sourcePath != nil
            && isDisabled
            && processID == nil
            && !isLoaded
            && LocalModelSupervisorControlPolicy.isSafeLabel(label)
    }
}

public struct LocalModelLaunchdJob: Equatable, Sendable {
    public let label: String
    public let processID: Int32?

    public init(label: String, processID: Int32?) {
        self.label = label
        self.processID = processID
    }
}

public struct LocalModelSupervisorInventory: Sendable {
    public let supervisors: [LocalModelSupervisorSnapshot]
    public let commandFailed: Bool

    public init(supervisors: [LocalModelSupervisorSnapshot], commandFailed: Bool) {
        self.supervisors = supervisors
        self.commandFailed = commandFailed
    }

    public var byProcessID: [Int32: LocalModelSupervisorSnapshot] {
        // 同名 Label 可同时存在于用户与系统 LaunchAgents 根目录，映射到同一
        // 进程；Dictionary(uniqueKeysWithValues:) 遇重复键会直接崩溃。
        Dictionary(
            supervisors.compactMap { supervisor in
                supervisor.processID.map { ($0, supervisor) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

public enum LocalModelSupervisorControlPolicy {
    public static func isSafeLabel(_ label: String) -> Bool {
        guard !label.isEmpty, label.count <= 255 else { return false }
        return label.utf8.allSatisfy { byte in
            (65...90).contains(byte) || (97...122).contains(byte)
                || (48...57).contains(byte) || [46, 95, 45, 64].contains(byte)
        }
    }

    public static func disableRefusalReason(
        runtime: LocalModelRuntimeInstance
    ) -> String? {
        guard !runtime.isOwnedByCleanNest else {
            return "这是 CleanNest 自己启动的实例，不需要停用外部守护服务。"
        }
        guard let process = runtime.process,
              let supervisor = runtime.supervisor else {
            return "没有取得进程与守护服务的精确对应关系。"
        }
        guard supervisor.processID == process.pid else {
            return "守护服务记录的 PID 与当前模型进程不一致。"
        }
        guard supervisor.kind == .userLaunchAgent,
              supervisor.isOwnedByCurrentUser else {
            return "该守护服务不属于当前用户，CleanNest 只提供只读证据。"
        }
        guard supervisor.sourcePath != nil,
              supervisor.sourceDeviceID != nil,
              supervisor.sourceFileID != nil else {
            return "缺少守护配置文件的稳定身份，不能安全停用。"
        }
        guard isSafeLabel(supervisor.label) else {
            return "守护服务标签包含不安全字符。"
        }
        guard !supervisor.isDisabled else {
            return "该守护服务已经停用。"
        }
        return nil
    }

    public static func enableRefusalReason(
        supervisor: LocalModelSupervisorSnapshot
    ) -> String? {
        guard supervisor.kind == .userLaunchAgent,
              supervisor.isOwnedByCurrentUser else {
            return "该守护服务不属于当前用户，不能从 CleanNest 启用。"
        }
        guard supervisor.sourcePath != nil,
              supervisor.sourceDeviceID != nil,
              supervisor.sourceFileID != nil else {
            return "缺少守护配置文件的稳定身份，不能安全启用。"
        }
        guard isSafeLabel(supervisor.label) else {
            return "守护服务标签包含不安全字符。"
        }
        guard supervisor.isDisabled else {
            return "该守护服务当前没有被停用。"
        }
        guard supervisor.processID == nil,
              !supervisor.isLoaded else {
            return "守护服务仍处于载入或运行状态，请先重新发现当前进程。"
        }
        return nil
    }

    public static func identityMismatchReason(
        expected: LocalModelSupervisorSnapshot,
        observed: LocalModelSupervisorSnapshot
    ) -> String? {
        guard expected.label == observed.label,
              expected.domain == observed.domain,
              expected.kind == observed.kind else {
            return "守护服务标签或作用域已经改变。"
        }
        guard expected.sourcePath == observed.sourcePath,
              expected.sourceDeviceID == observed.sourceDeviceID,
              expected.sourceFileID == observed.sourceFileID else {
            return "守护配置文件已经被替换。"
        }
        if let expectedPID = expected.processID,
           observed.processID != expectedPID {
            return "守护服务已经切换到另一个进程。"
        }
        return nil
    }
}

public enum LocalModelSupervisorDiscovery {
    public static func capture() -> LocalModelSupervisorInventory {
        let uid = UInt32(Darwin.getuid())
        let domain = "gui/\(uid)"
        // A native GUI app can run inside an application bootstrap subset.
        // An unscoped `launchctl list` then returns CleanNest's own services
        // instead of the user's gui/<uid> domain. Always address the user
        // domain explicitly so external LaunchAgents are discoverable too.
        let listResult = run("/bin/launchctl", ["print", domain])
        let disabledResult = run("/bin/launchctl", ["print-disabled", domain])
        let jobs = parseLaunchctlList(listResult.output)
        // launchctl 输出是外部数据；标签重复时保留第一条，不崩溃。
        let jobsByLabel = Dictionary(jobs.map { ($0.label, $0) }, uniquingKeysWith: { first, _ in first })
        let disabledLabels = parseDisabledServices(disabledResult.output)
        let knownLabels = parseServiceLabels(disabledResult.output)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots: [(URL, LocalModelSupervisorKind, String)] = [
            (home.appendingPathComponent("Library/LaunchAgents", isDirectory: true), .userLaunchAgent, domain),
            (URL(fileURLWithPath: "/Library/LaunchAgents", isDirectory: true), .systemLaunchAgent, domain),
            (URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true), .systemLaunchDaemon, "system")
        ]

        var supervisors: [LocalModelSupervisorSnapshot] = []
        var representedLabels = Set<String>()
        for (root, kind, launchdDomain) in roots {
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).prefix(2_048) {
                guard url.pathExtension.lowercased() == "plist",
                      let supervisor = decodeLaunchAgent(
                        at: url,
                        root: root,
                        kind: kind,
                        domain: launchdDomain,
                        jobsByLabel: jobsByLabel,
                        disabledLabels: disabledLabels,
                        currentUserID: uid
                      ) else { continue }
                supervisors.append(supervisor)
                representedLabels.insert(supervisor.label)
            }
        }

        var fallbackJobs = jobs
        for label in knownLabels where !jobsByLabel.keys.contains(label) {
            fallbackJobs.append(LocalModelLaunchdJob(label: label, processID: nil))
        }
        for job in fallbackJobs where !representedLabels.contains(job.label) {
            guard let platform = LocalModelRuntimeDiscovery.classifyPlatform(text: job.label) else {
                continue
            }
            if let printed = decodeLaunchctlService(
                label: job.label,
                domain: domain,
                job: job,
                disabledLabels: disabledLabels,
                currentUserID: uid
            ) {
                supervisors.append(printed)
            } else {
                supervisors.append(
                    LocalModelSupervisorSnapshot(
                        label: job.label,
                        domain: domain,
                        kind: .launchdUnknown,
                        sourcePath: nil,
                        programName: nil,
                        keepAlive: false,
                        runAtLoad: false,
                        isLoaded: true,
                        isDisabled: disabledLabels.contains(job.label),
                        processID: job.processID,
                        isOwnedByCurrentUser: false,
                        platform: platform
                    )
                )
            }
        }

        supervisors.sort {
            if $0.processID != nil, $1.processID == nil { return true }
            if $0.processID == nil, $1.processID != nil { return false }
            return $0.label < $1.label
        }
        return LocalModelSupervisorInventory(
            supervisors: supervisors,
            commandFailed: listResult.exitCode != 0
        )
    }

    public static func parseLaunchctlList(_ output: String) -> [LocalModelLaunchdJob] {
        output.split(whereSeparator: \.isNewline).compactMap { rawLine in
            // launchctl print aligns the label with a tab after the second
            // field. Taking the last whitespace-delimited token keeps the
            // label exact for both list and domain-print formats.
            let fields = rawLine.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard fields.count == 3,
                  fields[0] == "-" || Int32(fields[0]) != nil else { return nil }
            let label = String(fields[2])
            guard LocalModelSupervisorControlPolicy.isSafeLabel(label), label != "Label" else { return nil }
            let rawPID = Int32(fields[0])
            let pid = rawPID.flatMap { $0 > 0 ? $0 : nil }
            return LocalModelLaunchdJob(label: label, processID: pid)
        }
    }

    private static func decodeLaunchctlService(
        label: String,
        domain: String,
        job: LocalModelLaunchdJob,
        disabledLabels: Set<String>,
        currentUserID: UInt32
    ) -> LocalModelSupervisorSnapshot? {
        let result = run("/bin/launchctl", ["print", "\(domain)/\(label)"])
        guard result.exitCode == 0 else { return nil }
        let output = result.output
        let sourcePath = value(after: "path = ", in: output)
        let program = value(after: "program = ", in: output)
        let type = value(after: "type = ", in: output)?.lowercased() ?? ""
        let properties = value(after: "properties = ", in: output)?.lowercased() ?? ""
        let processID = value(after: "pid = ", in: output).flatMap(Int32.init) ?? job.processID
        let classification = [label, program].compactMap { $0 }.joined(separator: " ")
        guard let platform = LocalModelRuntimeDiscovery.classifyPlatform(text: classification) else {
            return nil
        }
        let kind: LocalModelSupervisorKind
        if type.contains("launchagent") {
            kind = .userLaunchAgent
        } else if type.contains("launchdaemon") {
            kind = .systemLaunchDaemon
        } else {
            kind = .launchdUnknown
        }
        let attributes = sourcePath.flatMap { try? FileManager.default.attributesOfItem(atPath: $0) }
        let ownerID = (attributes?[.ownerAccountID] as? NSNumber)?.uint32Value
        let deviceID = (attributes?[.systemNumber] as? NSNumber)?.uint64Value
        let fileID = (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
        return LocalModelSupervisorSnapshot(
            label: label,
            domain: domain,
            kind: kind,
            sourcePath: sourcePath,
            sourceDeviceID: deviceID,
            sourceFileID: fileID,
            programName: program.map { URL(fileURLWithPath: $0).lastPathComponent },
            keepAlive: properties.contains("keepalive"),
            runAtLoad: properties.contains("runatload"),
            isLoaded: true,
            isDisabled: disabledLabels.contains(label),
            processID: processID,
            isOwnedByCurrentUser: kind == .userLaunchAgent && ownerID == currentUserID,
            platform: platform
        )
    }

    private static func value(after marker: String, in output: String) -> String? {
        guard let range = output.range(of: marker),
              let lineEnd = output[range.upperBound...].firstIndex(of: "\n") else {
            return nil
        }
        let value = output[range.upperBound..<lineEnd]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public static func parseDisabledServices(_ output: String) -> Set<String> {
        var labels = Set<String>()
        for line in output.split(whereSeparator: \.isNewline) where line.contains("=> disabled") {
            let quotedFields = line.split(separator: "\"", maxSplits: 2, omittingEmptySubsequences: false)
            guard quotedFields.count >= 2 else { continue }
            let label = String(quotedFields[1]).trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n"))
            if LocalModelSupervisorControlPolicy.isSafeLabel(label) { labels.insert(label) }
        }
        return labels
    }

    public static func parseServiceLabels(_ output: String) -> Set<String> {
        var labels = Set<String>()
        for line in output.split(whereSeparator: \.isNewline) where line.contains("=>") {
            let quotedFields = line.split(separator: "\"", maxSplits: 2, omittingEmptySubsequences: false)
            guard quotedFields.count >= 2 else { continue }
            let label = String(quotedFields[1]).trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n"))
            if LocalModelSupervisorControlPolicy.isSafeLabel(label) { labels.insert(label) }
        }
        return labels
    }

    private static func decodeLaunchAgent(
        at url: URL,
        root: URL,
        kind: LocalModelSupervisorKind,
        domain: String,
        jobsByLabel: [String: LocalModelLaunchdJob],
        disabledLabels: Set<String>,
        currentUserID: UInt32
    ) -> LocalModelSupervisorSnapshot? {
        guard url.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              (values.fileSize ?? 0) <= 1_048_576,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              let propertyList = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = propertyList as? [String: Any],
              let label = dictionary["Label"] as? String,
              LocalModelSupervisorControlPolicy.isSafeLabel(label) else { return nil }

        let arguments = dictionary["ProgramArguments"] as? [String] ?? []
        let program = (dictionary["Program"] as? String) ?? arguments.first
        let classification = ([label, program].compactMap { $0 } + arguments).joined(separator: " ")
        guard let platform = LocalModelRuntimeDiscovery.classifyPlatform(text: classification) else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let ownerID = (attributes?[.ownerAccountID] as? NSNumber)?.uint32Value
        let deviceID = (attributes?[.systemNumber] as? NSNumber)?.uint64Value
        let fileID = (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
        let keepAlive: Bool
        if let value = dictionary["KeepAlive"] as? Bool {
            keepAlive = value
        } else {
            keepAlive = dictionary["KeepAlive"] is [String: Any]
        }

        let job = jobsByLabel[label]
        return LocalModelSupervisorSnapshot(
            label: label,
            domain: domain,
            kind: kind,
            sourcePath: url.standardizedFileURL.path,
            sourceDeviceID: deviceID,
            sourceFileID: fileID,
            programName: program.map { URL(fileURLWithPath: $0).lastPathComponent },
            keepAlive: keepAlive,
            runAtLoad: dictionary["RunAtLoad"] as? Bool ?? false,
            isLoaded: job != nil,
            isDisabled: disabledLabels.contains(label),
            processID: job?.processID,
            isOwnedByCurrentUser: kind == .userLaunchAgent && ownerID == currentUserID,
            platform: platform
        )
    }

    private static func run(_ executable: String, _ arguments: [String]) -> (exitCode: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard data.count <= 4 * 1_024 * 1_024 else { return (-1, "") }
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        } catch {
            return (-1, "")
        }
    }
}
