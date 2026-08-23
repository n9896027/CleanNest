import Foundation
import XCTest
@testable import CleanNestCore

final class LocalModelCatalogTests: XCTestCase {
    func testDiscoversOnlyCompleteModelsAndReadsUsefulMetadata() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let model = root.appendingPathComponent("Qwen-Test-4bit", isDirectory: true)
        let incomplete = root.appendingPathComponent("Incomplete", isDirectory: true)
        let unsupported = root.appendingPathComponent("Whisper-Test", isDirectory: true)
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: incomplete, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unsupported, withIntermediateDirectories: true)
        let config = #"{"architectures":["QwenTestForCausalLM"],"model_type":"qwen_test","_name_or_path":"example/Qwen-Test","quantization":{"bits":4}}"#
        try config.write(to: model.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        try Data(repeating: 0, count: 256).write(
            to: model.appendingPathComponent("model-00001-of-00001.safetensors")
        )
        try "{}".write(
            to: incomplete.appendingPathComponent("config.json"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"model_type":"whisper"}"#.write(
            to: unsupported.appendingPathComponent("config.json"),
            atomically: true,
            encoding: .utf8
        )
        try Data([0]).write(to: unsupported.appendingPathComponent("weights.safetensors"))

        let catalog = LocalModelCatalog(maximumVisitedDirectories: 20, maximumModels: 8, maximumDepth: 2)
        let discovered = catalog.discover(homeDirectory: root, roots: [root])

        XCTAssertEqual(discovered.count, 1)
        XCTAssertEqual(discovered[0].displayName, "Qwen-Test-4bit")
        XCTAssertEqual(discovered[0].architecture, "QwenTestForCausalLM")
        XCTAssertEqual(discovered[0].modelType, "qwen_test")
        XCTAssertEqual(discovered[0].quantization, "4-bit")
        XCTAssertEqual(discovered[0].weightBytes, 256)
    }

    func testModelIdentityAcceptsCanonicalPathAndRepositoryAlias() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let model = root.appendingPathComponent("Model", isDirectory: true)
        let alias = root.appendingPathComponent("Friendly-Model", isDirectory: true)
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        try #"{"_name_or_path":"publisher/model"}"#.write(
            to: model.appendingPathComponent("config.json"),
            atomically: true,
            encoding: .utf8
        )
        try Data([0]).write(to: model.appendingPathComponent("weights.safetensors"))
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: model)

        let descriptor = try XCTUnwrap(LocalModelCatalog().descriptor(at: alias))
        XCTAssertEqual(descriptor.displayName, "Friendly-Model")
        XCTAssertTrue(descriptor.matches(serviceModelID: model.path))
        XCTAssertTrue(descriptor.matches(serviceModelID: "publisher/model"))
        XCTAssertFalse(descriptor.matches(serviceModelID: "publisher/other"))
    }

    func testProbeAcceptsOMLXHealthAndResolvesExactServiceID() {
        XCTAssertTrue(LocalAIHealthStatus.isReady("healthy"))
        XCTAssertTrue(LocalAIHealthStatus.isReady("OK"))
        XCTAssertFalse(LocalAIHealthStatus.isReady("loading"))

        let selected = LocalModelDescriptor(
            path: "/models/Qwen3.8-27B-Uncensored-8bit",
            canonicalPath: "/models/Qwen3.8-27B-Uncensored-8bit",
            displayName: "Qwen3.8-27B-Uncensored-8bit",
            architecture: "Qwen3_5ForConditionalGeneration",
            modelType: "qwen3_5",
            quantization: "8-bit",
            weightBytes: 1,
            serviceAliases: ["Qwen3.8-27B-Uncensored-8bit"]
        )
        let probe = LocalAIProbeResult(
            modelIDs: [
                "Qwen3.8-27B-Uncensored-8bit",
                "z-lab--Qwen3.8-27B-DFlash2"
            ],
            defaultModelID: "Qwen3.8-27B-Uncensored-8bit"
        )

        XCTAssertEqual(
            probe.resolvedModelID(preferredModelID: nil, selectedLocalModel: selected),
            "Qwen3.8-27B-Uncensored-8bit"
        )
        XCTAssertEqual(
            probe.resolvedModelID(
                preferredModelID: "qwen3.8-27b-uncensored-8BIT",
                selectedLocalModel: nil
            ),
            "Qwen3.8-27B-Uncensored-8bit"
        )
        XCTAssertNil(
            probe.resolvedModelID(
                preferredModelID: "/Users/example/model",
                selectedLocalModel: selected
            )
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNestLocalModelCatalogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
