import CleanNestCore
import Darwin
import Foundation

/// Performs an atomic, collision-safe rename into the current user's Trash.
/// This module is linked only by the GUI target; the read-only MCP executable
/// deliberately has no dependency on it.
public enum AtomicApplicationTrashMover {
    public static func move(_ request: ApplicationTrashRequest) throws -> URL {
        let fileManager = FileManager.default
        let source = request.source.standardizedFileURL
        let trashDirectory = request.trashDirectory.standardizedFileURL

        try validateSource(request)

        if !fileManager.fileExists(atPath: trashDirectory.path) {
            try fileManager.createDirectory(
                at: trashDirectory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
        }
        let trashValues = try trashDirectory.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey
        ])
        guard trashValues.isDirectory == true, trashValues.isSymbolicLink != true else {
            throw SafePathError.protectedPath
        }
        guard deviceID(at: source.deletingLastPathComponent()) == deviceID(at: trashDirectory) else {
            throw POSIXError(.EXDEV)
        }

        for suffix in 1...10_000 {
            let destination = destinationURL(
                for: source,
                in: trashDirectory,
                suffix: suffix
            )
            let result = source.path.withCString { sourcePath in
                destination.path.withCString { destinationPath in
                    renameatx_np(
                        AT_FDCWD,
                        sourcePath,
                        AT_FDCWD,
                        destinationPath,
                        UInt32(RENAME_EXCL)
                    )
                }
            }
            if result == 0 {
                guard !fileManager.fileExists(atPath: source.path),
                      try ApplicationFileIdentity.capture(at: destination) == request.expectedIdentity else {
                    throw ApplicationTrashMoveError.resultNotConfirmed
                }
                return destination
            }

            let code = errno
            if code == EEXIST { continue }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }

        throw POSIXError(.EEXIST)
    }

    public static func validateSource(_ request: ApplicationTrashRequest) throws {
        let fileManager = FileManager.default
        let source = request.source.standardizedFileURL

        guard fileManager.fileExists(atPath: source.path) else {
            throw SafePathError.missing
        }
        if (try? source.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw SafePathError.symbolicLink
        }
        guard try ApplicationFileIdentity.capture(at: source) == request.expectedIdentity else {
            throw SafePathError.applicationChanged
        }
        if let expectedBundleIdentifier = request.expectedBundleIdentifier,
           !expectedBundleIdentifier.isEmpty,
           Bundle(url: source)?.bundleIdentifier != expectedBundleIdentifier {
            throw SafePathError.applicationChanged
        }
    }

    public static func findMovedItem(
        in trashDirectory: URL,
        matching identity: ApplicationFileIdentity
    ) -> URL? {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: trashDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        return children.first { child in
            (try? ApplicationFileIdentity.capture(at: child)) == identity
        }
    }

    private static func destinationURL(
        for source: URL,
        in trashDirectory: URL,
        suffix: Int
    ) -> URL {
        guard suffix > 1 else {
            return trashDirectory.appendingPathComponent(
                source.lastPathComponent,
                isDirectory: true
            )
        }
        let stem = source.deletingPathExtension().lastPathComponent
        let fileExtension = source.pathExtension
        let name = fileExtension.isEmpty
            ? "\(stem) \(suffix)"
            : "\(stem) \(suffix).\(fileExtension)"
        return trashDirectory.appendingPathComponent(name, isDirectory: true)
    }

    private static func deviceID(at url: URL) -> UInt64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.systemNumber] as? NSNumber)?.uint64Value
    }
}

private enum ApplicationTrashMoveError: LocalizedError {
    case resultNotConfirmed

    var errorDescription: String? {
        "原子移动返回后，无法确认目标已经进入废纸篓。"
    }
}
