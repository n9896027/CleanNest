import Foundation

public struct SystemAlertEvent: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let metric: MenuBarMetric
    public var level: NativeMetricHealthLevel
    public let startedAt: Date
    public var lastObservedAt: Date
    public var endedAt: Date?
    public var peakValue: Double?
    public var peakDescription: String
    public var reason: String
    public let riskDirection: NativeMetricRiskDirection

    public init(
        id: UUID = UUID(),
        metric: MenuBarMetric,
        level: NativeMetricHealthLevel,
        startedAt: Date,
        lastObservedAt: Date,
        endedAt: Date? = nil,
        peakValue: Double?,
        peakDescription: String,
        reason: String,
        riskDirection: NativeMetricRiskDirection
    ) {
        self.id = id
        self.metric = metric
        self.level = level
        self.startedAt = startedAt
        self.lastObservedAt = lastObservedAt
        self.endedAt = endedAt
        self.peakValue = peakValue
        self.peakDescription = peakDescription
        self.reason = reason
        self.riskDirection = riskDirection
    }

    public var isActive: Bool { endedAt == nil }

    public func duration(at now: Date = Date()) -> TimeInterval {
        max(0, (endedAt ?? now).timeIntervalSince(startedAt))
    }
}

public struct SystemAlertTimeline: Codable, Equatable, Sendable {
    public private(set) var events: [SystemAlertEvent]
    public var maximumEventCount: Int
    public var maximumContinuousSampleGap: TimeInterval

    public init(
        events: [SystemAlertEvent] = [],
        maximumEventCount: Int = 200,
        maximumContinuousSampleGap: TimeInterval = 5 * 60
    ) {
        self.events = events
        self.maximumEventCount = max(20, maximumEventCount)
        self.maximumContinuousSampleGap = max(30, maximumContinuousSampleGap)
        trim()
    }

    /// Ends an event at the last sample seen before the app stopped. A later
    /// launch must not make downtime or sleep look like one continuous alert.
    public mutating func closeUnfinishedEventsFromPreviousRun() -> Bool {
        var changed = false
        for index in events.indices where events[index].endedAt == nil {
            events[index].endedAt = events[index].lastObservedAt
            changed = true
        }
        return changed
    }

    /// Returns true only when durable event state changed. Normal samples do
    /// not rewrite the history file every two seconds.
    @discardableResult
    public mutating func record(
        sample: NativeMonitorSample,
        thresholds: NativeAlertThresholds
    ) -> Bool {
        var changed = false
        let tracked: [MenuBarMetric] = [.memory, .temperature, .disk, .fan, .battery]

        for metric in tracked {
            let assessment = sample.healthAssessment(for: metric, thresholds: thresholds)
            let activeIndex = events.firstIndex {
                $0.metric == metric && $0.endedAt == nil
            }

            if let activeIndex,
               sample.sampledAt.timeIntervalSince(events[activeIndex].lastObservedAt)
                    > maximumContinuousSampleGap {
                events[activeIndex].endedAt = events[activeIndex].lastObservedAt
                changed = true
            }

            let currentActiveIndex = events.firstIndex {
                $0.metric == metric && $0.endedAt == nil
            }
            guard let assessment else { continue }

            if assessment.level == .normal {
                if let currentActiveIndex {
                    events[currentActiveIndex].lastObservedAt = sample.sampledAt
                    events[currentActiveIndex].endedAt = sample.sampledAt
                    changed = true
                }
                continue
            }

            if let currentActiveIndex {
                events[currentActiveIndex].lastObservedAt = sample.sampledAt
                if assessment.level > events[currentActiveIndex].level {
                    events[currentActiveIndex].level = assessment.level
                    events[currentActiveIndex].reason = assessment.reason
                    changed = true
                }
                if isWorsePeak(
                    assessment.observedValue,
                    than: events[currentActiveIndex].peakValue,
                    direction: assessment.riskDirection
                ) {
                    events[currentActiveIndex].peakValue = assessment.observedValue
                    events[currentActiveIndex].peakDescription = assessment.observedDescription
                    events[currentActiveIndex].reason = assessment.reason
                    changed = true
                }
            } else {
                events.insert(
                    SystemAlertEvent(
                        metric: metric,
                        level: assessment.level,
                        startedAt: sample.sampledAt,
                        lastObservedAt: sample.sampledAt,
                        peakValue: assessment.observedValue,
                        peakDescription: assessment.observedDescription,
                        reason: assessment.reason,
                        riskDirection: assessment.riskDirection
                    ),
                    at: 0
                )
                changed = true
            }
        }

        if changed { trim() }
        return changed
    }

    private func isWorsePeak(
        _ candidate: Double?,
        than current: Double?,
        direction: NativeMetricRiskDirection
    ) -> Bool {
        guard let candidate else { return false }
        guard let current else { return true }
        switch direction {
        case .higherIsWorse: return candidate > current
        case .lowerIsWorse: return candidate < current
        }
    }

    private mutating func trim() {
        if events.count > maximumEventCount {
            events.removeLast(events.count - maximumEventCount)
        }
    }
}

public enum SystemAlertTimelinePersistence {
    public static func load(from url: URL) throws -> SystemAlertTimeline {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SystemAlertTimeline.self, from: data)
    }

    public static func save(_ timeline: SystemAlertTimeline, to url: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(timeline)
        try data.write(to: url, options: .atomic)
    }
}
