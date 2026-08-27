import Darwin
import Foundation

public struct MountedInstallerVolume: Codable, Equatable, Identifiable, Sendable {
    public let sourceURL: URL
    public let mountURL: URL
    public let deviceEntry: String
    public let imageType: String
    public let imageBytes: Int64?
    public let sourceExists: Bool

    public var id: String { deviceEntry + "|" + mountURL.path }
    public var displayName: String { mountURL.lastPathComponent }

    public init(
        sourceURL: URL,
        mountURL: URL,
        deviceEntry: String,
        imageType: String,
        imageBytes: Int64?,
        sourceExists: Bool
    ) {
        self.sourceURL = sourceURL.standardizedFileURL
        self.mountURL = mountURL.standardizedFileURL
        self.deviceEntry = deviceEntry
        self.imageType = imageType
        self.imageBytes = imageBytes
        self.sourceExists = sourceExists
    }
}

public enum MountedInstallerProbeError: LocalizedError, Equatable {
    case invalidOutput
    case invalidPropertyList

    public var errorDescription: String? {
        switch self {
        case .invalidOutput:
            return "系统没有返回可读取的磁盘映像信息。"
        case .invalidPropertyList:
            return "系统返回的磁盘映像信息格式无效。"
        }
    }
}

/// Discovers user-owned installer disk images without traversing arbitrary
/// external disks. Discovery is read-only; ejecting is a separate, explicit UI
/// action that must revalidate the live identity first.
public struct MountedInstallerProbe: Sendable {
    public static let hdiutilURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
    private static let installerImageExtensions = Set(["dmg", "iso"])
    private static let installerArtifactExtensions = Set(["app", "pkg", "mpkg"])

    public init() {}

    public func discover(using runner: CommandRunner = CommandRunner()) async throws -> [MountedInstallerVolume] {
        let result = try await runner.runChecked(
            executable: Self.hdiutilURL,
            arguments: ["info", "-plist"],
            timeout: 10
        )
        guard let data = result.standardOutput.data(using: .utf8), !data.isEmpty else {
            throw MountedInstallerProbeError.invalidOutput
        }
        return try Self.parse(
            plistData: data,
            volumeRoot: URL(fileURLWithPath: "/Volumes", isDirectory: true),
            currentUserID: getuid()
        )
    }

    static func parse(
        plistData: Data,
        volumeRoot: URL,
        currentUserID: uid_t,
        fileManager: FileManager = .default
    ) throws -> [MountedInstallerVolume] {
        let info: HDIInfo
        do {
            info = try PropertyListDecoder().decode(HDIInfo.self, from: plistData)
        } catch {
            throw MountedInstallerProbeError.invalidPropertyList
        }

        var discovered: [MountedInstallerVolume] = []
        for image in info.images {
            guard image.ownerUserID == UInt32(currentUserID),
                  image.removable != false else { continue }

            let sourceURL = URL(fileURLWithPath: image.imagePath).standardizedFileURL
            guard installerImageExtensions.contains(sourceURL.pathExtension.lowercased()) else {
                continue
            }

            for entity in image.systemEntities {
                guard let mountPoint = entity.mountPoint,
                      let deviceEntry = entity.deviceEntry else { continue }
                let mountURL = URL(fileURLWithPath: mountPoint, isDirectory: true).standardizedFileURL
                guard isStrictDescendant(mountURL, of: volumeRoot),
                      containsInstallerArtifact(at: mountURL, fileManager: fileManager) else {
                    continue
                }

                discovered.append(
                    MountedInstallerVolume(
                        sourceURL: sourceURL,
                        mountURL: mountURL,
                        deviceEntry: deviceEntry,
                        imageType: image.imageType ?? "disk image",
                        imageBytes: image.byteCount,
                        sourceExists: fileManager.fileExists(atPath: sourceURL.path)
                    )
                )
            }
        }

        return discovered.sorted {
            if $0.displayName != $1.displayName {
                return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            return $0.mountURL.path < $1.mountURL.path
        }
    }

    public static func hasSameLiveIdentity(
        _ candidate: MountedInstallerVolume,
        _ live: MountedInstallerVolume
    ) -> Bool {
        candidate.deviceEntry == live.deviceEntry
            && candidate.mountURL.standardizedFileURL == live.mountURL.standardizedFileURL
            && candidate.sourceURL.standardizedFileURL == live.sourceURL.standardizedFileURL
    }

    public static func isSafeEjectTarget(_ volume: MountedInstallerVolume) -> Bool {
        isStrictDescendant(
            volume.mountURL,
            of: URL(fileURLWithPath: "/Volumes", isDirectory: true)
        ) && volume.deviceEntry.range(
            of: #"^/dev/disk[0-9]+(?:s[0-9]+)?$"#,
            options: .regularExpression
        ) != nil
    }

    private static func containsInstallerArtifact(
        at mountURL: URL,
        fileManager: FileManager
    ) -> Bool {
        guard let children = try? fileManager.contentsOfDirectory(
            at: mountURL,
            includingPropertiesForKeys: [.isPackageKey],
            options: [.skipsHiddenFiles]
        ) else { return false }
        return children.contains {
            installerArtifactExtensions.contains($0.pathExtension.lowercased())
        }
    }

    private static func isStrictDescendant(_ url: URL, of root: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        return path != rootPath && path.hasPrefix(rootPath + "/")
    }
}

private struct HDIInfo: Decodable {
    let images: [HDIImage]
}

private struct HDIImage: Decodable {
    let imagePath: String
    let imageType: String?
    let blockCount: Int64?
    let blockSize: Int64?
    let removable: Bool?
    let ownerUserID: UInt32?
    let systemEntities: [HDISystemEntity]

    var byteCount: Int64? {
        guard let blockCount, let blockSize,
              blockCount > 0, blockSize > 0,
              blockCount <= Int64.max / blockSize else { return nil }
        return blockCount * blockSize
    }

    enum CodingKeys: String, CodingKey {
        case imagePath = "image-path"
        case imageType = "image-type"
        case blockCount = "blockcount"
        case blockSize = "blocksize"
        case removable
        case ownerUserID = "owner-uid"
        case systemEntities = "system-entities"
    }
}

private struct HDISystemEntity: Decodable {
    let deviceEntry: String?
    let mountPoint: String?

    enum CodingKeys: String, CodingKey {
        case deviceEntry = "dev-entry"
        case mountPoint = "mount-point"
    }
}
