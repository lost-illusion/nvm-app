import Foundation

/// One row of `nvm ls-remote --no-colors` output.
public struct RemoteVersion: Identifiable, Sendable, Hashable {
    public let version: NodeVersion
    /// `(Latest: node)` — what `nvm install node` would pick.
    public let isLatestCurrent: Bool
    /// `(Latest LTS: <codename>)` — latest patch of that LTS line only;
    /// older LTS patches carry no marker in ls-remote output.
    public let ltsCodename: String?
    /// `(Aliases: a, b)` — the user's own aliases that resolve here.
    public let aliasedBy: [String]

    public var id: String { version.raw }
    public var isLatestLTSLine: Bool { ltsCodename != nil }

    public init(version: NodeVersion, isLatestCurrent: Bool, ltsCodename: String?, aliasedBy: [String]) {
        self.version = version
        self.isLatestCurrent = isLatestCurrent
        self.ltsCodename = ltsCodename
        self.aliasedBy = aliasedBy
    }
}

public enum RemoteCatalogParser {
    private static let versionPattern = try! NSRegularExpression(pattern: #"^\s*(v[0-9][^ ]*)"#)
    private static let ltsPattern = try! NSRegularExpression(pattern: "\\(Latest LTS: ([^)]+)\\)")
    private static let latestPattern = try! NSRegularExpression(pattern: "\\(Latest: ([^)]+)\\)")
    private static let aliasesPattern = try! NSRegularExpression(pattern: "\\(Aliases: ([^)]+)\\)")

    public static func parse(_ text: String) -> [RemoteVersion] {
        text.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = String(rawLine)
            if line.contains("iojs") { return nil } // legacy line; out of scope
            guard let match = versionPattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let versionRange = Range(match.range(at: 1), in: line)
            else { return nil }
            guard let version = NodeVersion.parse(String(line[versionRange])) else { return nil }

            let lts = firstCapture(ltsPattern, in: line, group: 1)
            let isLatest = firstCapture(latestPattern, in: line, group: 1) != nil
            let aliases = firstCapture(aliasesPattern, in: line, group: 1)
                .map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } } ?? []

            return RemoteVersion(version: version, isLatestCurrent: isLatest,
                                 ltsCodename: lts, aliasedBy: aliases)
        }
    }

    private static func firstCapture(_ pattern: NSRegularExpression, in line: String, group: Int) -> String? {
        guard let match = pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: group), in: line) else { return nil }
        return String(line[range])
    }
}
