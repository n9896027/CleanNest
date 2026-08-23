#!/usr/bin/env swift

import Foundation

enum ExportError: LocalizedError {
    case usage
    case malformedCatalog

    var errorDescription: String? {
        switch self {
        case .usage:
            return "usage: LocalizationExporter.swift <Localizable.xcstrings> <resources-directory>"
        case .malformedCatalog:
            return "Localizable.xcstrings is malformed"
        }
    }
}

func quoted(_ value: String) -> String {
    var result = "\""
    for scalar in value.unicodeScalars {
        switch scalar {
        case "\\": result += "\\\\"
        case "\"": result += "\\\""
        case "\n": result += "\\n"
        case "\r": result += "\\r"
        case "\t": result += "\\t"
        default: result.unicodeScalars.append(scalar)
        }
    }
    result += "\""
    return result
}

func run() throws {
    guard CommandLine.arguments.count == 3 else { throw ExportError.usage }
    let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
    let outputURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true).standardizedFileURL
    let tableName = sourceURL.deletingPathExtension().lastPathComponent
    let data = try Data(contentsOf: sourceURL)
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let sourceLanguage = root["sourceLanguage"] as? String,
          let strings = root["strings"] as? [String: Any] else {
        throw ExportError.malformedCatalog
    }

    for language in ["en", "zh-Hans", "zh-Hant"] {
        var lines = ["/* Generated from Localizable.xcstrings. Do not edit the app bundle copy. */"]
        for key in strings.keys.sorted() {
            guard let entry = strings[key] as? [String: Any] else { continue }
            let localizations = entry["localizations"] as? [String: Any]
            let localized = localizations?[language] as? [String: Any]
            let unit = localized?["stringUnit"] as? [String: Any]
            let value = unit?["value"] as? String
            let resolved = language == sourceLanguage ? (value ?? key) : (value ?? key)
            lines.append("\(quoted(key)) = \(quoted(resolved));")
        }
        lines.append("")

        let directory = outputURL.appendingPathComponent("\(language).lproj", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("\(tableName).strings", isDirectory: false)
        try lines.joined(separator: "\n").write(to: destination, atomically: true, encoding: .utf8)
    }
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("Localization export failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
