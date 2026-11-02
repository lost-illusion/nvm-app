import Foundation

/// Groups catalog rows into major → minor → patches for the compact table view.
public struct VersionTree: Sendable {
    public struct Major: Sendable, Identifiable {
        public let major: Int
        public let minors: [Minor]
        /// LTS codename when any patch of this major carries an LTS marker.
        public let ltsCodename: String?
        public var totalCount: Int { minors.reduce(0) { $0 + $1.patches.count } }
        public var id: Int { major }
    }

    public struct Minor: Sendable, Identifiable {
        public let major: Int
        public let minor: Int
        public let patches: [RemoteVersion]
        public var id: String { "\(major).\(minor)" }
    }

    public let majors: [Major]

    public init(rows: [RemoteVersion]) {
        let byMajor = Dictionary(grouping: rows, by: { $0.version.major })
        self.majors = byMajor.keys.sorted(by: >).map { major in
            let rows = byMajor[major]!
            let byMinor = Dictionary(grouping: rows, by: { $0.version.minor })
            let minors = byMinor.keys.sorted(by: >).map { minor in
                Minor(major: major, minor: minor,
                      patches: byMinor[minor]!.sorted { $0.version > $1.version })
            }
            return Major(major: major, minors: minors,
                         ltsCodename: rows.compactMap(\.ltsCodename).first)
        }
    }
}
