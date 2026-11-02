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
