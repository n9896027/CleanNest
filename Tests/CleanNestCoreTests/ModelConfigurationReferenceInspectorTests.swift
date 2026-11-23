import Foundation
import XCTest
@testable import CleanNestCore

final class ModelConfigurationReferenceInspectorTests: XCTestCase {
    func testJSONResolvesEscapedRelativeAndAbsolutePathsWithoutFollowingThem() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let existing = fixture.root.appendingPathComponent("models/present.gguf")
        try FileManager.default.createDirectory(at: existing.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("model".utf8).write(to: existing)
        let absoluteURL = fixture.root.appendingPathComponent("absolute.bin")
        try Data("absolute".utf8).write(to: absoluteURL)
        let absolute = absoluteURL.path
        let escapedAbsolute = absolute.replacingOccurrences(of: "/", with: "\\u002F")
        let json = """
        {
          "model_path": "models\\/present.gguf",
          "weights": "models/missing.safetensors",
          "checkpoint": "\(escapedAbsolute)",
          "unrelatedText": "this/is/not/a/path/key"
        }
        """
        try fixture.write(json, named: "config.json")

        let report = ModelConfigurationReferenceInspector().inspect(root: fixture.root)

        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.scannedConfigurationCount, 1)
        XCTAssertEqual(report.references.count, 3)
        XCTAssertEqual(report.references.first(where: { $0.key == "model_path" })?.status, .existingTarget)
        XCTAssertEqual(report.references.first(where: { $0.key == "weights" })?.status, .missingTarget)
        XCTAssertEqual(report.references.first(where: { $0.key == "checkpoint" })?.status, .existingTarget)
        XCTAssertEqual(report.references.first(where: { $0.key == "checkpoint" })?.resolvedURL?.path, absolute)
        XCTAssertTrue(FileManager.default.fileExists(atPath: existing.path))
    }

    func testYAMLParsesMappingsListsQuotesAndComments() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let present = fixture.root.appendingPathComponent("weights/present.safetensors")
        try FileManager.default.createDirectory(at: present.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("weights".utf8).write(to: present)
        try fixture.write(
            """
            # model configuration
            model_path: 'weights/present.safetensors' # existing
            adapter_paths:
              - \"adapters/one.safetensors\"
              - 'adapters/two.safetensors'
            tokenizer_path: tokenizer.json
            """,
            named: "model.yaml"
        )

        let report = ModelConfigurationReferenceInspector().inspect(root: fixture.root)

        XCTAssertTrue(report.isComplete, report.issues.map(\.message).joined(separator: "; "))
        XCTAssertEqual(report.references.count, 4)
        XCTAssertEqual(report.references.filter { $0.status == .existingTarget }.count, 1)
        XCTAssertEqual(report.references.filter { $0.status == .missingTarget }.count, 3)
        XCTAssertEqual(Set(report.references.map(\.key)), ["model_path", "adapter_paths", "tokenizer_path"])
    }

    func testTOMLParsesTablesDottedKeysStringArraysAndComments() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.write(
            """
            [model]
            model.path = \"weights/model.gguf\" # primary
            adapter_paths = ['one.safetensors', \"two.safetensors\"]
            enabled = true
            count = 2
            """,
            named: "model.toml"
        )

        let report = ModelConfigurationReferenceInspector().inspect(root: fixture.root)

        XCTAssertTrue(report.isComplete, report.issues.map(\.message).joined(separator: "; "))
        XCTAssertEqual(report.references.count, 3)
        XCTAssertEqual(Set(report.references.map(\.key)), ["path", "adapter_paths"])
        XCTAssertTrue(report.references.allSatisfy { $0.status == .missingTarget })
    }

    func testMalformedJSONYAMLAndTOMLFailClosedPerFile() throws {
        for (name, text) in [
            ("broken.json", "{\\\"model_path\\\":"),
            ("broken.yaml", "model_path: \"unterminated"),
            ("broken.toml", "model_path = [\"unterminated\"")
        ] {
            let fixture = try Fixture()
            try fixture.write(text, named: name)
            let report = ModelConfigurationReferenceInspector().inspect(root: fixture.root)
            XCTAssertFalse(report.isComplete, name)
            XCTAssertFalse(report.issues.isEmpty, name)
            XCTAssertTrue(report.requiresReview, name)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent(name).path))
            fixture.cleanup()
        }
    }

    func testTraversalExternalAndUnresolvedReferencesStayReadOnlyEvidence() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let outside = fixture.root.deletingLastPathComponent().appendingPathComponent("outside.gguf")
        try Data("outside".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let configuration = fixture.root.appendingPathComponent("nested/config.json")
        try FileManager.default.createDirectory(at: configuration.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("""
        {
          "model_path": "../../\(outside.lastPathComponent)",
          "cache_dir": "/tmp/cleannest-external-fixture",
          "snapshot_path": "${MODEL_ROOT}/snapshot.bin"
        }
        """.utf8).write(to: configuration)

        let report = ModelConfigurationReferenceInspector().inspect(root: fixture.root)

        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.references.first(where: { $0.key == "model_path" })?.status, .directoryTraversal)
        XCTAssertEqual(report.references.first(where: { $0.key == "cache_dir" })?.status, .externalTarget)
        XCTAssertEqual(report.references.first(where: { $0.key == "snapshot_path" })?.status, .unresolvedText)
        XCTAssertNil(report.references.first(where: { $0.key == "snapshot_path" })?.resolvedURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testSymlinkAndOversizeConfigurationsProduceIssues() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let target = fixture.root.deletingLastPathComponent().appendingPathComponent("linked-target.json")
        try Data("{\"model_path\":\"outside.gguf\"}".utf8).write(to: target)
        defer { try? FileManager.default.removeItem(at: target) }
        try FileManager.default.createSymbolicLink(
            at: fixture.root.appendingPathComponent("linked.json"),
            withDestinationURL: target
        )
        let oversize = String(repeating: " ", count: 1_100)
        try fixture.write("{\"model_path\":\"\(oversize)\"}", named: "large.json")

        let report = ModelConfigurationReferenceInspector(
            maximumConfigurations: 8,
            maximumBytesPerConfiguration: 1_024,
            maximumVisitedEntries: 32
        ).inspect(root: fixture.root)

        XCTAssertFalse(report.isComplete)
        XCTAssertTrue(report.issues.contains { $0.configurationURL.lastPathComponent == "linked.json" })
        XCTAssertTrue(report.issues.contains { $0.configurationURL.lastPathComponent == "large.json" })
        XCTAssertTrue(report.references.isEmpty)
    }

    func testConfigurationLimitIsExplicitAndDoesNotClaimCompleteness() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.write("{\"model_path\":\"one.gguf\"}", named: "01.json")
        try fixture.write("{\"model_path\":\"two.gguf\"}", named: "02.json")

        let report = ModelConfigurationReferenceInspector(maximumConfigurations: 1).inspect(root: fixture.root)

        XCTAssertFalse(report.isComplete)
        XCTAssertEqual(report.scannedConfigurationCount, 1)
        XCTAssertTrue(report.issues.contains { $0.message.contains("上限") })
    }

    func testNoKnownPathKeysDoesNotClaimThereAreNoExternalReferences() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.write("{\"name\":\"demo\",\"enabled\":true}", named: "settings.json")

        let report = ModelConfigurationReferenceInspector().inspect(root: fixture.root)

        XCTAssertTrue(report.isComplete)
        XCTAssertFalse(report.requiresReview)
        XCTAssertTrue(report.references.isEmpty)
        XCTAssertTrue(report.summary.contains("不等于"))
    }

    func testAgentCacheWithModelReferenceLosesPreviewAndActionCandidates() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let cache = fixture.root.appendingPathComponent(".codex/cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let configuration = cache.appendingPathComponent("model.json")
        try Data("{\"model_path\":\"../shared/model.gguf\"}".utf8).write(to: configuration)
        let payload = cache.appendingPathComponent("payload.bin")
        try Data(repeating: 0x41, count: 8_192).write(to: payload)
        let old = Date().addingTimeInterval(-40 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: configuration.path)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: payload.path)

        let result = try await AgentWorkspaceScanner().scan(
            homeDirectory: fixture.root,
            openFiles: [],
            providers: [.codex],
            actionCandidateProviders: [.codex]
        )
        let artifact = try XCTUnwrap(
            result.snapshot.agents.first?.artifacts.first { $0.kind == .caches }
        )
        let report = try XCTUnwrap(artifact.configurationReferenceReport)

        XCTAssertEqual(report.references.count, 1)
        XCTAssertEqual(artifact.disposition, .review)
        XCTAssertEqual(artifact.previewBytes, 0)
        XCTAssertTrue(artifact.actionCandidates.isEmpty)
        XCTAssertTrue(artifact.protectionReasons.contains(report.summary))
        XCTAssertEqual(artifact.withoutActionCandidates().configurationReferenceReport, report)
    }

    private struct Fixture {
        let root: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("CleanNestConfigurationTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func write(_ text: String, named name: String) throws {
            try Data(text.utf8).write(to: root.appendingPathComponent(name))
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
