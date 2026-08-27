import Foundation
import XCTest
@testable import CleanNestCore

final class DownloadMediaScannerTests: XCTestCase {
    func testScreenshotNamesBypassLargeImageAndAgeThresholdsButRemainUnselected() async throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        let screenshot = desktop.appendingPathComponent("ScreenShot_2026-08-26_120000_001.png")
        let localizedScreenshot = desktop.appendingPathComponent("截图 2026-08-26 12.00.01.png")
        let ordinaryImage = desktop.appendingPathComponent("family-photo.png")
        try Data(repeating: 0x11, count: 512).write(to: screenshot)
        try Data(repeating: 0x12, count: 640).write(to: localizedScreenshot)
        try Data(repeating: 0x13, count: 768).write(to: ordinaryImage)

        let scanner = DownloadMediaScanner(
            homeDirectory: home,
            configuration: DownloadMediaScanConfiguration(
                mediaMinimumAgeDays: 14,
                minimumImageBytes: 5 * 1_048_576
            )
        )
        let result = await scanner.scan(includeMediaAndDuplicates: true)
        let screenshots = result.candidates.filter { $0.kind == .screenshot }

        XCTAssertEqual(Set(screenshots.map(\.url)), Set([screenshot, localizedScreenshot]))
        XCTAssertTrue(screenshots.allSatisfy { !$0.isRecommended })
        XCTAssertFalse(result.candidates.contains { $0.url == ordinaryImage })
        XCTAssertEqual(result.insights.imageCount, 2)
        XCTAssertEqual(result.insights.mediaCount, 2)
    }

    func testScreenshotClassifierRecognizesCommonMacNames() {
        XCTAssertTrue(ScreenshotNameClassifier.matches(filename: "Screen Shot 2026-08-26 at 12.30.00.png"))
        XCTAssertTrue(ScreenshotNameClassifier.matches(filename: "Screenshot-2026-08-26.png"))
        XCTAssertTrue(ScreenshotNameClassifier.matches(filename: "ScreenCapture_42.jpg"))
        XCTAssertTrue(ScreenshotNameClassifier.matches(filename: "截屏2026-08-26.png"))
        XCTAssertFalse(ScreenshotNameClassifier.matches(filename: "holiday.png"))
    }

    func testScreenshotRootsAreVisitedBeforeLargeDocumentsTreeConsumesFileBudget() async throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        let documents = home.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let screenshot = desktop.appendingPathComponent("Screenshot 2026-08-26.png")
        try Data([0x01]).write(to: screenshot)
        for index in 0..<120 {
            try Data([UInt8(index % 255)]).write(
                to: documents.appendingPathComponent("document-\(index).bin")
            )
        }

        let scanner = DownloadMediaScanner(
            homeDirectory: home,
            configuration: DownloadMediaScanConfiguration(maximumFiles: 100)
        )
        let result = await scanner.scan(includeMediaAndDuplicates: true)

        XCTAssertTrue(result.insights.reachedFileLimit)
        XCTAssertTrue(result.candidates.contains { $0.url == screenshot && $0.kind == .screenshot })
    }

    func testScannerClassifiesNestedInstallersArchivesAndMediaWithoutRecommendingPersonalFiles() async throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        let nested = downloads.appendingPathComponent("Installers/Old", isDirectory: true)
        let pictures = home.appendingPathComponent("Pictures", isDirectory: true)
        let movies = home.appendingPathComponent("Movies", isDirectory: true)
        let music = home.appendingPathComponent("Music", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pictures, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: movies, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)

        let installerZIP = downloads.appendingPathComponent("Utility.zip")
        let genericZIP = downloads.appendingPathComponent("Documents.zip")
        let nestedDMG = nested.appendingPathComponent("Utility.dmg")
        let image = pictures.appendingPathComponent("large-photo.jpg")
        let video = movies.appendingPathComponent("large-video.mov")
        let audio = music.appendingPathComponent("large-audio.mp3")
        try centralDirectoryData(entryName: "Utility.app/Contents/MacOS/Utility").write(to: installerZIP)
        try centralDirectoryData(entryName: "notes/readme.txt").write(to: genericZIP)
        try Data(repeating: 0x11, count: 41).write(to: nestedDMG)
        try Data(repeating: 0x21, count: 53).write(to: image)
        try Data(repeating: 0x31, count: 67).write(to: video)
        try Data(repeating: 0x41, count: 79).write(to: audio)

        let scanner = DownloadMediaScanner(
            homeDirectory: home,
            configuration: DownloadMediaScanConfiguration(
                maximumDepth: 4,
                maximumFiles: 1_000,
                maximumHashCandidates: 100,
                minimumDuplicateBytes: 10_000,
                mediaMinimumAgeDays: 0,
                minimumImageBytes: 1,
                minimumVideoBytes: 1,
                minimumAudioBytes: 1
            )
        )
        let result = await scanner.scan(includeMediaAndDuplicates: true)
        let candidatesByPath = Dictionary(uniqueKeysWithValues: result.candidates.map { ($0.url.path, $0) })

        XCTAssertEqual(candidatesByPath[installerZIP.path]?.kind, .installer)
        XCTAssertEqual(candidatesByPath[genericZIP.path]?.kind, .archive)
        XCTAssertEqual(candidatesByPath[nestedDMG.path]?.kind, .installer)
        XCTAssertEqual(candidatesByPath[image.path]?.kind, .image)
        XCTAssertEqual(candidatesByPath[video.path]?.kind, .video)
        XCTAssertEqual(candidatesByPath[audio.path]?.kind, .audio)
        XCTAssertTrue(result.candidates.allSatisfy { !$0.isRecommended })
        XCTAssertEqual(result.insights.installerCount, 2)
        XCTAssertEqual(result.insights.archiveCount, 1)
        XCTAssertEqual(result.insights.mediaCount, 3)
    }

    func testDesktopInstallersAreIncludedWithoutTreatingOrdinaryDesktopArchivesAsCleanup() async throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)

        let desktopDMG = desktop.appendingPathComponent("Desktop Utility.dmg")
        let desktopInstallerZIP = desktop.appendingPathComponent("Desktop Utility.zip")
        let desktopDocumentsZIP = desktop.appendingPathComponent("Unique Documents.zip")
        let downloadedDocumentsZIP = downloads.appendingPathComponent("Downloaded Documents.zip")
        try Data(repeating: 0x51, count: 128).write(to: desktopDMG)
        try centralDirectoryData(entryName: "Utility.app/Contents/Info.plist")
            .write(to: desktopInstallerZIP)
        let genericArchive = centralDirectoryData(entryName: "documents/report.pdf")
        try genericArchive.write(to: desktopDocumentsZIP)
        try genericArchive.write(to: downloadedDocumentsZIP)

        let result = await DownloadMediaScanner(homeDirectory: home).scan(
            includeMediaAndDuplicates: false
        )
        let byPath = Dictionary(uniqueKeysWithValues: result.candidates.map { ($0.url.path, $0) })

        XCTAssertEqual(byPath[desktopDMG.path]?.kind, .installer)
        XCTAssertTrue(byPath[desktopDMG.path]?.detail.contains("来自桌面") == true)
        XCTAssertEqual(byPath[desktopInstallerZIP.path]?.kind, .installer)
        XCTAssertNil(byPath[desktopDocumentsZIP.path])
        XCTAssertEqual(byPath[downloadedDocumentsZIP.path]?.kind, .archive)
        XCTAssertEqual(result.insights.installerCount, 2)
        XCTAssertEqual(result.insights.archiveCount, 1)
    }

    func testDuplicateDetectionKeepsStableCopyAndRejectsChangedRetainedFile() async throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let documents = home.appendingPathComponent("Documents", isDirectory: true)
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)

        let retained = documents.appendingPathComponent("original.bin")
        let desktopCopy = desktop.appendingPathComponent("copy-a.bin")
        let downloadCopy = downloads.appendingPathComponent("copy-b.bin")
        let content = Data(repeating: 0x5a, count: 2 * 1_048_576)
        try content.write(to: retained)
        try content.write(to: desktopCopy)
        try content.write(to: downloadCopy)

        let scanner = DownloadMediaScanner(
            homeDirectory: home,
            configuration: DownloadMediaScanConfiguration(
                maximumDepth: 2,
                maximumFiles: 1_000,
                maximumHashCandidates: 100,
                minimumDuplicateBytes: 1_024,
                mediaMinimumAgeDays: 99,
                minimumImageBytes: 10_000_000,
                minimumVideoBytes: 10_000_000,
                minimumAudioBytes: 10_000_000
            )
        )
        let result = await scanner.scan(includeMediaAndDuplicates: true)
        let duplicates = result.candidates.filter { $0.kind == .duplicate }

        XCTAssertEqual(duplicates.count, 2)
        XCTAssertEqual(result.insights.duplicateGroupCount, 1)
        XCTAssertEqual(result.insights.duplicateFileCount, 2)
        XCTAssertTrue(duplicates.allSatisfy { $0.duplicateEvidence?.retainedURL == retained })
        XCTAssertTrue(duplicates.allSatisfy { $0.duplicateEvidence?.groupFileCount == 3 })
        XCTAssertTrue(duplicates.allSatisfy { !$0.isRecommended })
        try CleanupEvidenceValidator.validate(try XCTUnwrap(duplicates.first))

        try FileManager.default.removeItem(at: retained)
        try Data(repeating: 0x7b, count: content.count).write(to: retained)
        XCTAssertThrowsError(try CleanupEvidenceValidator.validate(try XCTUnwrap(duplicates.first))) { error in
            XCTAssertEqual(error as? CleanupEvidenceError, .retainedCopyChanged)
        }
    }

    func testQuickFingerprintCollisionStillRequiresMatchingFullDigest() async throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let documents = home.appendingPathComponent("Documents", isDirectory: true)
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)

        let first = documents.appendingPathComponent("first.bin")
        let second = downloads.appendingPathComponent("second.bin")
        var firstBytes = Data(repeating: 0x31, count: 256 * 1_024)
        var secondBytes = firstBytes
        firstBytes.replaceSubrange((128 * 1_024)..<(128 * 1_024 + 4), with: [0x10, 0x20, 0x30, 0x40])
        secondBytes.replaceSubrange((128 * 1_024)..<(128 * 1_024 + 4), with: [0x50, 0x60, 0x70, 0x80])
        try firstBytes.write(to: first)
        try secondBytes.write(to: second)

        // The cheap stage intentionally samples only the file edges. A match
        // must never be accepted until the complete SHA-256 digest also agrees.
        XCTAssertEqual(
            try FileContentHasher.quickFingerprint(of: first),
            try FileContentHasher.quickFingerprint(of: second)
        )
        XCTAssertNotEqual(
            try FileContentHasher.sha256(of: first),
            try FileContentHasher.sha256(of: second)
        )

        let scanner = DownloadMediaScanner(
            homeDirectory: home,
            configuration: DownloadMediaScanConfiguration(
                maximumDepth: 2,
                maximumFiles: 1_000,
                maximumHashCandidates: 100,
                minimumDuplicateBytes: 1,
                mediaMinimumAgeDays: 99
            )
        )
        let result = await scanner.scan(includeMediaAndDuplicates: true)

        XCTAssertTrue(result.candidates.filter { $0.kind == .duplicate }.isEmpty)
        XCTAssertEqual(result.insights.duplicateGroupCount, 0)
        XCTAssertEqual(result.insights.duplicateFileCount, 0)
    }

    func testChangedDuplicateCandidateIsRejectedBeforeTrash() async throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let documents = home.appendingPathComponent("Documents", isDirectory: true)
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let retained = documents.appendingPathComponent("original.dat")
        let duplicate = downloads.appendingPathComponent("copy.dat")
        let data = Data(repeating: 0x18, count: 1_048_576)
        try data.write(to: retained)
        try data.write(to: duplicate)

        let scanner = DownloadMediaScanner(
            homeDirectory: home,
            configuration: DownloadMediaScanConfiguration(
                maximumDepth: 2,
                maximumFiles: 1_000,
                maximumHashCandidates: 100,
                minimumDuplicateBytes: 1,
                mediaMinimumAgeDays: 99
            )
        )
        let result = await scanner.scan(includeMediaAndDuplicates: true)
        let candidate = try XCTUnwrap(result.candidates.first { $0.kind == .duplicate })
        try FileManager.default.removeItem(at: candidate.url)
        try Data(repeating: 0x27, count: data.count).write(to: candidate.url)

        XCTAssertThrowsError(try CleanupEvidenceValidator.validate(candidate)) { error in
            XCTAssertEqual(error as? CleanupEvidenceError, .targetChanged)
        }

        let trashService = TrashService(
            policy: SafePathPolicy(homeDirectory: home),
            applicationRecycler: { _ in nil }
        )
        let outcomes = await trashService.trashCleanupCandidates([candidate])
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertFalse(try XCTUnwrap(outcomes.first).succeeded)
        XCTAssertEqual(outcomes.first?.failureKind, .targetChanged)
        XCTAssertTrue(FileManager.default.fileExists(atPath: candidate.url.path))
    }

    func testZIPCentralDirectoryClassificationDoesNotTreatGenericArchiveAsInstaller() {
        XCTAssertEqual(
            ZIPCentralDirectoryInspector.classifyCentralDirectoryBytes(
                centralDirectoryData(entryName: "CleanNest.app/Contents/Info.plist")
            ),
            .installerLike
        )
        XCTAssertEqual(
            ZIPCentralDirectoryInspector.classifyCentralDirectoryBytes(
                centralDirectoryData(entryName: "photos/holiday.jpg")
            ),
            .generic
        )
        XCTAssertEqual(
            ZIPCentralDirectoryInspector.classifyCentralDirectoryBytes(Data("not a zip".utf8)),
            .unreadable
        )
    }

    func testDuplicateArchiveKeepsDownloadClassificationAndDuplicateEvidence() async throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let first = downloads.appendingPathComponent("first.zip")
        let second = downloads.appendingPathComponent("second.zip")
        let archive = centralDirectoryData(entryName: "documents/readme.txt")
        try archive.write(to: first)
        try archive.write(to: second)

        let scanner = DownloadMediaScanner(
            homeDirectory: home,
            configuration: DownloadMediaScanConfiguration(
                maximumDepth: 2,
                maximumFiles: 1_000,
                maximumHashCandidates: 100,
                minimumDuplicateBytes: 1,
                mediaMinimumAgeDays: 99
            )
        )
        let result = await scanner.scan(includeMediaAndDuplicates: true)
        let archives = result.candidates.filter { $0.kind == .archive }

        XCTAssertEqual(archives.count, 2)
        XCTAssertEqual(archives.filter { $0.duplicateEvidence != nil }.count, 1)
        XCTAssertEqual(result.insights.archiveCount, 2)
        XCTAssertEqual(result.insights.duplicateGroupCount, 1)
        XCTAssertEqual(result.insights.duplicateFileCount, 1)
    }

    func testPersonalCandidateUsesDedicatedEvidenceBoundedPathWithoutExpandingCachePolicy() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let pictures = home.appendingPathComponent("Pictures", isDirectory: true)
        try FileManager.default.createDirectory(at: pictures, withIntermediateDirectories: true)
        let image = pictures.appendingPathComponent("review.jpg")
        try Data(repeating: 0x44, count: 128).write(to: image)

        let policy = SafePathPolicy(homeDirectory: home)
        let identity = try CleanupFileIdentity.capture(at: image)
        let candidate = CleanupCandidate(
            name: image.lastPathComponent,
            url: image,
            kind: .image,
            allocatedBytes: identity.logicalBytes,
            modifiedAt: identity.modifiedAt,
            isRecommended: false,
            detail: "手动复核",
            fileIdentity: identity
        )

        XCTAssertThrowsError(try policy.validateCleanupTarget(image)) { error in
            XCTAssertEqual(error as? SafePathError, .outsideAllowedRoots)
        }
        XCTAssertNoThrow(try policy.validateCleanupCandidate(candidate))

        let missingEvidence = CleanupCandidate(
            name: image.lastPathComponent,
            url: image,
            kind: .image,
            allocatedBytes: identity.logicalBytes,
            modifiedAt: identity.modifiedAt,
            isRecommended: false,
            detail: "缺少扫描凭据"
        )
        XCTAssertThrowsError(try policy.validateCleanupCandidate(missingEvidence)) { error in
            XCTAssertEqual(error as? CleanupEvidenceError, .targetChanged)
        }
    }

    private func makeTemporaryHome() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNestDownloadMediaTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func centralDirectoryData(entryName: String) -> Data {
        let name = Data(entryName.utf8)
        var bytes = Data([0x50, 0x4b, 0x01, 0x02])
        bytes.append(Data(repeating: 0, count: 24))
        appendLittleEndianUInt16(UInt16(name.count), to: &bytes)
        appendLittleEndianUInt16(0, to: &bytes)
        appendLittleEndianUInt16(0, to: &bytes)
        bytes.append(Data(repeating: 0, count: 12))
        bytes.append(name)
        return bytes
    }

    private func appendLittleEndianUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
    }
}
