#!/usr/bin/env swift

import Foundation

enum LocalizationAuditError: LocalizedError {
    case usage
    case malformedCatalog
    case missingLanguage(key: String, language: String)
    case formatMismatch(key: String, language: String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "usage: LocalizationAudit.swift <Localizable.xcstrings> [Sources/CleanNest] [--strict-source] [--verbose]"
        case .malformedCatalog:
            return "Localizable.xcstrings is malformed"
        case .missingLanguage(let key, let language):
            return "missing non-empty \(language) localization for key: \(key)"
        case .formatMismatch(let key, let language):
            return "format specifiers differ in \(language) localization for key: \(key)"
        }
    }
}

struct MissingSourceLiteral: Hashable {
    let file: String
    let line: Int
    let value: String
    let isDynamic: Bool
}

struct ParsedLiteral {
    let start: Int
    let end: Int
    let raw: String
    let isDynamic: Bool
}

/// A small Swift lexer for source-localization coverage. Unlike a line-based
/// regular expression, it understands nested strings inside interpolation and
/// skips comments, so custom component arguments and multi-line calls are seen.
final class SwiftLiteralLexer {
    private let characters: [Character]

    init(_ source: String) {
        characters = Array(source)
    }

    func literals() -> [ParsedLiteral] {
        var result: [ParsedLiteral] = []
        var cursor = 0
        while cursor < characters.count {
            if let end = commentEnd(at: cursor) {
                cursor = end
                continue
            }
            guard characters[cursor] == "\"" else {
                cursor += 1
                continue
            }
            guard let literal = stringLiteral(at: cursor) else {
                cursor += 1
                continue
            }
            result.append(literal)
            cursor = literal.end
        }
        return result
    }

    private func commentEnd(at start: Int) -> Int? {
        guard start + 1 < characters.count, characters[start] == "/" else { return nil }
        if characters[start + 1] == "/" {
            var cursor = start + 2
            while cursor < characters.count, characters[cursor] != "\n" { cursor += 1 }
            return cursor < characters.count ? cursor + 1 : cursor
        }
        guard characters[start + 1] == "*" else { return nil }
        var cursor = start + 2
        var depth = 1
        while cursor < characters.count, depth > 0 {
            if has("/*", at: cursor) {
                depth += 1
                cursor += 2
            } else if has("*/", at: cursor) {
                depth -= 1
                cursor += 2
            } else {
                cursor += 1
            }
        }
        return cursor
    }

    private func stringLiteral(at start: Int) -> ParsedLiteral? {
        if has("\"\"\"", at: start) {
            var cursor = start + 3
            while cursor < characters.count {
                if has("\"\"\"", at: cursor) {
                    let end = cursor + 3
                    return ParsedLiteral(
                        start: start,
                        end: end,
                        raw: String(characters[start..<end]),
                        isDynamic: false
                    )
                }
                if characters[cursor] == "\\" { cursor += 1 }
                cursor += 1
            }
            return nil
        }

        var cursor = start + 1
        var dynamic = false
        while cursor < characters.count {
            let character = characters[cursor]
            if character == "\"" {
                let end = cursor + 1
                return ParsedLiteral(
                    start: start,
                    end: end,
                    raw: String(characters[start..<end]),
                    isDynamic: dynamic
                )
            }
            guard character == "\\", cursor + 1 < characters.count else {
                cursor += 1
                continue
            }
            if characters[cursor + 1] != "(" {
                cursor += 2
                continue
            }

            dynamic = true
            cursor += 2
            var depth = 1
            while cursor < characters.count, depth > 0 {
                if let end = commentEnd(at: cursor) {
                    cursor = end
                    continue
                }
                if characters[cursor] == "\"" {
                    guard let nested = stringLiteral(at: cursor) else { return nil }
                    cursor = nested.end
                    continue
                }
                if characters[cursor] == "\\" {
                    cursor += 2
                    continue
                }
                if characters[cursor] == "(" { depth += 1 }
                if characters[cursor] == ")" {
                    depth -= 1
                    if depth == 0 {
                        cursor += 1
                        break
                    }
                }
                cursor += 1
            }
            if depth > 0 { return nil }
        }
        return nil
    }

    private func has(_ token: String, at index: Int) -> Bool {
        let tokenCharacters = Array(token)
        guard index + tokenCharacters.count <= characters.count else { return false }
        return Array(characters[index..<(index + tokenCharacters.count)]) == tokenCharacters
    }
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

func formatSpecifiers(in value: String) throws -> [String] {
    let expression = try NSRegularExpression(pattern: #"%(?!%)(?:[0-9]+\$)?[@dfu]"#)
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return expression.matches(in: value, range: range).compactMap {
        Range($0.range, in: value).map { String(value[$0]) }
    }.sorted()
}

func decodedSourceValue(_ raw: String) -> String {
    if let data = raw.data(using: .utf8),
       let decoded = try? JSONDecoder().decode(String.self, from: data) {
        return decoded
    }
    return raw
}

func containsHanCharacter(_ value: String) -> Bool {
    value.unicodeScalars.contains { scalar in
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F:
            return true
        default:
            return false
        }
    }
}

func sourceLiterals(at sourceRoot: URL, catalogKeys: Set<String>) throws -> [MissingSourceLiteral] {
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
        let characters = Array(contents)
        for literal in SwiftLiteralLexer(contents).literals() {
            let value = decodedSourceValue(literal.raw)
            guard containsHanCharacter(value) else { continue }
            if literal.isDynamic || !catalogKeys.contains(value) {
                missing.insert(MissingSourceLiteral(
                    file: url.path.replacingOccurrences(of: sourceRoot.path + "/", with: ""),
                    line: characters[..<literal.start].reduce(into: 1) { count, character in
                        if character == "\n" { count += 1 }
                    },
                    value: value,
                    isDynamic: literal.isDynamic
                ))
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
    guard let catalogPath = arguments.first, arguments.count <= 4 else {
        throw LocalizationAuditError.usage
    }
    let strictSource = arguments.contains("--strict-source")
    let verbose = arguments.contains("--verbose")
    let sourceArgument = arguments.dropFirst().first { !$0.hasPrefix("--") }
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
        let sourceSpecifiers = try formatSpecifiers(in: key)
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
            guard try formatSpecifiers(in: value) == sourceSpecifiers else {
                throw LocalizationAuditError.formatMismatch(key: key, language: language)
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
    print("source_static_missing=\(staticMissing.count)")
    print("source_dynamic_requires_review=\(dynamicMissing.count)")
    let visibleFindings = verbose ? missing : Array(missing.prefix(80))
    for item in visibleFindings {
        let kind = item.isDynamic ? "dynamic" : "missing"
        print("\(kind):\(item.file):\(item.line):\(item.value)")
    }
    if !verbose && missing.count > 80 { print("remaining_findings=\(missing.count - 80)") }
    return strictSource && !missing.isEmpty ? 3 : 0
}

do {
    exit(try run())
} catch {
    FileHandle.standardError.write(Data("Localization audit failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
