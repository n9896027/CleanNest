import Darwin
import Foundation
import XCTest
@testable import CleanNestCore

final class MountedInstallerVolumeTests: XCTestCase {
    func testProbeKeepsOnlyCurrentUsersInstallerImagesMountedUnderVolumeRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNestMountedInstallerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let volumeRoot = root.appendingPathComponent("Volumes", isDirectory: true)
        let installerMount = volumeRoot.appendingPathComponent("测试安装盘", isDirectory: true)
        let documentsMount = volumeRoot.appendingPathComponent("文档镜像", isDirectory: true)
        try FileManager.default.createDirectory(
            at: installerMount.appendingPathComponent("Utility.app", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: documentsMount, withIntermediateDirectories: true)
        try Data("notes".utf8).write(to: documentsMount.appendingPathComponent("README.txt"))

        let source = root.appendingPathComponent("Utility.dmg")
        try Data(repeating: 0x41, count: 32).write(to: source)
        let plist = try makeInfoPlist(
            images: [
                image(
                    source: source,
                    owner: getuid(),
                    mount: installerMount,
                    device: "/dev/disk40s1"
                ),
                image(
                    source: root.appendingPathComponent("Documents.dmg"),
                    owner: getuid(),
                    mount: documentsMount,
                    device: "/dev/disk41s1"
                ),
                image(
                    source: root.appendingPathComponent("OtherUser.dmg"),
                    owner: getuid() + 1,
                    mount: installerMount,
                    device: "/dev/disk42s1"
                )
            ]
        )

        let result = try MountedInstallerProbe.parse(
            plistData: plist,
            volumeRoot: volumeRoot,
            currentUserID: getuid()
        )

        XCTAssertEqual(result.count, 1)
        let volume = try XCTUnwrap(result.first)
        XCTAssertEqual(volume.sourceURL, source)
        XCTAssertEqual(volume.mountURL, installerMount)
        XCTAssertEqual(volume.deviceEntry, "/dev/disk40s1")
        XCTAssertEqual(volume.imageBytes, 2_048)
        XCTAssertTrue(volume.sourceExists)
    }

    func testProbeReportsMissingSourceAndEjectValidationFailsClosed() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNestMountedInstallerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let volumeRoot = root.appendingPathComponent("Volumes", isDirectory: true)
        let mount = volumeRoot.appendingPathComponent("仅剩挂载卷", isDirectory: true)
        try FileManager.default.createDirectory(
            at: mount.appendingPathComponent("Launcher.pkg", isDirectory: true),
            withIntermediateDirectories: true
        )
        let source = root.appendingPathComponent("Missing.dmg")
        let plist = try makeInfoPlist(
            images: [image(source: source, owner: getuid(), mount: mount, device: "/dev/disk50")]
        )
        let result = try MountedInstallerProbe.parse(
            plistData: plist,
            volumeRoot: volumeRoot,
            currentUserID: getuid()
        )
        let volume = try XCTUnwrap(result.first)

        XCTAssertFalse(volume.sourceExists)
        XCTAssertTrue(MountedInstallerProbe.hasSameLiveIdentity(volume, volume))

        let unsafe = MountedInstallerVolume(
            sourceURL: source,
            mountURL: URL(fileURLWithPath: "/Users/example/Desktop", isDirectory: true),
            deviceEntry: "/dev/disk50;rm",
            imageType: "disk image",
            imageBytes: nil,
            sourceExists: false
        )
        XCTAssertFalse(MountedInstallerProbe.isSafeEjectTarget(unsafe))
    }

    private func makeInfoPlist(images: [[String: Any]]) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: ["images": images],
            format: .xml,
            options: 0
        )
    }

    private func image(
        source: URL,
        owner: uid_t,
        mount: URL,
        device: String
    ) -> [String: Any] {
        [
            "image-path": source.path,
            "image-type": "read-only disk image",
            "blockcount": 4,
            "blocksize": 512,
            "removable": true,
            "owner-uid": Int(owner),
            "system-entities": [
                ["dev-entry": device, "mount-point": mount.path]
            ]
        ]
    }
}
