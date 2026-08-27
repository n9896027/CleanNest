#!/usr/bin/env swift

import Foundation

enum LocalizationAuditError: LocalizedError {
    case usage
    case malformedCatalog
    case missingLanguage(key: String, language: String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "usage: LocalizationAudit.swift <Localizable.xcstrings> [Sources/CleanNest] [--strict-source]"
        case .malformedCatalog:
            return "Localizable.xcstrings is malformed"
        case .missingLanguage(let key, let language):
            return "missing non-empty \(language) localization for key: \(key)"
        }
    }
}

struct MissingSourceLiteral: Hashable {
    let file: String
    let line: Int
    let value: String
    let isDynamic: Bool
}

func catalogValue(
    entry: [String: Any],
    key: String,
    language: String,
    sourceLanguage: String
) -> String? {
    if language == sourceLanguage { return key }
    let localizations = entry["localizations"] as? [String: Any]
    let localized = localizations?[language] as? [String: Any]
    let unit = localized?["stringUnit"] as? [String: Any]
    return unit?["value"] as? String
}

func sourceLiterals(at sourceRoot: URL, catalogKeys: Set<String>) throws -> [MissingSourceLiteral] {
    let expression = try NSRegularExpression(
        pattern: #"(?:Text|Label|Button|Toggle|Picker|Section|navigationTitle|accessibilityLabel|accessibilityHint)\s*\(\s*\"((?:\\.|[^\"\\])*)\""#
    )
    let enumerator = FileManager.default.enumerator(
        at: sourceRoot,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
    )
    var missing = Set<MissingSourceLiteral>()
    while let url = enumerator?.nextObject() as? URL {
        guard url.pathExtension == "swift",
              (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else {
            continue
        }
        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
        for (offset, rawLine) in lines.enumerated() {
            let line = String(rawLine)
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            for match in expression.matches(in: line, range: range) {
                guard match.numberOfRanges > 1,
                      let capture = Range(match.range(at: 1), in: line) else { continue }
                let value = String(line[capture])
                guard value.range(of: #"\p{Han}"#, options: .regularExpression) != nil else {
                    continue
                }
                let dynamic = value.contains(#"\("#)
                if dynamic || !catalogKeys.contains(value) {
                    missing.insert(MissingSourceLiteral(
                        file: url.path.replacingOccurrences(of: sourceRoot.path + "/", with: ""),
                        line: offset + 1,
                        value: value,
                        isDynamic: dynamic
                    ))
                }
            }
        }
    }
    return missing.sorted {
        if $0.file != $1.file { return $0.file < $1.file }
        if $0.line != $1.line { return $0.line < $1.line }
        return $0.value < $1.value
    }
}

func run() throws -> Int32 {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let catalogPath = arguments.first, arguments.count <= 3 else {
        throw LocalizationAuditError.usage
    }
    let strictSource = arguments.contains("--strict-source")
    let sourceArgument = arguments.dropFirst().first { $0 != "--strict-source" }
    let catalogURL = URL(fileURLWithPath: catalogPath).standardizedFileURL
    let data = try Data(contentsOf: catalogURL)
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let sourceLanguage = root["sourceLanguage"] as? String,
          let strings = root["strings"] as? [String: Any] else {
        throw LocalizationAuditError.malformedCatalog
    }

    let requiredLanguages = ["zh-Hans", "en", "zh-Hant"]
    var translatedCounts = Dictionary(uniqueKeysWithValues: requiredLanguages.map { ($0, 0) })
    for key in strings.keys.sorted() {
        guard let entry = strings[key] as? [String: Any] else {
            throw LocalizationAuditError.malformedCatalog
        }
        if entry["shouldTranslate"] as? Bool == false { continue }
        for language in requiredLanguages {
            guard let value = catalogValue(
                entry: entry,
                key: key,
                language: language,
                sourceLanguage: sourceLanguage
            )?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                throw LocalizationAuditError.missingLanguage(key: key, language: language)
            }
            translatedCounts[language, default: 0] += 1
        }
    }

    print("catalog_entries=\(strings.count)")
    for language in requiredLanguages {
        print("\(language)=\(translatedCounts[language, default: 0])")
    }

    guard let sourceArgument else { return 0 }
    let sourceRoot = URL(fileURLWithPath: sourceArgument, isDirectory: true).standardizedFileURL
    let missing = try sourceLiterals(at: sourceRoot, catalogKeys: Set(strings.keys))
    let staticMissing = missing.filter { !$0.isDynamic }
    let dynamicMissing = missing.filter(\.isDynamic)
    print("direct_ui_static_missing=\(staticMissing.count)")
    print("direct_ui_dynamic_requires_review=\(dynamicMissing.count)")
    for item in missing.prefix(80) {
        let kind = item.isDynamic ? "dynamic" : "missing"
        print("\(kind):\(item.file):\(item.line):\(item.value)")
    }
    if missing.count > 80 { print("remaining_findings=\(missing.count - 80)") }
    return strictSource && !missing.isEmpty ? 3 : 0
}

do {
    exit(try run())
} catch {
    FileHandle.standardError.write(Data("Localization audit failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
