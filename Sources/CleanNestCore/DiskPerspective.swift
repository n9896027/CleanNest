import Foundation

public enum DiskLedgerPerspective: String, CaseIterable, Codable, Identifiable, Sendable {
    case directory
    case application
    case function

    public var id: String { rawValue }
}

public enum DiskLedgerCoverage: String, Codable, Equatable, Sendable {
    case complete
    case partial
    case unknown
}

public enum DiskLedgerClassificationEvidence: String, Codable, Equatable, Sendable {
    case directPath
    case localRule
    case unresolved
}

public enum DiskLedgerFunctionalGroup: String, CaseIterable, Codable, Identifiable, Sendable {
    case personalContent
    case applicationsAndData
    case localAIModels
    case virtualMachinesAndContainers
    case developmentAndAgents
    case downloadsAndInstallers
    case cachesAndTemporary
    case cloudAndSync
    case logsAndDiagnostics
    case systemAndShared
    case unknown

    public var id: String { rawValue }
}

public struct DiskLedgerRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let bytes: Int64
    public let members: [DiskEntry]
    public let ownerIdentifier: String?
    public let functionalGroup: DiskLedgerFunctionalGroup?
    public let classificationEvidence: DiskLedgerClassificationEvidence
    public let coverage: DiskLedgerCoverage

    public init(
        id: String,
        title: String,
        detail: String,
        bytes: Int64,
        members: [DiskEntry],
        ownerIdentifier: String? = nil,
        functionalGroup: DiskLedgerFunctionalGroup? = nil,
        classificationEvidence: DiskLedgerClassificationEvidence,
        coverage: DiskLedgerCoverage
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.bytes = max(0, bytes)
        self.members = members
        self.ownerIdentifier = ownerIdentifier
        self.functionalGroup = functionalGroup
        self.classificationEvidence = classificationEvidence
        self.coverage = coverage
    }
}

public struct DiskPerspectiveLedger: Equatable, Sendable {
    public let perspective: DiskLedgerPerspective
    public let rows: [DiskLedgerRow]
    public let accountedBytes: Int64
    public let reportBytes: Int64

    public init(
        perspective: DiskLedgerPerspective,
        rows: [DiskLedgerRow],
        accountedBytes: Int64,
        reportBytes: Int64
    ) {
        self.perspective = perspective
        self.rows = rows
        self.accountedBytes = max(0, accountedBytes)
        self.reportBytes = max(0, reportBytes)
    }

    public var unresolvedBytes: Int64 {
        rows
            .filter { $0.classificationEvidence == .unresolved }
            .reduce(0) { $0 + $1.bytes }
    }

    public var containsPartialCoverage: Bool {
        rows.contains { $0.coverage != .complete }
    }
}

public enum DiskPerspectiveBuilder {
    public static func make(
        report: DiskReport,
        evidenceReport: DiskEvidenceReport?,
        perspective: DiskLedgerPerspective,
        homeDirectory: URL
    ) -> DiskPerspectiveLedger {
        let evidenceByID = (evidenceReport?.entries ?? []).reduce(into: [String: DiskEvidenceEntry]()) {
            if $0[$1.id] == nil { $0[$1.id] = $1 }
        }
        let rows: [DiskLedgerRow]
        switch perspective {
        case .directory:
            rows = report.entries.map { entry in
                return DiskLedgerRow(
                    id: "directory:\(entry.id)",
                    title: entry.name,
                    detail: entry.url.path,
                    bytes: entry.bytes,
                    members: [entry],
                    classificationEvidence: .directPath,
                    coverage: coverage(for: [entry])
                )
            }
        case .application:
            rows = applicationRows(report: report, evidenceByID: evidenceByID)
        case .function:
            rows = functionalRows(
                report: report,
                evidenceByID: evidenceByID,
                homeDirectory: homeDirectory
            )
        }

        let sorted = rows.sorted {
            if $0.bytes == $1.bytes { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            return $0.bytes > $1.bytes
        }
        return DiskPerspectiveLedger(
            perspective: perspective,
            rows: sorted,
            accountedBytes: sorted.reduce(0) { $0 + $1.bytes },
            reportBytes: report.totalBytes
        )
    }

    private struct ApplicationAssignment {
        let key: String
        let title: String
        let ownerIdentifier: String?
        let evidence: DiskLedgerClassificationEvidence
    }

    private static func applicationRows(
        report: DiskReport,
        evidenceByID: [String: DiskEvidenceEntry]
    ) -> [DiskLedgerRow] {
        let assignments = report.entries.map { entry -> (ApplicationAssignment, DiskEntry) in
            let evidence = evidenceByID[DiskEvidenceIndexer.fingerprint(for: entry.url)]
            return (applicationAssignment(for: entry, evidence: evidence), entry)
        }
        let groups = Dictionary(grouping: assignments, by: { $0.0.key })
        return groups.values.compactMap { values in
            guard let assignment = values.first?.0 else { return nil }
            let members = values.map(\.1).sorted { $0.bytes > $1.bytes }
            let detail: String
            if assignment.evidence == .unresolved {
                detail = "当前层级没有足够路径证据；展开后可继续进入确认"
            } else if members.count == 1 {
                detail = members[0].url.path
            } else {
                detail = "合并 \(members.count) 个有相同路径归属的项目"
            }
            return DiskLedgerRow(
                id: "application:\(assignment.key)",
                title: assignment.title,
                detail: detail,
                bytes: members.reduce(0) { $0 + $1.bytes },
                members: members,
                ownerIdentifier: assignment.ownerIdentifier,
                classificationEvidence: assignment.evidence,
                coverage: coverage(for: members)
            )
        }
    }

    private static func applicationAssignment(
        for entry: DiskEntry,
        evidence: DiskEvidenceEntry?
    ) -> ApplicationAssignment {
        if entry.url.pathExtension.lowercased() == "app" {
            let name = entry.url.deletingPathExtension().lastPathComponent
            return ApplicationAssignment(
                key: "app:\(name.lowercased())",
                title: name,
                ownerIdentifier: nil,
                evidence: .directPath
            )
        }

        if let owner = sanitizedOwner(evidence?.likelyOwner) {
            return ApplicationAssignment(
                key: "owner:\(owner.lowercased())",
                title: friendlyOwnerName(owner),
                ownerIdentifier: owner.contains(".") ? owner : nil,
                evidence: .directPath
            )
        }

        let components = entry.url.standardizedFileURL.pathComponents
        let markers = ["Containers", "Group Containers", "Application Support", "Caches", "Logs"]
        for marker in markers {
            guard let index = components.lastIndex(of: marker),
                  components.indices.contains(index + 1),
                  let owner = sanitizedOwner(components[index + 1]) else { continue }
            return ApplicationAssignment(
                key: "owner:\(owner.lowercased())",
                title: friendlyOwnerName(owner),
                ownerIdentifier: owner.contains(".") ? owner : nil,
                evidence: .directPath
            )
        }

        let aliases: [String: String] = [
            ".claude": "Claude",
            ".codex": "Codex",
            ".docker": "Docker",
            ".ollama": "Ollama",
            ".openclaw": "OpenClaw",
            ".pi": "Pi Agent"
        ]
        if let alias = aliases[entry.name.lowercased()] {
            return ApplicationAssignment(
                key: "alias:\(alias.lowercased())",
                title: alias,
                ownerIdentifier: nil,
                evidence: .localRule
            )
        }

        return ApplicationAssignment(
            key: "unresolved",
            title: "归属待确认",
            ownerIdentifier: nil,
            evidence: .unresolved
        )
    }

    private static func functionalRows(
        report: DiskReport,
        evidenceByID: [String: DiskEvidenceEntry],
        homeDirectory: URL
    ) -> [DiskLedgerRow] {
        let assignments = report.entries.map { entry -> (DiskLedgerFunctionalGroup, DiskEntry) in
            let evidence = evidenceByID[DiskEvidenceIndexer.fingerprint(for: entry.url)]
            return (functionalGroup(for: entry, evidence: evidence, homeDirectory: homeDirectory), entry)
        }
        let groups = Dictionary(grouping: assignments, by: { $0.0 })
        return groups.map { group, values in
            let members = values.map(\.1).sorted { $0.bytes > $1.bytes }
            let evidence: DiskLedgerClassificationEvidence = group == .unknown ? .unresolved : .localRule
            return DiskLedgerRow(
                id: "function:\(group.rawValue)",
                title: functionalTitle(group),
                detail: functionalDetail(group, memberCount: members.count),
                bytes: members.reduce(0) { $0 + $1.bytes },
                members: members,
                functionalGroup: group,
                classificationEvidence: evidence,
                coverage: coverage(for: members)
            )
        }
    }

    private static func functionalGroup(
        for entry: DiskEntry,
        evidence: DiskEvidenceEntry?,
        homeDirectory: URL
    ) -> DiskLedgerFunctionalGroup {
        let path = entry.url.standardizedFileURL.path.lowercased()
        let componentSet = Set(entry.url.pathComponents.map { $0.lowercased() })

        if path == "/applications" || path.hasPrefix("/applications/") {
            return .applicationsAndData
        }
        if path == "/system" || path.hasPrefix("/system/")
            || path == "/library" || path.hasPrefix("/library/") {
            return .systemAndShared
        }
        if path == "/users" {
            return .personalContent
        }

        if path.contains("/vm_bundles/")
            || path.contains("com.docker.docker")
            || path.contains("/docker.raw")
            || componentSet.contains("docker")
            || componentSet.contains(".docker")
            || componentSet.contains("vm_bundles")
            || componentSet.contains("vms") {
            return .virtualMachinesAndContainers
        }
        if componentSet.contains("models")
            || path.contains("huggingface/hub")
            || path.contains("/ollama/models")
            || path.contains("/mlx/")
            || path.contains("lm studio") {
            return .localAIModels
        }
        if !componentSet.isDisjoint(with: [
            ".codex", ".claude", ".openclaw", ".pi", ".turbo", "node_modules",
            ".build", "deriveddata", "developer"
        ]) {
            return .developmentAndAgents
        }

        let category = evidence?.category
            ?? DiskAISafetyPolicy.policy(for: entry.url, homeDirectory: homeDirectory).category
        switch category {
        case .cache: return .cachesAndTemporary
        case .logs: return .logsAndDiagnostics
        case .developerArtifacts, .packageManagerData: return .developmentAndAgents
        case .appSandboxData, .appSupportData: return .applicationsAndData
        case .cloudDocuments: return .cloudAndSync
        case .userContent: return .personalContent
        case .systemData: return .systemAndShared
        case .installerOrArchive: return .downloadsAndInstallers
        case .unknown: return .unknown
        }
    }

    private static func coverage(for members: [DiskEntry]) -> DiskLedgerCoverage {
        var containsUnknown = false
        for member in members {
            if let traversal = member.traversal {
                if !traversal.isCompleteWithinFileSystem { return .partial }
            } else if member.isDirectory {
                containsUnknown = true
            }
        }
        return containsUnknown ? .unknown : .complete
    }

    private static func sanitizedOwner(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 160,
              !trimmed.contains("/"),
              !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return nil
        }
        return trimmed
    }

    private static func friendlyOwnerName(_ owner: String) -> String {
        let known: [String: String] = [
            "com.docker.docker": "Docker",
            "com.anthropic.claudefordesktop": "Claude",
            "com.openai.codex": "Codex"
        ]
        if let name = known[owner.lowercased()] { return name }
        return owner
    }

    private static func functionalTitle(_ group: DiskLedgerFunctionalGroup) -> String {
        switch group {
        case .personalContent: return "个人文件与媒体"
        case .applicationsAndData: return "应用本体与应用数据"
        case .localAIModels: return "本地 AI 模型"
        case .virtualMachinesAndContainers: return "虚拟机与容器"
        case .developmentAndAgents: return "开发工具与 AI Agent 产物"
        case .downloadsAndInstallers: return "下载、安装包与归档"
        case .cachesAndTemporary: return "缓存与临时数据"
        case .cloudAndSync: return "云盘与同步文件"
        case .logsAndDiagnostics: return "日志与诊断"
        case .systemAndShared: return "系统与共享数据"
        case .unknown: return "用途待确认"
        }
    }

    private static func functionalDetail(_ group: DiskLedgerFunctionalGroup, memberCount: Int) -> String {
        let prefix = "本次扫描中的 \(memberCount) 项"
        switch group {
        case .personalContent: return "\(prefix)；通常不可自动重建"
        case .applicationsAndData: return "\(prefix)；应优先由所属 App 管理"
        case .localAIModels: return "\(prefix)；删除会让本地推理不可用或需要重下"
        case .virtualMachinesAndContainers: return "\(prefix)；包含镜像、容器、卷或隔离运行环境"
        case .developmentAndAgents: return "\(prefix)；源代码、会话与可重建产物可能混在一起"
        case .downloadsAndInstallers: return "\(prefix)；仅在确认不再需要离线安装后复核"
        case .cachesAndTemporary: return "\(prefix)；通常可重建，但下次使用可能变慢"
        case .cloudAndSync: return "\(prefix)；本机操作可能同步到其他设备"
        case .logsAndDiagnostics: return "\(prefix)；旧记录可能影响故障追溯"
        case .systemAndShared: return "\(prefix)；由 macOS 或多个组件共同管理"
        case .unknown: return "\(prefix)；路径规则不足，默认保留并继续查看"
        }
    }
}
