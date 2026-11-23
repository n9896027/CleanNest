import Foundation

public enum ApplicationContainerActivityStatus: String, Codable, Equatable, Sendable {
    case notRunning
    case running
    case unknown

    public var displayName: String {
        switch self {
        case .notRunning: return "已确认未运行"
        case .running: return "仍在运行"
        case .unknown: return "退出状态未知"
        }
    }
}

/// Read-only evidence for a container already associated with the selected App.
/// This report never authorizes deletion, including when every check succeeds.
public struct ApplicationContainerReadOnlyReport: Codable, Equatable, Sendable {
    public let containerURL: URL
    public let expectedBundleIdentifier: String
    public let ownership: ApplicationDependencyOwnership
    public let bundleIdentifierMatched: Bool
    public let signatureMatched: Bool
    public let identityVerified: Bool
    public let activityStatus: ApplicationContainerActivityStatus
    public let isReadOnly: Bool
    public let evidence: [String]

    public init(
        containerURL: URL,
        expectedBundleIdentifier: String,
        ownership: ApplicationDependencyOwnership,
        bundleIdentifierMatched: Bool,
        signatureMatched: Bool,
        identityVerified: Bool,
        activityStatus: ApplicationContainerActivityStatus,
        evidence: [String]
    ) {
        self.containerURL = containerURL.standardizedFileURL
        self.expectedBundleIdentifier = expectedBundleIdentifier
        self.ownership = ownership
        self.bundleIdentifierMatched = bundleIdentifierMatched
        self.signatureMatched = signatureMatched
        self.identityVerified = identityVerified
        self.activityStatus = activityStatus
        isReadOnly = true
        self.evidence = evidence
    }
}

public struct ApplicationContainerReadOnlyInspector: Sendable {
    public let homeDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    public func inspect(
        container: URL,
        expectedBundleIdentifier: String,
        declaredApplicationGroups: [String],
        signatureMatchesApplication: Bool,
        applicationIsRunning: Bool?
    ) -> ApplicationContainerReadOnlyReport {
        let container = container.standardizedFileURL
        let privateRoot = homeDirectory.appendingPathComponent("Library/Containers", isDirectory: true).standardizedFileURL
        let groupRoot = homeDirectory.appendingPathComponent("Library/Group Containers", isDirectory: true).standardizedFileURL
        let parent = container.deletingLastPathComponent().standardizedFileURL
        let isPrivateLocation = parent == privateRoot
        let isGroupLocation = parent == groupRoot
        let bundleMatches = isPrivateLocation
            && !expectedBundleIdentifier.isEmpty
            && container.lastPathComponent == expectedBundleIdentifier
        let groupMatches = isGroupLocation && declaredApplicationGroups.contains(container.lastPathComponent)
        let identity = try? ApplicationDependencyIdentity.capture(at: container)
        let identityVerified = identity?.itemType == .directory
        let ownership: ApplicationDependencyOwnership
        if bundleMatches {
            ownership = .systemManaged
        } else if groupMatches {
            ownership = .sharedGroup
        } else {
            ownership = .unverified
        }
        let activityStatus: ApplicationContainerActivityStatus
        switch applicationIsRunning {
        case .some(true): activityStatus = .running
        case .some(false): activityStatus = .notRunning
        case .none: activityStatus = .unknown
        }
        var evidence: [String] = []
        if bundleMatches {
            evidence.append("容器位置与 Bundle ID 精确匹配：\(expectedBundleIdentifier)")
        } else if groupMatches {
            evidence.append("容器来自 App 签名声明的共享组；可能仍被其他 App 使用")
        } else {
            evidence.append("容器不在允许的直属位置，或 Bundle ID／共享组归属不匹配")
        }
        evidence.append(signatureMatchesApplication
            ? "App 签名标识与 Bundle ID 一致"
            : "App 签名归属未确认；不扩大容器处理范围")
        evidence.append(identityVerified
            ? "已记录容器目录稳定身份"
            : "容器身份不可确认，或是符号链接／非目录；保持只读")
        evidence.append("退出状态：\(activityStatus.displayName)")
        switch activityStatus {
        case .running:
            evidence.append("App 仍在运行；容器及其内容保持只读")
        case .notRunning:
            evidence.append("已确认 App 退出，但 macOS 管理容器仍不按普通缓存处理")
        case .unknown:
            evidence.append("无法确认退出状态；容器及其内容保持只读")
        }
        evidence.append("本报告只提供归属与状态证据，永不授权删除容器")
        return ApplicationContainerReadOnlyReport(
            containerURL: container,
            expectedBundleIdentifier: expectedBundleIdentifier,
            ownership: ownership,
            bundleIdentifierMatched: bundleMatches,
            signatureMatched: signatureMatchesApplication,
            identityVerified: identityVerified,
            activityStatus: activityStatus,
            evidence: evidence
        )
    }
}
