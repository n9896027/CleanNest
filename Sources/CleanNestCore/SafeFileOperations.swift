import Darwin
import Foundation
import Security

public enum SafePathError: LocalizedError, Equatable {
    case missing
    case symbolicLink
    case protectedPath
    case outsideAllowedRoots
    case invalidApplication
    case currentApplication
    case applicationChanged

    public var errorDescription: String? {
        switch self {
        case .missing: return "目标已经不存在。"
        case .symbolicLink: return "为避免越过安全边界，符号链接不会被处理。"
        case .protectedPath: return "该路径受到保护，不能清理。"
        case .outsideAllowedRoots: return "该路径不在 CleanNest 允许的清理范围内。"
        case .invalidApplication: return "只能卸载 Applications 目录中的 .app。"
        case .currentApplication: return "CleanNest 不能在运行时卸载自身。"
        case .applicationChanged: return "App 在扫描后发生了变化。为避免卸载错误目标，本次操作已停止。"
        }
    }
}

public struct ApplicationFileIdentity: Hashable, Sendable {
    public let deviceID: UInt64
    public let fileID: UInt64
    public let ownerUserID: UInt32

    public init(deviceID: UInt64, fileID: UInt64, ownerUserID: UInt32) {
        self.deviceID = deviceID
        self.fileID = fileID
        self.ownerUserID = ownerUserID
    }

    public static func capture(
        at target: URL,
        fileManager: FileManager = .default
    ) throws -> ApplicationFileIdentity {
        let attributes = try fileManager.attributesOfItem(atPath: target.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              let deviceID = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
              let fileID = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
              let ownerUserID = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value else {
            throw SafePathError.invalidApplication
        }
        return ApplicationFileIdentity(
            deviceID: deviceID,
            fileID: fileID,
            ownerUserID: ownerUserID
        )
    }
}

public enum ApplicationRemovalRequirement: String, Equatable, Sendable {
    case standard
    case administratorAuthentication
}

public struct ApplicationTrashRequest: Sendable {
    public let source: URL
    public let expectedIdentity: ApplicationFileIdentity
    public let expectedBundleIdentifier: String?
    public let trashDirectory: URL

    public init(
        source: URL,
        expectedIdentity: ApplicationFileIdentity,
        expectedBundleIdentifier: String?,
        trashDirectory: URL
    ) {
        self.source = source.standardizedFileURL
        self.expectedIdentity = expectedIdentity
        self.expectedBundleIdentifier = expectedBundleIdentifier
        self.trashDirectory = trashDirectory.standardizedFileURL
    }
}

private enum ApplicationMovePermissionProbeSystem {
    static func canMoveWithoutAuthorization(
        source: URL,
        trashDirectory: URL
    ) -> Bool {
        let sourceParent = source.standardizedFileURL.deletingLastPathComponent()
        let destinationAnchor = FileManager.default.fileExists(atPath: trashDirectory.path)
            ? trashDirectory.standardizedFileURL
            : trashDirectory.standardizedFileURL.deletingLastPathComponent()

        guard access(sourceParent.path, W_OK | X_OK) == 0,
              access(destinationAnchor.path, W_OK | X_OK) == 0,
              let sourceDevice = deviceID(at: sourceParent),
              let destinationDevice = deviceID(at: destinationAnchor) else {
            return false
        }
        return sourceDevice == destinationDevice
    }

    private static func deviceID(at url: URL) -> UInt64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.systemNumber] as? NSNumber)?.uint64Value
    }
}

public struct SafePathPolicy: Sendable {
    public let homeDirectory: URL
    public let systemApplicationsDirectory: URL
    private let protectedApplicationPaths: Set<String>

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemApplicationsDirectory: URL = URL(fileURLWithPath: "/Applications", isDirectory: true),
        protectedApplicationURLs: [URL]? = nil
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.systemApplicationsDirectory = systemApplicationsDirectory.standardizedFileURL
        let protectedURLs: [URL]
        if let protectedApplicationURLs {
            protectedURLs = protectedApplicationURLs
        } else if Bundle.main.bundleURL.pathExtension.lowercased() == "app" {
            protectedURLs = [Bundle.main.bundleURL]
        } else {
            protectedURLs = []
        }
        self.protectedApplicationPaths = Set(
            protectedURLs.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        )
    }

    public var cleanupRoots: [URL] {
        [
            homeDirectory.appendingPathComponent("Library/Caches", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Logs", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Application Support", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Containers", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Group Containers", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/HTTPStorages", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Preferences", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Saved Application State", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/WebKit", isDirectory: true),
            homeDirectory.appendingPathComponent("Downloads", isDirectory: true),
            homeDirectory.appendingPathComponent(".npm/_cacache", isDirectory: true),
            homeDirectory.appendingPathComponent(".cache/pip", isDirectory: true)
        ].map(\.standardizedFileURL)
    }

    public var personalFileRoots: [URL] {
        [
            "Desktop",
            "Documents",
            "Downloads",
            "Pictures",
            "Movies",
            "Music"
        ].map { homeDirectory.appendingPathComponent($0, isDirectory: true).standardizedFileURL }
    }

    public func validateCleanupTarget(_ target: URL) throws {
        let resolved = try validatedExistingTarget(target)
        let isStrictDescendant = isStrictDescendant(resolved, of: cleanupRoots)
        guard isStrictDescendant else { throw SafePathError.outsideAllowedRoots }
    }

    public func validateCleanupCandidate(_ candidate: CleanupCandidate) throws {
        guard candidate.kind.isPersonalFile else {
            try validateCleanupTarget(candidate.url)
            return
        }

        let resolved = try validatedExistingTarget(candidate.url)
        guard isStrictDescendant(resolved, of: personalFileRoots) else {
            throw SafePathError.outsideAllowedRoots
        }
        guard candidate.fileIdentity != nil else {
            throw CleanupEvidenceError.targetChanged
        }
        _ = try CleanupFileIdentity.capture(at: resolved)
    }

    private func validatedExistingTarget(_ target: URL) throws -> URL {
        guard FileManager.default.fileExists(atPath: target.path) else { throw SafePathError.missing }
        if (try? target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw SafePathError.symbolicLink
        }

        let resolved = target.resolvingSymlinksInPath().standardizedFileURL
        let protected = [
            URL(fileURLWithPath: "/"),
            URL(fileURLWithPath: "/System"),
            URL(fileURLWithPath: "/Library"),
            homeDirectory,
            homeDirectory.appendingPathComponent("Library")
        ].map { $0.standardizedFileURL.path }
        guard !protected.contains(resolved.path) else { throw SafePathError.protectedPath }
        return resolved
    }

    private func isStrictDescendant(_ target: URL, of roots: [URL]) -> Bool {
        roots.contains { root in
            let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
            return target.path.hasPrefix(resolvedRoot + "/")
        }
    }

    public func validateApplicationTarget(_ target: URL) throws {
        guard FileManager.default.fileExists(atPath: target.path) else { throw SafePathError.missing }
        if (try? target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw SafePathError.symbolicLink
        }

        let resolved = target.resolvingSymlinksInPath().standardizedFileURL
        let applicationRoots = [
            systemApplicationsDirectory,
            homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        ].map { $0.resolvingSymlinksInPath().standardizedFileURL }

        guard resolved.pathExtension.lowercased() == "app",
              applicationRoots.contains(where: { resolved.deletingLastPathComponent().path == $0.path }) else {
            throw SafePathError.invalidApplication
        }
        guard !protectedApplicationPaths.contains(resolved.path) else {
            throw SafePathError.currentApplication
        }
        _ = try ApplicationFileIdentity.capture(at: resolved)
    }

    public func applicationIdentity(for target: URL) throws -> ApplicationFileIdentity {
        try validateApplicationTarget(target)
        return try ApplicationFileIdentity.capture(at: target.resolvingSymlinksInPath().standardizedFileURL)
    }
}

public struct TrashService: Sendable {
    public typealias ApplicationRecycler = @Sendable (ApplicationTrashRequest) async throws -> URL?
    public typealias ApplicationMovePermissionProbe = @Sendable (URL, URL) -> Bool
    typealias DependencyRecycler = @Sendable (URL) throws -> URL?

    private let policy: SafePathPolicy
    private let applicationRecycler: ApplicationRecycler
    private let applicationMovePermissionProbe: ApplicationMovePermissionProbe
    private let dependencyRecycler: DependencyRecycler

    public init(
        policy: SafePathPolicy = SafePathPolicy(),
        applicationRecycler: @escaping ApplicationRecycler
    ) {
        self.policy = policy
        self.applicationRecycler = applicationRecycler
        self.applicationMovePermissionProbe = {
            ApplicationMovePermissionProbeSystem.canMoveWithoutAuthorization(
                source: $0,
                trashDirectory: $1
            )
        }
        self.dependencyRecycler = Self.recycleDependencyThroughFileManager
    }

    public init(
        policy: SafePathPolicy,
        applicationRecycler: @escaping ApplicationRecycler,
        applicationMovePermissionProbe: @escaping ApplicationMovePermissionProbe
    ) {
        self.policy = policy
        self.applicationRecycler = applicationRecycler
        self.applicationMovePermissionProbe = applicationMovePermissionProbe
        self.dependencyRecycler = Self.recycleDependencyThroughFileManager
    }

    init(
        policy: SafePathPolicy,
        applicationRecycler: @escaping ApplicationRecycler,
        dependencyRecycler: @escaping DependencyRecycler
    ) {
        self.policy = policy
        self.applicationRecycler = applicationRecycler
        self.applicationMovePermissionProbe = {
            ApplicationMovePermissionProbeSystem.canMoveWithoutAuthorization(
                source: $0,
                trashDirectory: $1
            )
        }
        self.dependencyRecycler = dependencyRecycler
    }

    public func applicationRemovalRequirement(
        for target: URL,
        expectedIdentity: ApplicationFileIdentity? = nil,
        expectedBundleIdentifier: String? = nil,
        currentUserID: UInt32 = geteuid()
    ) throws -> ApplicationRemovalRequirement {
        let identity = try policy.applicationIdentity(for: target)
        if let expectedIdentity, identity != expectedIdentity {
            throw SafePathError.applicationChanged
        }
        if let expectedBundleIdentifier,
           !expectedBundleIdentifier.isEmpty,
           Bundle(url: target)?.bundleIdentifier != expectedBundleIdentifier {
            throw SafePathError.applicationChanged
        }
        let parent = target.resolvingSymlinksInPath().standardizedFileURL.deletingLastPathComponent().path
        let systemApplicationsPath = policy.systemApplicationsDirectory
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        let trashDirectory = policy.homeDirectory.appendingPathComponent(".Trash", isDirectory: true)
        if parent == systemApplicationsPath,
           identity.ownerUserID != currentUserID,
           !applicationMovePermissionProbe(target, trashDirectory) {
            return .administratorAuthentication
        }
        return .standard
    }

    public func trashCleanupTargets(_ targets: [URL]) async -> [TrashOutcome] {
        await trash(targets) { target in
            try policy.validateCleanupTarget(target)
        }
    }

    public func trashCleanupCandidates(_ candidates: [CleanupCandidate]) async -> [TrashOutcome] {
        let candidatesByPath = Dictionary(
            candidates.map {
                ($0.url.standardizedFileURL.path, $0)
            },
            uniquingKeysWith: { first, _ in first }
        )
        return await trash(candidates.map(\.url)) { target in
            guard let candidate = candidatesByPath[target.standardizedFileURL.path] else {
                throw CleanupEvidenceError.targetChanged
            }
            try policy.validateCleanupCandidate(candidate)
            try CleanupEvidenceValidator.validate(candidate)
        }
    }

    /// Moves only dependency nodes that were proven App-owned and explicitly
    /// approved for post-App removal. Every path is revalidated against its
    /// scan-time filesystem identity immediately before mutation.
    public func trashApplicationDependencies(
        _ nodes: [ApplicationDependencyNode]
    ) async -> [TrashOutcome] {
        let policy = self.policy
        let dependencyRecycler = self.dependencyRecycler
        return await Task.detached(priority: .userInitiated) {
            nodes.map { node in
                let source = node.url.standardizedFileURL
                do {
                    guard node.ownership == .applicationOwned,
                          node.action == .removeAfterApplication,
                          let expectedIdentity = node.identity else {
                        throw SafePathError.protectedPath
                    }
                    try policy.validateCleanupTarget(source)
                    guard try ApplicationDependencyIdentity.capture(at: source) == expectedIdentity else {
                        throw SafePathError.applicationChanged
                    }
                    let resultingURL = try dependencyRecycler(source)
                    guard !FileManager.default.fileExists(atPath: source.path),
                          let destination = resultingURL,
                          FileManager.default.fileExists(atPath: destination.path) else {
                        throw WorkspaceRecycleError.missingResult
                    }
                    return TrashOutcome(
                        source: source,
                        trashedURL: destination,
                        errorDescription: nil
                    )
                } catch {
                    let nsError = error as NSError
                    let kind: TrashFailureKind
                    if error as? SafePathError == .applicationChanged {
                        kind = .targetChanged
                    } else if error is SafePathError {
                        kind = .validation
                    } else {
                        kind = .operationFailed
                    }
                    return TrashOutcome(
                        source: source,
                        trashedURL: nil,
                        errorDescription: error.localizedDescription,
                        failureKind: kind,
                        technicalDescription: "错误域：\(nsError.domain)\n错误码：\(nsError.code)\n目标：\(source.path)\n系统说明：\(nsError.localizedDescription)"
                    )
                }
            }
        }.value
    }

    private static let recycleDependencyThroughFileManager: DependencyRecycler = { source in
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: source, resultingItemURL: &resultingURL)
        return resultingURL as URL?
    }

    public func trashApplication(
        _ target: URL,
        expectedIdentity: ApplicationFileIdentity? = nil,
        expectedBundleIdentifier: String? = nil
    ) async -> TrashOutcome {
        let source = URL(fileURLWithPath: target.path, isDirectory: true).standardizedFileURL
        do {
            try policy.validateApplicationTarget(source)
            let firstIdentity = try policy.applicationIdentity(for: source)
            if let expectedIdentity, firstIdentity != expectedIdentity {
                throw SafePathError.applicationChanged
            }
            if let expectedBundleIdentifier, !expectedBundleIdentifier.isEmpty {
                guard Bundle(url: source)?.bundleIdentifier == expectedBundleIdentifier else {
                    throw SafePathError.applicationChanged
                }
            }

            // Keep an async boundary between the scan-time check and the final
            // execution-time check so path replacement is caught before Finder
            // receives the request.
            await Task.yield()
            try Task.checkCancellation()
            try policy.validateApplicationTarget(source)
            let finalIdentity = try policy.applicationIdentity(for: source)
            guard finalIdentity == firstIdentity else {
                throw SafePathError.applicationChanged
            }

            let trashDirectory = policy.homeDirectory.appendingPathComponent(".Trash", isDirectory: true)
            let request = ApplicationTrashRequest(
                source: source,
                expectedIdentity: finalIdentity,
                expectedBundleIdentifier: expectedBundleIdentifier,
                trashDirectory: trashDirectory
            )
            guard let trashedURL = try await applicationRecycler(request) else {
                throw WorkspaceRecycleError.missingResult
            }
            guard !FileManager.default.fileExists(atPath: source.path) else {
                throw WorkspaceRecycleError.sourceStillPresent
            }
            let destination = trashedURL.standardizedFileURL
            let destinationValues = try? destination.resourceValues(forKeys: [.isSymbolicLinkKey])
            let expectedTrashParent = trashDirectory.resolvingSymlinksInPath().standardizedFileURL
            let actualTrashParent = destination
                .resolvingSymlinksInPath()
                .standardizedFileURL
                .deletingLastPathComponent()
            guard FileManager.default.fileExists(atPath: destination.path),
                  destinationValues?.isSymbolicLink != true,
                  actualTrashParent == expectedTrashParent,
                  (try? ApplicationFileIdentity.capture(at: destination)) == finalIdentity else {
                throw WorkspaceRecycleError.missingResult
            }
            if let expectedBundleIdentifier,
               !expectedBundleIdentifier.isEmpty,
               Bundle(url: destination)?.bundleIdentifier != expectedBundleIdentifier {
                throw WorkspaceRecycleError.missingResult
            }
            return TrashOutcome(
                source: source,
                trashedURL: destination,
                errorDescription: nil
            )
        } catch {
            return applicationFailureOutcome(source: source, error: error)
        }
    }

    private func trash(
        _ targets: [URL],
        validator: @escaping @Sendable (URL) throws -> Void
    ) async -> [TrashOutcome] {
        await Task.detached(priority: .userInitiated) {
            targets.map { source in
                do {
                    try validator(source)
                    var resultingURL: NSURL?
                    try FileManager.default.trashItem(at: source, resultingItemURL: &resultingURL)
                    return TrashOutcome(
                        source: source,
                        trashedURL: resultingURL as URL?,
                        errorDescription: nil
                    )
                } catch {
                    let nsError = error as NSError
                    let failureKind: TrashFailureKind
                    if error is CleanupEvidenceError {
                        failureKind = .targetChanged
                    } else if error is SafePathError {
                        failureKind = .validation
                    } else {
                        failureKind = .operationFailed
                    }
                    return TrashOutcome(
                        source: source,
                        trashedURL: nil,
                        errorDescription: error.localizedDescription,
                        failureKind: failureKind,
                        technicalDescription: "错误域：\(nsError.domain)\n错误码：\(nsError.code)\n目标：\(source.path)\n系统说明：\(nsError.localizedDescription)"
                    )
                }
            }
        }.value
    }

    private func applicationFailureOutcome(source: URL, error: Error) -> TrashOutcome {
        let nsError = error as NSError
        let failureKind: TrashFailureKind
        let message: String

        if !FileManager.default.fileExists(atPath: source.path) {
            failureKind = .missingResult
            message = "App 已离开原位置，但 CleanNest 无法确认它仍是废纸篓中的同一项目；相关文件未处理，请检查废纸篓。"
        } else if let safeError = error as? SafePathError {
            failureKind = safeError == .applicationChanged ? .targetChanged : .validation
            message = safeError.localizedDescription
        } else if Self.isAuthorizationCancellation(nsError) {
            failureKind = .authorizationCancelled
            message = "已取消 macOS 管理员认证；App 和相关文件均未改动。"
        } else if Self.isAuthorizationDenial(nsError) {
            failureKind = .authorizationDenied
            message = "macOS 管理员认证没有通过；App 和相关文件均未改动。"
        } else if Self.isAutomationDenial(nsError) {
            failureKind = .automationDenied
            message = "macOS 已阻止 CleanNest 控制 Finder；App 和相关文件均未改动。可在“隐私与安全性 → 自动化”中检查权限。"
        } else if Self.isPermissionFailure(nsError) {
            failureKind = .permissionDenied
            message = "macOS 未授予移动此 App 所需的权限；App 和相关文件均未改动。"
        } else if error as? WorkspaceRecycleError == .missingResult {
            failureKind = .missingResult
            message = "macOS 没有确认 App 已进入废纸篓；相关文件未处理。"
        } else if error as? WorkspaceRecycleError == .sourceStillPresent {
            failureKind = .missingResult
            message = "macOS 返回后 App 仍在原位置；相关文件未处理。"
        } else {
            failureKind = .operationFailed
            message = "macOS 未能将此 App 移到废纸篓；App 和相关文件均未改动。"
        }

        let technicalDescription = [
            "操作：通过 CleanNest 安全废纸篓通道移动 App",
            "目标：\(source.path)",
            "错误域：\(nsError.domain)",
            "错误码：\(nsError.code)",
            "系统说明：\(nsError.localizedDescription)"
        ].joined(separator: "\n")

        return TrashOutcome(
            source: source,
            trashedURL: nil,
            errorDescription: message,
            failureKind: failureKind,
            technicalDescription: technicalDescription
        )
    }

    private static func isAuthorizationCancellation(_ error: NSError) -> Bool {
        (error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError)
            || (error.domain == NSOSStatusErrorDomain && error.code == Int(errAuthorizationCanceled))
            || (error.domain == NSOSStatusErrorDomain && error.code == -128)
    }

    private static func isPermissionFailure(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain {
            return error.code == NSFileWriteNoPermissionError
                || error.code == NSFileReadNoPermissionError
        }
        if error.domain == NSPOSIXErrorDomain {
            return error.code == Int(EACCES) || error.code == Int(EPERM)
        }
        return false
    }

    private static func isAuthorizationDenial(_ error: NSError) -> Bool {
        error.domain == NSOSStatusErrorDomain && error.code == Int(errAuthorizationDenied)
    }

    private static func isAutomationDenial(_ error: NSError) -> Bool {
        error.domain == NSOSStatusErrorDomain && error.code == -1743
    }
}

private enum WorkspaceRecycleError: LocalizedError, Equatable {
    case missingResult
    case sourceStillPresent

    var errorDescription: String? {
        switch self {
        case .missingResult:
            return "NSWorkspace 没有返回废纸篓目标。"
        case .sourceStillPresent:
            return "NSWorkspace 返回后源路径仍然存在。"
        }
    }
}
