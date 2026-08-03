import Foundation

public enum EngineLocator {
    public static func locate(customPath: String? = nil) -> URL? {
        candidates(customPath: customPath).first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    public static func candidates(customPath: String? = nil) -> [URL] {
        var paths: [String] = []

        if let customPath, !customPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            paths.append((customPath as NSString).expandingTildeInPath)
        }

        let environmentPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in environmentPath.split(separator: ":").map(String.init) {
            paths.append(directory + "/mole")
            paths.append(directory + "/mo")
        }
        paths.append(contentsOf: [
            "/opt/homebrew/bin/mole",
            "/opt/homebrew/bin/mo",
            "/usr/local/bin/mole",
            "/usr/local/bin/mo",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/mole").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/mo").path,
            "/opt/local/bin/mole",
            "/opt/local/bin/mo"
        ])

        var seen = Set<String>()
        return paths.compactMap { path in
            let standardized = URL(fileURLWithPath: path).standardizedFileURL
            return seen.insert(standardized.path).inserted ? standardized : nil
        }
    }

    public static func locateHomebrew() -> URL? {
        [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]
        .map { URL(fileURLWithPath: $0) }
        .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
