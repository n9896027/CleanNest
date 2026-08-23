#!/usr/bin/env swift

import CryptoKit
import Foundation

enum SBOMError: LocalizedError {
    case usage
    case missingInput(String)

    var errorDescription: String? {
        switch self {
        case .usage: return "usage: SBOMGenerator.swift <app-bundle> <output.spdx.json>"
        case .missingInput(let path): return "input bundle does not exist: \(path)"
        }
    }
}

func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func run() throws {
    guard CommandLine.arguments.count == 3 else { throw SBOMError.usage }
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL
    let output = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
    guard FileManager.default.fileExists(atPath: root.path) else {
        throw SBOMError.missingInput(root.path)
    }

    let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
    let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
    )
    var records: [(path: String, size: Int, checksum: String)] = []
    while let url = enumerator?.nextObject() as? URL {
        let values = try url.resourceValues(forKeys: Set(keys))
        guard values.isRegularFile == true else { continue }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let relative = String(url.path.dropFirst(root.path.count + 1))
        records.append((relative, values.fileSize ?? data.count, sha256(data)))
    }
    records.sort { $0.path < $1.path }
    let aggregate = records.map { "\($0.path)\u{0}\($0.checksum)" }.joined(separator: "\n")
    let namespaceHash = sha256(Data(aggregate.utf8))

    let files: [[String: Any]] = records.enumerated().map { index, record in
        [
            "SPDXID": "SPDXRef-File-\(index + 1)",
            "fileName": "./\(record.path)",
            "checksums": [["algorithm": "SHA256", "checksumValue": record.checksum]],
            "fileTypes": ["BINARY"],
            "comment": "File size: \(record.size) bytes"
        ]
    }
    var relationships: [[String: Any]] = [[
        "spdxElementId": "SPDXRef-DOCUMENT",
        "relationshipType": "DESCRIBES",
        "relatedSpdxElement": "SPDXRef-Package-CleanNest"
    ]]
    relationships.append(contentsOf: records.indices.map { index in
        [
            "spdxElementId": "SPDXRef-Package-CleanNest",
            "relationshipType": "CONTAINS",
            "relatedSpdxElement": "SPDXRef-File-\(index + 1)"
        ]
    })

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let document: [String: Any] = [
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT",
        "name": "CleanNest-0.4.0",
        "documentNamespace": "https://github.com/n9896027/CleanNest/sbom/\(namespaceHash)",
        "creationInfo": [
            "created": formatter.string(from: Date()),
            "creators": ["Tool: CleanNest-SBOMGenerator-1.0"]
        ],
        "packages": [[
            "name": "CleanNest",
            "SPDXID": "SPDXRef-Package-CleanNest",
            "versionInfo": "0.4.0",
            "downloadLocation": "NOASSERTION",
            "filesAnalyzed": true,
            "licenseConcluded": "MIT",
            "licenseDeclared": "MIT",
            "copyrightText": "Copyright (c) 2026 CleanNest contributors",
            "supplier": "Organization: CleanNest contributors"
        ]],
        "files": files,
        "relationships": relationships
    ]
    let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try data.write(to: output, options: .atomic)
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("SBOM generation failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
