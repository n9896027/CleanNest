import Darwin
import Foundation

/// Privacy-sensitive areas below the current user's Library directory that a
/// recursive disk scan may not be able to enumerate without Full Disk Access.
public enum DiskPrivacySensitiveArea: String, CaseIterable, Hashable, Sendable {
    case containers = "Library/Containers"
    case groupContainers = "Library/Group Containers"
    case mobileDocuments = "Library/Mobile Documents"
    case cloudStorage = "Library/CloudStorage"
    case applicationSupport = "Library/Application Support"

    fileprivate func url(in homeDirectory: URL) -> URL {
        rawValue.split(separator: "/").reduce(homeDirectory.standardizedFileURL) { url, component in
            url.appendingPathComponent(String(component), isDirectory: true)
        }
    }
}

/// A conservative description of which privacy-sensitive areas intersect a
/// requested traversal. It is not a claim about the current macOS TCC switch.
public struct DiskPrivacyAssessment: Equatable, Sendable {
    public let sensitiveAreas: [DiskPrivacySensitiveArea]

    public init(sensitiveAreas: [DiskPrivacySensitiveArea]) {
        self.sensitiveAreas = sensitiveAreas
    }

    public var mayRequireFullDiskAccess: Bool { !sensitiveAreas.isEmpty }
}

public enum DiskPrivacyPolicy {
    /// Reports sensitive Library areas that are either inside `root` or contain
    /// `root`. Both lexical and symlink-resolved paths are checked so a symlink
    /// cannot make a protected traversal look ordinary (or vice versa).
    public static func assessTraversal(
        root: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> DiskPrivacyAssessment {
        let lexicalRoot = root.standardizedFileURL
        let resolvedRoot = lexicalRoot.resolvingSymlinksInPath().standardizedFileURL
        let lexicalHome = homeDirectory.standardizedFileURL
        let resolvedHome = lexicalHome.resolvingSymlinksInPath().standardizedFileURL

        let matches = DiskPrivacySensitiveArea.allCases.filter { area in
            let lexicalArea = area.url(in: lexicalHome)
            let resolvedArea = area.url(in: resolvedHome).resolvingSymlinksInPath().standardizedFileURL
            return intersectsTraversal(lexicalRoot, lexicalArea)
                || intersectsTraversal(resolvedRoot, resolvedArea)
        }
        return DiskPrivacyAssessment(sensitiveAreas: matches)
    }

    private static func intersectsTraversal(_ lhs: URL, _ rhs: URL) -> Bool {
        isSameOrDescendant(lhs, of: rhs) || isSameOrDescendant(rhs, of: lhs)
    }

    private static func isSameOrDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path
        let ancestorPath = ancestor.standardizedFileURL.path
        guard candidatePath != ancestorPath else { return true }
        let prefix = ancestorPath == "/" ? "/" : ancestorPath + "/"
        return candidatePath.hasPrefix(prefix)
    }
}

/// Result of a lightweight access attempt. This intentionally does not expose
/// an `authorized` state because macOS has no public API that confirms the Full
/// Disk Access switch; it only classifies what the attempted operation proved.
public enum FullDiskAccessProbeResult: Equatable, Sendable {
    case accessible
    case permissionDenied
    case indeterminate

    /// Maps a POSIX operation result to the narrowest conclusion CleanNest can
    /// safely make. A zero errno represents success; only EACCES and EPERM are
    /// treated as explicit permission failures.
    public static func classify(errno code: Int32) -> FullDiskAccessProbeResult {
        switch code {
        case 0:
            return .accessible
        case EACCES, EPERM:
            return .permissionDenied
        default:
            return .indeterminate
        }
    }

    /// Convenience for adapters that receive Foundation errors. Missing files
    /// and unrelated I/O failures remain indeterminate rather than being
    /// misreported as a denied Full Disk Access grant.
    public static func classify(error: Error?) -> FullDiskAccessProbeResult {
        guard let error else { return .accessible }
        let cocoaError = error as NSError
        if cocoaError.domain == NSPOSIXErrorDomain {
            return classify(errno: Int32(cocoaError.code))
        }
        if cocoaError.domain == NSCocoaErrorDomain,
           cocoaError.code == CocoaError.Code.fileReadNoPermission.rawValue {
            return .permissionDenied
        }
        return .indeterminate
    }
}
