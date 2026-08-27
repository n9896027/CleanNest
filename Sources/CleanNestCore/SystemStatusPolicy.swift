import Foundation

public struct MenuBarWidthCandidate: Equatable, Sendable {
    public let metric: MenuBarMetric
    public let width: Double
    public let healthLevel: NativeMetricHealthLevel

    public init(metric: MenuBarMetric, width: Double, healthLevel: NativeMetricHealthLevel) {
        self.metric = metric
        self.width = max(0, width)
        self.healthLevel = healthLevel
    }
}

public struct MenuBarWidthSelection: Equatable, Sendable {
    public let visible: [MenuBarMetric]
    public let collapsed: [MenuBarMetric]
    public let usedWidth: Double
    public let budget: Double

    public init(
        visible: [MenuBarMetric],
        collapsed: [MenuBarMetric],
        usedWidth: Double,
        budget: Double
    ) {
        self.visible = visible
        self.collapsed = collapsed
        self.usedWidth = usedWidth
        self.budget = budget
    }
}

public enum MenuBarWidthPolicy {
    /// Keeps every abnormal item, then the user's preferred item, then fills
    /// remaining space in the user's order. Values are never shortened to fit.
    public static func select(
        candidates: [MenuBarWidthCandidate],
        budget: Double,
        preferredMetric: MenuBarMetric?
    ) -> MenuBarWidthSelection {
        let safeBudget = max(0, budget)
        var selected = Set<MenuBarMetric>()
        var used = 0.0

        for candidate in candidates where candidate.healthLevel != .normal {
            if selected.insert(candidate.metric).inserted { used += candidate.width }
        }

        if let preferredMetric,
           let preferred = candidates.first(where: { $0.metric == preferredMetric }),
           selected.insert(preferred.metric).inserted {
            used += preferred.width
        }

        if selected.isEmpty, let first = candidates.first {
            selected.insert(first.metric)
            used += first.width
        }

        for candidate in candidates where !selected.contains(candidate.metric) {
            guard used + candidate.width <= safeBudget else { continue }
            selected.insert(candidate.metric)
            used += candidate.width
        }

        return MenuBarWidthSelection(
            visible: candidates.compactMap { selected.contains($0.metric) ? $0.metric : nil },
            collapsed: candidates.compactMap { selected.contains($0.metric) ? nil : $0.metric },
            usedWidth: used,
            budget: safeBudget
        )
    }
}

public struct MemoryApplicationGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let processes: [MemoryProcessSnapshot]
    public let physicalFootprintBytes: Int64
    public let residentBytes: Int64

    public init(
        id: String,
        displayName: String,
        processes: [MemoryProcessSnapshot],
        physicalFootprintBytes: Int64,
        residentBytes: Int64
    ) {
        self.id = id
        self.displayName = displayName
        self.processes = processes
        self.physicalFootprintBytes = physicalFootprintBytes
        self.residentBytes = residentBytes
    }

    public var protectedProcessCount: Int {
        processes.lazy.filter { !$0.canTerminate }.count
    }
}

public enum MemoryApplicationGrouper {
    private struct GroupIdentity: Hashable {
        let key: String
        let name: String
    }

    public static func groups(_ processes: [MemoryProcessSnapshot]) -> [MemoryApplicationGroup] {
        let grouped = Dictionary(grouping: processes) { process in
            groupIdentity(process)
        }
        return grouped.map { identity, members in
            let ordered = members.sorted { lhs, rhs in
                footprint(lhs) == footprint(rhs)
                    ? lhs.pid < rhs.pid
                    : footprint(lhs) > footprint(rhs)
            }
            return MemoryApplicationGroup(
                id: identity.key,
                displayName: identity.name,
                processes: ordered,
                physicalFootprintBytes: saturatedSum(ordered.map(\.physicalFootprintBytes)),
                residentBytes: saturatedSum(ordered.map(\.residentBytes))
            )
        }
        .sorted { lhs, rhs in
            if lhs.physicalFootprintBytes == rhs.physicalFootprintBytes {
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
            return lhs.physicalFootprintBytes > rhs.physicalFootprintBytes
        }
    }

    private static func groupIdentity(_ process: MemoryProcessSnapshot) -> GroupIdentity {
        if let applicationName = nonempty(process.applicationName) {
            return GroupIdentity(
                key: "app:" + applicationName.lowercased(),
                name: applicationName
            )
        }
        if let path = process.executablePath,
           let appComponent = path.split(separator: "/").first(where: { $0.hasSuffix(".app") }) {
            let name = String(appComponent.dropLast(4))
            return GroupIdentity(
                key: "bundle:" + String(appComponent).lowercased(),
                name: name
            )
        }
        let name = nonempty(process.name) ?? "未知进程"
        return GroupIdentity(key: "process:" + name.lowercased(), name: name)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func footprint(_ process: MemoryProcessSnapshot) -> Int64 {
        process.physicalFootprintBytes > 0
            ? process.physicalFootprintBytes
            : process.residentBytes
    }

    private static func saturatedSum(_ values: [Int64]) -> Int64 {
        values.reduce(0) { result, value in
            let (sum, overflow) = result.addingReportingOverflow(max(0, value))
            return overflow ? Int64.max : sum
        }
    }
}
