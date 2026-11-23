import CryptoKit
import Darwin
import Foundation
import UniformTypeIdentifiers

public enum ScreenshotNameClassifier {
    private static let compactPrefixes = [
        "screenshot",
        "screencapture",
        "截屏",
        "截图"
    ]

    /// Matches filename conventions used by macOS and common screenshot tools.
    /// Parent folders are intentionally ignored so unrelated images inside a
    /// folder named “Screenshots” are never reclassified automatically.
    public static func matches(_ url: URL) -> Bool {
        matches(filename: url.lastPathComponent)
    }

    public static func matches(filename: String) -> Bool {
        let stem = (filename as NSString).deletingPathExtension
        let folded = stem.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        var compact = ""
        for scalar in folded.unicodeScalars where CharacterSet.alphanumerics.contains(scalar) {
            compact.unicodeScalars.append(scalar)
        }
        return compactPrefixes.contains { compact.hasPrefix($0) }
    }
}

public struct DownloadMediaScanConfiguration: Sendable {
    public let maximumDepth: Int
    public let maximumFiles: Int
    public let maximumHashCandidates: Int
    public let minimumDuplicateBytes: Int64
    public let mediaMinimumAgeDays: Int
    public let minimumImageBytes: Int64
    public let minimumVideoBytes: Int64
    public let minimumAudioBytes: Int64

    public init(
        maximumDepth: Int = 4,
        maximumFiles: Int = 25_000,
        maximumHashCandidates: Int = 3_000,
        minimumDuplicateBytes: Int64 = 1_048_576,
        mediaMinimumAgeDays: Int = 14,
        minimumImageBytes: Int64 = 5 * 1_048_576,
        minimumVideoBytes: Int64 = 100 * 1_048_576,
        minimumAudioBytes: Int64 = 20 * 1_048_576
    ) {
        self.maximumDepth = max(1, min(maximumDepth, 8))
        self.maximumFiles = max(100, min(maximumFiles, 100_000))
        self.maximumHashCandidates = max(20, min(maximumHashCandidates, 20_000))
        self.minimumDuplicateBytes = max(1, minimumDuplicateBytes)
        self.mediaMinimumAgeDays = max(0, mediaMinimumAgeDays)
        self.minimumImageBytes = max(1, minimumImageBytes)
        self.minimumVideoBytes = max(1, minimumVideoBytes)
        self.minimumAudioBytes = max(1, minimumAudioBytes)
    }
}

public struct CleanupScanInsights: Codable, Equatable, Sendable {
    public static let empty = CleanupScanInsights()

    public let examinedFileCount: Int
    public let installerCount: Int
    public let archiveCount: Int
    public let imageCount: Int
    public let videoCount: Int
    public let audioCount: Int
    public let duplicateGroupCount: Int
    public let duplicateFileCount: Int
    public let duplicateBytes: Int64
    public let skippedCloudItemCount: Int
    public let skippedSymbolicLinkCount: Int
    public let skippedPackageCount: Int
    public let skippedUnreadableItemCount: Int
    public let skippedDepthLimitCount: Int
    public let skippedUnsafeRootCount: Int
    public let reachedFileLimit: Bool
    public let reachedHashLimit: Bool

    private enum CodingKeys: String, CodingKey {
        case examinedFileCount
        case installerCount
        case archiveCount
        case imageCount
        case videoCount
        case audioCount
        case duplicateGroupCount
        case duplicateFileCount
        case duplicateBytes
        case skippedCloudItemCount
        case skippedSymbolicLinkCount
        case skippedPackageCount
        case skippedUnreadableItemCount
        case skippedDepthLimitCount
        case skippedUnsafeRootCount
        case reachedFileLimit
        case reachedHashLimit
    }

    public var mediaCount: Int { imageCount + videoCount + audioCount }
    public var wasLimited: Bool { reachedFileLimit || reachedHashLimit }

    public var skippedItemCount: Int {
        [
            skippedCloudItemCount,
            skippedSymbolicLinkCount,
            skippedPackageCount,
            skippedUnreadableItemCount,
            skippedDepthLimitCount,
            skippedUnsafeRootCount
        ].reduce(0, Self.saturatingAdd)
    }

    public init(
        examinedFileCount: Int = 0,
        installerCount: Int = 0,
        archiveCount: Int = 0,
        imageCount: Int = 0,
        videoCount: Int = 0,
        audioCount: Int = 0,
        duplicateGroupCount: Int = 0,
        duplicateFileCount: Int = 0,
        duplicateBytes: Int64 = 0,
        skippedCloudItemCount: Int = 0,
        skippedSymbolicLinkCount: Int = 0,
        skippedPackageCount: Int = 0,
        skippedUnreadableItemCount: Int = 0,
        skippedDepthLimitCount: Int = 0,
        skippedUnsafeRootCount: Int = 0,
        reachedFileLimit: Bool = false,
        reachedHashLimit: Bool = false
    ) {
        self.examinedFileCount = examinedFileCount
        self.installerCount = installerCount
        self.archiveCount = archiveCount
        self.imageCount = imageCount
        self.videoCount = videoCount
        self.audioCount = audioCount
        self.duplicateGroupCount = duplicateGroupCount
        self.duplicateFileCount = duplicateFileCount
        self.duplicateBytes = duplicateBytes
        self.skippedCloudItemCount = skippedCloudItemCount
        self.skippedSymbolicLinkCount = skippedSymbolicLinkCount
        self.skippedPackageCount = skippedPackageCount
        self.skippedUnreadableItemCount = skippedUnreadableItemCount
        self.skippedDepthLimitCount = skippedDepthLimitCount
        self.skippedUnsafeRootCount = skippedUnsafeRootCount
        self.reachedFileLimit = reachedFileLimit
        self.reachedHashLimit = reachedHashLimit
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            examinedFileCount: try values.decode(Int.self, forKey: .examinedFileCount),
            installerCount: try values.decode(Int.self, forKey: .installerCount),
            archiveCount: try values.decode(Int.self, forKey: .archiveCount),
            imageCount: try values.decode(Int.self, forKey: .imageCount),
            videoCount: try values.decode(Int.self, forKey: .videoCount),
            audioCount: try values.decode(Int.self, forKey: .audioCount),
            duplicateGroupCount: try values.decode(Int.self, forKey: .duplicateGroupCount),
            duplicateFileCount: try values.decode(Int.self, forKey: .duplicateFileCount),
            duplicateBytes: try values.decode(Int64.self, forKey: .duplicateBytes),
            skippedCloudItemCount: try values.decode(Int.self, forKey: .skippedCloudItemCount),
            skippedSymbolicLinkCount: try values.decodeIfPresent(Int.self, forKey: .skippedSymbolicLinkCount) ?? 0,
            skippedPackageCount: try values.decodeIfPresent(Int.self, forKey: .skippedPackageCount) ?? 0,
            skippedUnreadableItemCount: try values.decodeIfPresent(Int.self, forKey: .skippedUnreadableItemCount) ?? 0,
            skippedDepthLimitCount: try values.decodeIfPresent(Int.self, forKey: .skippedDepthLimitCount) ?? 0,
            skippedUnsafeRootCount: try values.decodeIfPresent(Int.self, forKey: .skippedUnsafeRootCount) ?? 0,
            reachedFileLimit: try values.decode(Bool.self, forKey: .reachedFileLimit),
            reachedHashLimit: try values.decode(Bool.self, forKey: .reachedHashLimit)
        )
    }

    public func updatingCandidateCounts(from candidates: [CleanupCandidate]) -> CleanupScanInsights {
        let personalCandidates = candidates.filter { $0.kind.isPersonalFile }
        let duplicateCandidates = personalCandidates.filter { $0.duplicateEvidence != nil }
        return CleanupScanInsights(
            examinedFileCount: examinedFileCount,
            installerCount: personalCandidates.filter { $0.kind == .installer }.count,
            archiveCount: personalCandidates.filter { $0.kind == .archive }.count,
            imageCount: personalCandidates.filter { $0.kind == .image || $0.kind == .screenshot }.count,
            videoCount: personalCandidates.filter { $0.kind == .video }.count,
            audioCount: personalCandidates.filter { $0.kind == .audio }.count,
            duplicateGroupCount: Set(duplicateCandidates.compactMap { $0.duplicateEvidence?.groupID }).count,
            duplicateFileCount: duplicateCandidates.count,
            duplicateBytes: duplicateCandidates.reduce(0) { $0 + $1.allocatedBytes },
            skippedCloudItemCount: skippedCloudItemCount,
            skippedSymbolicLinkCount: skippedSymbolicLinkCount,
            skippedPackageCount: skippedPackageCount,
            skippedUnreadableItemCount: skippedUnreadableItemCount,
            skippedDepthLimitCount: skippedDepthLimitCount,
            skippedUnsafeRootCount: skippedUnsafeRootCount,
            reachedFileLimit: reachedFileLimit,
            reachedHashLimit: reachedHashLimit
        )
    }

    public func mergingTraversalEvidence(_ other: CleanupScanInsights) -> CleanupScanInsights {
        CleanupScanInsights(
            examinedFileCount: Self.saturatingAdd(examinedFileCount, other.examinedFileCount),
            installerCount: Self.saturatingAdd(installerCount, other.installerCount),
            archiveCount: Self.saturatingAdd(archiveCount, other.archiveCount),
            imageCount: Self.saturatingAdd(imageCount, other.imageCount),
            videoCount: Self.saturatingAdd(videoCount, other.videoCount),
            audioCount: Self.saturatingAdd(audioCount, other.audioCount),
            duplicateGroupCount: Self.saturatingAdd(duplicateGroupCount, other.duplicateGroupCount),
            duplicateFileCount: Self.saturatingAdd(duplicateFileCount, other.duplicateFileCount),
            duplicateBytes: Self.saturatingAdd(duplicateBytes, other.duplicateBytes),
            skippedCloudItemCount: Self.saturatingAdd(skippedCloudItemCount, other.skippedCloudItemCount),
            skippedSymbolicLinkCount: Self.saturatingAdd(skippedSymbolicLinkCount, other.skippedSymbolicLinkCount),
            skippedPackageCount: Self.saturatingAdd(skippedPackageCount, other.skippedPackageCount),
            skippedUnreadableItemCount: Self.saturatingAdd(skippedUnreadableItemCount, other.skippedUnreadableItemCount),
            skippedDepthLimitCount: Self.saturatingAdd(skippedDepthLimitCount, other.skippedDepthLimitCount),
            skippedUnsafeRootCount: Self.saturatingAdd(skippedUnsafeRootCount, other.skippedUnsafeRootCount),
            reachedFileLimit: reachedFileLimit || other.reachedFileLimit,
            reachedHashLimit: reachedHashLimit || other.reachedHashLimit
        )
    }

    private static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        guard rhs > 0 else { return max(0, lhs) }
        return lhs > Int.max - rhs ? Int.max : lhs + rhs
    }

    private static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        guard rhs > 0 else { return max(0, lhs) }
        return lhs > Int64.max - rhs ? Int64.max : lhs + rhs
    }
}

public struct DownloadMediaScanResult: Sendable {
    public let candidates: [CleanupCandidate]
    public let insights: CleanupScanInsights
    public let roots: [CleanupScanRootEvidence]
    public let issues: [CleanupScanIssue]

    public init(
        candidates: [CleanupCandidate],
        insights: CleanupScanInsights,
        roots: [CleanupScanRootEvidence] = [],
        issues: [CleanupScanIssue] = []
    ) {
        self.candidates = candidates
        self.insights = insights
        self.roots = roots
        self.issues = issues
    }
}

public enum ZIPArchiveClassification: Equatable, Sendable {
    case installerLike
    case generic
    case unreadable
}

public enum ZIPCentralDirectoryInspector {
    private static let maximumTailBytes = 8 * 1_048_576

    public static func classify(_ url: URL) -> ZIPArchiveClassification {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let fileSize = try handle.seekToEnd()
            let readCount = min(UInt64(maximumTailBytes), fileSize)
            try handle.seek(toOffset: fileSize - readCount)
            guard let data = try handle.read(upToCount: Int(readCount)), !data.isEmpty else {
                return .unreadable
            }
            return classifyCentralDirectoryBytes(data)
        } catch {
            return .unreadable
        }
    }

    static func classifyCentralDirectoryBytes(_ data: Data) -> ZIPArchiveClassification {
        let bytes = [UInt8](data)
        var index = 0
        var foundCentralEntry = false

        while index + 46 <= bytes.count {
            guard bytes[index] == 0x50,
                  bytes[index + 1] == 0x4b,
                  bytes[index + 2] == 0x01,
                  bytes[index + 3] == 0x02 else {
                index += 1
                continue
            }

            let nameLength = Int(littleEndianUInt16(bytes, at: index + 28))
            let extraLength = Int(littleEndianUInt16(bytes, at: index + 30))
            let commentLength = Int(littleEndianUInt16(bytes, at: index + 32))
            let entryLength = 46 + nameLength + extraLength + commentLength
            guard nameLength > 0, index + entryLength <= bytes.count else {
                index += 4
                continue
            }

            foundCentralEntry = true
            let nameStart = index + 46
            let name = String(decoding: bytes[nameStart..<(nameStart + nameLength)], as: UTF8.self)
                .lowercased()
            let components = name.split(separator: "/").map(String.init)
            if components.contains(where: { $0.hasSuffix(".app") })
                || components.contains(where: { $0.hasSuffix(".pkg") || $0.hasSuffix(".mpkg") })
                || name.hasSuffix(".dmg")
                || name.hasSuffix(".xip") {
                return .installerLike
            }
            index += entryLength
        }

        return foundCentralEntry ? .generic : .unreadable
    }

    private static func littleEndianUInt16(_ bytes: [UInt8], at index: Int) -> UInt16 {
        UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
    }
}

public enum FileContentHasher {
    private static let quickChunkBytes = 64 * 1_024
    private static let fullChunkBytes = 256 * 1_024

    /// A bounded first pass for duplicate discovery. Matching this value is
    /// never treated as proof: candidates still receive a full SHA-256 before
    /// CleanNest presents them as exact duplicates.
    public static func quickFingerprint(of url: URL) throws -> String {
        try Task.checkCancellation()
        let descriptor = try openReadOnlyDescriptor(for: url)
        defer { Darwin.close(descriptor) }
        let fileStat = try regularFileStat(descriptor: descriptor, url: url)
        let fileSize = UInt64(fileStat.st_size)
        var encodedSize = fileSize.bigEndian
        var hasher = SHA256()
        withUnsafeBytes(of: &encodedSize) { bytes in
            hasher.update(bufferPointer: bytes)
        }

        let headCount = Int(min(UInt64(quickChunkBytes), fileSize))
        let buffer = UnsafeMutableRawBufferPointer.allocate(
            byteCount: max(headCount, 1),
            alignment: 16
        )
        defer { buffer.deallocate() }
        if headCount > 0 {
            let count = try preadFully(
                descriptor: descriptor,
                into: buffer,
                count: headCount,
                offset: 0,
                url: url
            )
            hasher.update(
                bufferPointer: UnsafeRawBufferPointer(start: buffer.baseAddress, count: count)
            )
        }

        if fileSize > UInt64(quickChunkBytes) {
            try Task.checkCancellation()
            let tailCount = Int(min(UInt64(quickChunkBytes), fileSize))
            let count = try preadFully(
                descriptor: descriptor,
                into: buffer,
                count: tailCount,
                offset: off_t(fileSize - UInt64(tailCount)),
                url: url
            )
            hasher.update(
                bufferPointer: UnsafeRawBufferPointer(start: buffer.baseAddress, count: count)
            )
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256(of url: URL) throws -> String {
        try Task.checkCancellation()
        let descriptor = try openReadOnlyDescriptor(for: url)
        defer { Darwin.close(descriptor) }
        _ = try regularFileStat(descriptor: descriptor, url: url)
        let buffer = UnsafeMutableRawBufferPointer.allocate(
            byteCount: fullChunkBytes,
            alignment: 16
        )
        defer { buffer.deallocate() }
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            let bytesRead = Darwin.read(descriptor, buffer.baseAddress, buffer.count)
            if bytesRead == 0 { break }
            if bytesRead < 0 {
                if errno == EINTR { continue }
                throw posixError(for: url)
            }
            hasher.update(
                bufferPointer: UnsafeRawBufferPointer(
                    start: buffer.baseAddress,
                    count: bytesRead
                )
            )
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func openReadOnlyDescriptor(for url: URL) throws -> Int32 {
        let descriptor = url.path.withCString {
            Darwin.open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else { throw posixError(for: url) }
        return descriptor
    }

    private static func regularFileStat(descriptor: Int32, url: URL) throws -> stat {
        var value = stat()
        guard fstat(descriptor, &value) == 0 else { throw posixError(for: url) }
        guard (value.st_mode & S_IFMT) == S_IFREG, value.st_size >= 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(EINVAL),
                userInfo: [NSFilePathErrorKey: url.path]
            )
        }
        return value
    }

    private static func preadFully(
        descriptor: Int32,
        into buffer: UnsafeMutableRawBufferPointer,
        count: Int,
        offset: off_t,
        url: URL
    ) throws -> Int {
        var total = 0
        while total < count {
            try Task.checkCancellation()
            let bytesRead = Darwin.pread(
                descriptor,
                buffer.baseAddress?.advanced(by: total),
                count - total,
                offset + off_t(total)
            )
            if bytesRead == 0 { break }
            if bytesRead < 0 {
                if errno == EINTR { continue }
                throw posixError(for: url)
            }
            total += bytesRead
        }
        guard total == count else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(EIO),
                userInfo: [NSFilePathErrorKey: url.path]
            )
        }
        return total
    }

    private static func posixError(for url: URL) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(errno),
            userInfo: [NSFilePathErrorKey: url.path]
        )
    }
}

public enum CleanupEvidenceError: LocalizedError, Equatable {
    case notRegularFile
    case targetChanged
    case retainedCopyChanged
    case duplicateContentChanged

    public var errorDescription: String? {
        switch self {
        case .notRegularFile:
            return "目标已不再是扫描时的普通文件，本次操作已停止。"
        case .targetChanged:
            return "文件在扫描后发生了变化，请重新扫描后再决定。"
        case .retainedCopyChanged:
            return "计划保留的重复副本已移动或变化，为避免删掉最后一份，本次操作已停止。"
        case .duplicateContentChanged:
            return "重复文件的内容已变化，SHA-256 复核未通过，本次操作已停止。"
        }
    }
}

public extension CleanupFileIdentity {
    static func capture(at url: URL) throws -> CleanupFileIdentity {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw CleanupEvidenceError.notRegularFile
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let deviceID = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
              let fileID = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
              let logicalBytes = (attributes[.size] as? NSNumber)?.int64Value else {
            throw CleanupEvidenceError.notRegularFile
        }
        return CleanupFileIdentity(
            deviceID: deviceID,
            fileID: fileID,
            logicalBytes: logicalBytes,
            modifiedAt: attributes[.modificationDate] as? Date
        )
    }
}

public enum CleanupEvidenceValidator {
    public static func validate(_ candidate: CleanupCandidate) throws {
        if let expectedIdentity = candidate.fileIdentity {
            guard try CleanupFileIdentity.capture(at: candidate.url) == expectedIdentity else {
                throw CleanupEvidenceError.targetChanged
            }
        }
        guard let duplicate = candidate.duplicateEvidence else { return }

        guard try CleanupFileIdentity.capture(at: duplicate.retainedURL) == duplicate.retainedIdentity else {
            throw CleanupEvidenceError.retainedCopyChanged
        }
        let candidateDigest = try FileContentHasher.sha256(of: candidate.url)
        let retainedDigest = try FileContentHasher.sha256(of: duplicate.retainedURL)
        guard candidateDigest == duplicate.contentSHA256,
              retainedDigest == duplicate.contentSHA256 else {
            throw CleanupEvidenceError.duplicateContentChanged
        }
    }
}

public struct DownloadMediaScanner: Sendable {
    private enum RootRole: Int, CaseIterable, Sendable {
        case documents = 0
        case pictures = 1
        case movies = 2
        case music = 3
        case desktop = 4
        case downloads = 5

        /// Scan likely screenshot/download locations first so a very large
        /// Documents tree cannot consume the bounded file budget before these
        /// user-requested cleanup surfaces are reached.
        static let scanOrder: [RootRole] = [
            .desktop, .pictures, .downloads, .movies, .music, .documents
        ]

        var directoryName: String {
            switch self {
            case .documents: return "Documents"
            case .pictures: return "Pictures"
            case .movies: return "Movies"
            case .music: return "Music"
            case .desktop: return "Desktop"
            case .downloads: return "Downloads"
            }
        }

        var displayName: String {
            switch self {
            case .documents: return "文稿"
            case .pictures: return "图片"
            case .movies: return "影片"
            case .music: return "音乐"
            case .desktop: return "桌面"
            case .downloads: return "下载"
            }
        }
    }

    private struct FileRecord: Sendable {
        /// Store only an owned path string. URLs produced by DirectoryEnumerator
        /// may retain prefetched Foundation resource-value caches.
        let path: String
        let rootRole: RootRole
        let logicalBytes: Int64
        let allocatedBytes: Int64
        let modifiedAt: Date?
        let identity: CleanupFileIdentity

        var url: URL { URL(fileURLWithPath: path, isDirectory: false) }

        var stableKeeperRank: (Int, Int, TimeInterval, String) {
            let depth = (path as NSString).pathComponents.count
            let ageRank = modifiedAt?.timeIntervalSince1970 ?? .greatestFiniteMagnitude
            return (rootRole.rawValue, depth, ageRank, path)
        }
    }

    private struct CollectionResult {
        let records: [FileRecord]
        let roots: [CleanupScanRootEvidence]
        let examinedFileCount: Int
        let skippedCloudItems: Int
        let skippedSymbolicLinks: Int
        let skippedPackages: Int
        let skippedUnreadableItems: Int
        let skippedDepthLimits: Int
        let skippedUnsafeRoots: Int
        let reachedFileLimit: Bool
        let issues: [CleanupScanIssue]
    }

    public let homeDirectory: URL
    public let configuration: DownloadMediaScanConfiguration

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        configuration: DownloadMediaScanConfiguration = DownloadMediaScanConfiguration()
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.configuration = configuration
    }

    public func scan(
        includeMediaAndDuplicates: Bool = true,
        now: Date = Date()
    ) async -> DownloadMediaScanResult {
        let homeDirectory = self.homeDirectory
        let configuration = self.configuration
        let worker = Task.detached(priority: .userInitiated) {
            let collection = Self.collectFiles(
                homeDirectory: homeDirectory,
                configuration: configuration,
                includeMediaAndDuplicates: includeMediaAndDuplicates
            )
            var candidatesByPath: [String: CleanupCandidate] = [:]

            for record in collection.records
            where record.rootRole == .desktop || record.rootRole == .downloads {
                if let candidate = Self.installerOrArchiveCandidate(for: record, now: now) {
                    candidatesByPath[record.url.standardizedFileURL.path] = candidate
                }
            }

            if includeMediaAndDuplicates {
                for record in collection.records {
                    if let candidate = Self.mediaCandidate(for: record, now: now, configuration: configuration),
                       candidatesByPath[record.url.standardizedFileURL.path] == nil {
                        candidatesByPath[record.url.standardizedFileURL.path] = candidate
                    }
                }
            }

            var reachedHashLimit = false
            if includeMediaAndDuplicates {
                let duplicateResult = Self.duplicateCandidates(
                    from: collection.records,
                    configuration: configuration
                )
                reachedHashLimit = duplicateResult.reachedHashLimit
                for candidate in duplicateResult.candidates {
                    let path = candidate.url.standardizedFileURL.path
                    if let existing = candidatesByPath[path] {
                        candidatesByPath[path] = Self.mergingDuplicateEvidence(
                            candidate,
                            into: existing
                        )
                    } else {
                        candidatesByPath[path] = candidate
                    }
                }
            }

            let candidates = candidatesByPath.values.sorted {
                if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
                if $0.allocatedBytes != $1.allocatedBytes { return $0.allocatedBytes > $1.allocatedBytes }
                return $0.url.path < $1.url.path
            }
            let baseInsights = CleanupScanInsights(
                examinedFileCount: collection.examinedFileCount,
                skippedCloudItemCount: collection.skippedCloudItems,
                skippedSymbolicLinkCount: collection.skippedSymbolicLinks,
                skippedPackageCount: collection.skippedPackages,
                skippedUnreadableItemCount: collection.skippedUnreadableItems,
                skippedDepthLimitCount: collection.skippedDepthLimits,
                skippedUnsafeRootCount: collection.skippedUnsafeRoots,
                reachedFileLimit: collection.reachedFileLimit,
                reachedHashLimit: reachedHashLimit
            )
            return DownloadMediaScanResult(
                candidates: candidates,
                insights: baseInsights.updatingCandidateCounts(from: candidates),
                roots: collection.roots,
                issues: collection.issues
            )
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func collectFiles(
        homeDirectory: URL,
        configuration: DownloadMediaScanConfiguration,
        includeMediaAndDuplicates: Bool
    ) -> CollectionResult {
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isPackageKey,
            .fileSizeKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        let roles = includeMediaAndDuplicates
            ? RootRole.scanOrder
            : [.desktop, .downloads]
        let roots: [(RootRole, URL)] = roles.map {
            ($0, homeDirectory.appendingPathComponent($0.directoryName, isDirectory: true))
        }
        let rootEvidence = roots.map { role, root in
            CleanupScanRootEvidence(
                name: role.displayName,
                url: root,
                homeDirectory: homeDirectory
            )
        }
        var records: [FileRecord] = []
        var examinedFileCount = 0
        var skippedCloudItems = 0
        var skippedSymbolicLinks = 0
        var skippedPackages = 0
        var skippedUnreadableItems = 0
        var skippedDepthLimits = 0
        var skippedUnsafeRoots = 0
        var reachedFileLimit = false
        var issues: [CleanupScanIssue] = []
        func recordIssue(_ url: URL, _ reason: CleanupScanSkipReason) {
            guard issues.count < CleanupScanIssue.maximumPerScanner else { return }
            issues.append(CleanupScanIssue(url: url, reason: reason))
        }
        let enumerationBatchSize = 256

        for ((role, root), evidence) in zip(roots, rootEvidence) {
            switch evidence.status {
            case .checked:
                break
            case .unsafe:
                skippedUnsafeRoots += 1
                recordIssue(root, .unsafeRoot)
                continue
            case .unreadable:
                skippedUnreadableItems += 1
                recordIssue(root, .unreadable)
                continue
            case .missing:
                continue
            }
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { url, _ in
                    skippedUnreadableItems += 1
                    recordIssue(url, .unreadable)
                    return true
                }
            ) else {
                skippedUnreadableItems += 1
                recordIssue(root, .unreadable)
                continue
            }

            let rootDepth = root.pathComponents.count
            var exhausted = false
            while !exhausted, !reachedFileLimit, !Task.isCancelled {
                autoreleasepool {
                    for _ in 0..<enumerationBatchSize {
                        guard !Task.isCancelled,
                              let url = enumerator.nextObject() as? URL else {
                            exhausted = true
                            break
                        }
                        let depth = url.pathComponents.count - rootDepth
                        guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)) else {
                            skippedUnreadableItems += 1
                            recordIssue(url, .unreadable)
                            continue
                        }

                        if values.isSymbolicLink == true {
                            skippedSymbolicLinks += 1
                            recordIssue(url, .symbolicLink)
                            if values.isDirectory == true { enumerator.skipDescendants() }
                            continue
                        }
                        if values.isDirectory == true {
                            if values.isPackage == true {
                                skippedPackages += 1
                                recordIssue(url, .packageBoundary)
                                enumerator.skipDescendants()
                            } else if depth >= configuration.maximumDepth {
                                skippedDepthLimits += 1
                                recordIssue(url, .depthLimit)
                                enumerator.skipDescendants()
                            }
                            continue
                        }
                        guard values.isRegularFile == true else { continue }
                        examinedFileCount += 1
                        guard depth <= configuration.maximumDepth else {
                            skippedDepthLimits += 1
                            recordIssue(url, .depthLimit)
                            continue
                        }

                        if values.isUbiquitousItem == true,
                           values.ubiquitousItemDownloadingStatus != .current {
                            skippedCloudItems += 1
                            recordIssue(url, .cloudPlaceholder)
                            continue
                        }
                        guard records.count < configuration.maximumFiles else {
                            reachedFileLimit = true
                            recordIssue(root, .fileLimit)
                            exhausted = true
                            break
                        }

                        let logicalBytes = Int64(values.fileSize ?? 0)
                        guard logicalBytes > 0 else { continue }
                        guard let identity = try? CleanupFileIdentity.capture(at: url) else {
                            skippedUnreadableItems += 1
                            recordIssue(url, .unreadable)
                            continue
                        }
                        let allocatedBytes = Int64(
                            values.totalFileAllocatedSize
                                ?? values.fileAllocatedSize
                                ?? values.fileSize
                                ?? 0
                        )
                        records.append(
                            FileRecord(
                                path: (url.path as NSString).standardizingPath,
                                rootRole: role,
                                logicalBytes: logicalBytes,
                                allocatedBytes: max(allocatedBytes, 1),
                                modifiedAt: values.contentModificationDate,
                                identity: identity
                            )
                        )
                    }
                }
            }
            if reachedFileLimit || Task.isCancelled { break }
        }

        return CollectionResult(
            records: records,
            roots: rootEvidence,
            examinedFileCount: examinedFileCount,
            skippedCloudItems: skippedCloudItems,
            skippedSymbolicLinks: skippedSymbolicLinks,
            skippedPackages: skippedPackages,
            skippedUnreadableItems: skippedUnreadableItems,
            skippedDepthLimits: skippedDepthLimits,
            skippedUnsafeRoots: skippedUnsafeRoots,
            reachedFileLimit: reachedFileLimit,
            issues: issues
        )
    }

    private static func installerOrArchiveCandidate(
        for record: FileRecord,
        now: Date
    ) -> CleanupCandidate? {
        let ext = record.url.pathExtension.lowercased()
        let ageDetail = ageDescription(record.modifiedAt, now: now)
        let sourceDetail = "来自\(record.rootRole.displayName)"
        let kind: CleanupKind
        let detail: String

        switch ext {
        case "dmg", "pkg", "xip", "iso":
            kind = .installer
            detail = "安装介质 · \(sourceDetail) · \(ageDetail) · 个人文件，默认不勾选"
        case "zip":
            switch ZIPCentralDirectoryInspector.classify(record.url) {
            case .installerLike:
                kind = .installer
                detail = "ZIP 内含 App 或安装器；只读取了归档目录，未解压 · \(sourceDetail) · \(ageDetail)"
            case .generic:
                guard record.rootRole == .downloads else { return nil }
                kind = .archive
                detail = "普通 ZIP 资料归档；不能仅凭扩展名判断可删除 · \(ageDetail)"
            case .unreadable:
                guard record.rootRole == .downloads else { return nil }
                kind = .archive
                detail = "ZIP 目录无法读取，可能已损坏或加密；需要手动确认 · \(ageDetail)"
            }
        case "tar", "tgz", "gz", "bz2", "xz", "7z", "rar":
            guard record.rootRole == .downloads else { return nil }
            kind = .archive
            detail = "下载的压缩归档；可能包含唯一资料，默认不勾选 · \(ageDetail)"
        default:
            return nil
        }

        return CleanupCandidate(
            name: record.url.lastPathComponent,
            url: record.url,
            kind: kind,
            allocatedBytes: record.allocatedBytes,
            modifiedAt: record.modifiedAt,
            isRecommended: false,
            detail: detail,
            fileIdentity: record.identity
        )
    }

    private static func mediaCandidate(
        for record: FileRecord,
        now: Date,
        configuration: DownloadMediaScanConfiguration
    ) -> CleanupCandidate? {
        guard let kind = mediaKind(for: record.url) else { return nil }

        if kind == .image, ScreenshotNameClassifier.matches(record.url) {
            return CleanupCandidate(
                name: record.url.lastPathComponent,
                url: record.url,
                kind: .screenshot,
                allocatedBytes: record.allocatedBytes,
                modifiedAt: record.modifiedAt,
                isRecommended: false,
                detail: "已按截图命名识别 · 来自\(record.rootRole.displayName) · 不受大图和时间门槛限制，默认不勾选",
                fileIdentity: record.identity
            )
        }

        guard let modifiedAt = record.modifiedAt,
              now.timeIntervalSince(modifiedAt) >= Double(configuration.mediaMinimumAgeDays) * 86_400 else {
            return nil
        }

        let threshold: Int64
        let label: String
        switch kind {
        case .screenshot:
            return nil
        case .image:
            threshold = configuration.minimumImageBytes
            label = "图片"
        case .video:
            threshold = configuration.minimumVideoBytes
            label = "视频"
        case .audio:
            threshold = configuration.minimumAudioBytes
            label = "音频"
        default:
            return nil
        }
        guard record.logicalBytes >= threshold else { return nil }

        return CleanupCandidate(
            name: record.url.lastPathComponent,
            url: record.url,
            kind: kind,
            allocatedBytes: record.allocatedBytes,
            modifiedAt: modifiedAt,
            isRecommended: false,
            detail: "较大的\(label)文件 · 来自\(record.rootRole.displayName) · 仅供手动复核",
            fileIdentity: record.identity
        )
    }

    private static func mediaKind(for url: URL) -> CleanupKind? {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .audio) { return .audio }
        return nil
    }

    private static func duplicateCandidates(
        from records: [FileRecord],
        configuration: DownloadMediaScanConfiguration
    ) -> (candidates: [CleanupCandidate], reachedHashLimit: Bool) {
        let sizeGroups = Dictionary(
            grouping: records.filter { $0.logicalBytes >= configuration.minimumDuplicateBytes },
            by: \FileRecord.logicalBytes
        )
        .filter { $0.value.count > 1 }
        .sorted { $0.key > $1.key }

        var hashedRecordCount = 0
        var reachedHashLimit = false
        var candidates: [CleanupCandidate] = []

        for (_, recordsWithSize) in sizeGroups {
            if Task.isCancelled { break }
            var seenIdentities = Set<String>()
            let uniqueRecords = recordsWithSize.filter {
                seenIdentities.insert("\($0.identity.deviceID):\($0.identity.fileID)").inserted
            }
            guard uniqueRecords.count > 1 else { continue }
            guard hashedRecordCount + uniqueRecords.count <= configuration.maximumHashCandidates else {
                reachedHashLimit = true
                continue
            }
            hashedRecordCount += uniqueRecords.count

            var recordsByQuickFingerprint: [String: [FileRecord]] = [:]
            for record in uniqueRecords {
                if Task.isCancelled { break }
                guard let fingerprint = try? FileContentHasher.quickFingerprint(of: record.url) else { continue }
                recordsByQuickFingerprint[fingerprint, default: []].append(record)
            }

            for quickMatches in recordsByQuickFingerprint.values where quickMatches.count > 1 {
                if Task.isCancelled { break }
                var recordsByDigest: [String: [FileRecord]] = [:]
                for record in quickMatches {
                    if Task.isCancelled { break }
                    guard let digest = try? FileContentHasher.sha256(of: record.url) else { continue }
                    recordsByDigest[digest, default: []].append(record)
                }

                for (digest, matchingRecords) in recordsByDigest where matchingRecords.count > 1 {
                    let sorted = matchingRecords.sorted { $0.stableKeeperRank < $1.stableKeeperRank }
                    guard let retained = sorted.first else { continue }
                    let groupID = "\(digest.prefix(20))-\(retained.logicalBytes)"
                    let evidence = DuplicateFileEvidence(
                        groupID: groupID,
                        contentSHA256: digest,
                        retainedURL: retained.url,
                        retainedIdentity: retained.identity,
                        groupFileCount: sorted.count
                    )
                    for redundant in sorted.dropFirst() {
                        candidates.append(
                            CleanupCandidate(
                                name: redundant.url.lastPathComponent,
                                url: redundant.url,
                                kind: .duplicate,
                                allocatedBytes: redundant.allocatedBytes,
                                modifiedAt: redundant.modifiedAt,
                                isRecommended: false,
                                detail: "与“\(retained.url.lastPathComponent)”字节完全相同；保留该副本，执行前会重新核验 SHA-256",
                                fileIdentity: redundant.identity,
                                duplicateEvidence: evidence
                            )
                        )
                    }
                }
            }
        }

        return (candidates, reachedHashLimit)
    }

    private static func mergingDuplicateEvidence(
        _ duplicate: CleanupCandidate,
        into existing: CleanupCandidate
    ) -> CleanupCandidate {
        CleanupCandidate(
            id: existing.id,
            name: existing.name,
            url: existing.url,
            kind: existing.kind,
            allocatedBytes: existing.allocatedBytes,
            modifiedAt: existing.modifiedAt,
            isRecommended: false,
            detail: "\(existing.detail) · 同时与保留副本字节完全相同",
            fileIdentity: existing.fileIdentity,
            duplicateEvidence: duplicate.duplicateEvidence
        )
    }

    private static func ageDescription(_ modifiedAt: Date?, now: Date) -> String {
        guard let modifiedAt else { return "修改时间未知" }
        let days = max(0, Int(now.timeIntervalSince(modifiedAt) / 86_400))
        if days == 0 { return "今天修改" }
        return "约 \(days) 天未修改"
    }
}
