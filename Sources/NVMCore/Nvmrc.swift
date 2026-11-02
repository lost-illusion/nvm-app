import Foundation

/// Minimal `.nvmrc` handling (capabilities doc §7): the file holds one version
/// spec; `nvm resolve <spec>` decides which concrete version it means.
public enum Nvmrc {
    public static let fileName = ".nvmrc"

    /// First non-empty, non-comment line. `nil` when the file is missing or blank.
    public static func read(in folder: URL) -> String? {
        let url = folder.appendingPathComponent(fileName)
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in raw.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") { return trimmed }
        }
        return nil
    }

    public static func write(_ spec: String, in folder: URL) {
        let url = folder.appendingPathComponent(fileName)
        try? (spec + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    public static func remove(from folder: URL) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(fileName))
    }
}

/// Recursive `.nvmrc` discovery. Noise and system trees are skipped so even a
/// whole-disk scan stays bounded; unreadable corners are silently ignored.
public enum NvmrcScanner {
    public struct Limits: Sendable {
        public var maxResults = 300
        public var timeBudget: TimeInterval = 90
        public init() {}
    }

    private static let excluded: Set<String> = [
        // dev noise
        "node_modules", ".git", ".svn", ".hg", "vendor", ".cache", ".npm", ".gradle", ".m2",
        // macOS trees where .nvmrc realistically never lives
        "System", "usr", "bin", "sbin", "lib", "opt", "dev", "private", "var",
        "Volumes", "Network", "Applications", "Library", ".Trash", ".Spotlight-V100",
        ".DocumentRevisions-V100", ".fseventsd", ".vol", ".Timetracking",
    ]

    public static func scan(under root: URL,
                            limits: Limits = Limits(),
                            fileManager: FileManager = .default) -> [URL] {
        var found: [URL] = []
        let deadline = Date().addingTimeInterval(limits.timeBudget)
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return found
        }
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name == Nvmrc.fileName {
                // Enumerators return symlink-resolved paths (/var → /private/var);
                // resolve our own paths too so watch-list dedup matches them.
                found.append(url.deletingLastPathComponent().resolvingSymlinksInPath())
                if found.count >= limits.maxResults { break }
            } else if excluded.contains(name) {
                enumerator.skipDescendants()
            }
            if Date() > deadline { break }
        }
        return found
    }
}
