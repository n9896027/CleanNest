import AppKit
import CleanNestCore
import CleanNestMutation
import Foundation

/// Uses an atomic rename when the current account already has permission, then
/// falls back to Finder for cross-volume or administrator-authorized moves.
/// Keeping Apple Events in the GUI target avoids adding mutation or privileged
/// surfaces to the read-only CleanNestMCP executable through CleanNestCore.
enum WorkspaceApplicationRecycler {
    static let recycle: TrashService.ApplicationRecycler = { request in
        do {
            return try AtomicApplicationTrashMover.move(request)
        } catch {
            let nsError = error as NSError
            guard shouldAskFinderToRecycle(nsError) else { throw error }
            return try await recycleThroughFinder(request)
        }
    }

    private static func shouldAskFinderToRecycle(_ error: NSError) -> Bool {
        if error.domain == NSPOSIXErrorDomain {
            return error.code == Int(EACCES)
                || error.code == Int(EPERM)
                || error.code == Int(EXDEV)
        }
        return error.domain == NSCocoaErrorDomain
            && (error.code == NSFileWriteNoPermissionError
                || error.code == NSFileReadNoPermissionError)
    }

    private static func recycleThroughFinder(
        _ request: ApplicationTrashRequest
    ) async throws -> URL? {
        try await Task.detached(priority: .userInitiated) {
            try AtomicApplicationTrashMover.validateSource(request)
            let literal = try appleScriptStringLiteral(request.source.path)
            let source = """
            tell application id "com.apple.finder"
                set movedItem to delete (POSIX file \(literal))
                return POSIX path of (movedItem as alias)
            end tell
            """
            guard let script = NSAppleScript(source: source) else {
                throw NSError(
                    domain: NSOSStatusErrorDomain,
                    code: Int(errOSASystemError),
                    userInfo: [NSLocalizedDescriptionKey: "无法创建 Finder 废纸篓请求。"]
                )
            }

            var details: NSDictionary?
            let result = script.executeAndReturnError(&details)
            if let details {
                let code = (details[NSAppleScript.errorNumber] as? NSNumber)?.intValue
                    ?? Int(errOSASystemError)
                let message = (details[NSAppleScript.errorMessage] as? String)
                    ?? (details[NSAppleScript.errorBriefMessage] as? String)
                    ?? "Finder 未能完成废纸篓操作。"
                throw NSError(
                    domain: NSOSStatusErrorDomain,
                    code: code,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }

            let reportedDestination = result.stringValue.flatMap { path -> URL? in
                guard !path.isEmpty else { return nil }
                return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            }

            for _ in 0..<20 {
                if let destination = AtomicApplicationTrashMover.findMovedItem(
                    in: request.trashDirectory,
                    matching: request.expectedIdentity
                ) {
                    return destination
                }
                let delay: UInt64 = FileManager.default.fileExists(atPath: request.source.path)
                    ? 50_000_000
                    : 20_000_000
                try await Task.sleep(nanoseconds: delay)
            }

            if let reportedDestination,
               !FileManager.default.fileExists(atPath: request.source.path),
               reportedDestination.resolvingSymlinksInPath().deletingLastPathComponent()
                == request.trashDirectory.resolvingSymlinksInPath(),
               request.expectedBundleIdentifier == nil
                || Bundle(url: reportedDestination)?.bundleIdentifier == request.expectedBundleIdentifier {
                return reportedDestination
            }
            return nil
        }.value
    }

    private static func appleScriptStringLiteral(_ value: String) throws -> String {
        let hasControlCharacters = value.unicodeScalars.contains {
            $0.value < 0x20 || $0.value == 0x7f
        }
        guard !hasControlCharacters else {
            throw SafePathError.invalidApplication
        }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
