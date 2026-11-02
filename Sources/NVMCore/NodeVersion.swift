import Foundation

/// A parsed node version, e.g. `v22.22.1` or `v27.0.0-alpha.1.0.0`.
/// Ordering follows semver: prereleases sort below their release.
public struct NodeVersion: Sendable, Identifiable, Hashable {
    public let raw: String
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?

    public var id: String { raw }

    /// `v22.20.0` / `22.20.0` compared as one thing.
    public static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        return s
    }

    public static func parse(_ text: String) -> NodeVersion? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        guard !s.isEmpty else { return nil }

        let head = s.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = String(head[0])
        let prerelease = head.count > 1 ? String(head[1]) : nil

        let parts = core.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }), parts.count <= 3 else { return nil }
        let major = parts[0]!
        let minor = parts.count > 1 ? parts[1]! : 0
        let patch = parts.count > 2 ? parts[2]! : 0
        return NodeVersion(raw: text.trimmingCharacters(in: .whitespacesAndNewlines),
                           major: major, minor: minor, patch: patch, prerelease: prerelease)
    }
}

extension NodeVersion: Comparable {
    public static func < (lhs: NodeVersion, rhs: NodeVersion) -> Bool {
        let l = (lhs.major, lhs.minor, lhs.patch)
        let r = (rhs.major, rhs.minor, rhs.patch)
        if l != r { return l < r }
        switch (lhs.prerelease == nil, rhs.prerelease == nil) {
        case (true, false): return false // a release outranks a prerelease
        case (false, true): return true
        default: return (lhs.prerelease ?? "") < (rhs.prerelease ?? "")
        }
    }
}
