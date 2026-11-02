import Testing

@testable import NVMCore

private let rows: [RemoteVersion] = [
    RemoteVersion(version: NodeVersion.parse("v22.22.1")!, isLatestCurrent: false, ltsCodename: nil, aliasedBy: []),
    RemoteVersion(version: NodeVersion.parse("v22.22.0")!, isLatestCurrent: false, ltsCodename: nil, aliasedBy: []),
    RemoteVersion(version: NodeVersion.parse("v22.20.0")!, isLatestCurrent: false, ltsCodename: "Jod", aliasedBy: []),
    RemoteVersion(version: NodeVersion.parse("v20.9.0")!, isLatestCurrent: false, ltsCodename: "Iron", aliasedBy: []),
    RemoteVersion(version: NodeVersion.parse("v24.0.0")!, isLatestCurrent: true, ltsCodename: nil, aliasedBy: []),
]

@Suite struct VersionTreeTests {
    @Test func groupsMajorsAndMinorsDescending() {
        let tree = VersionTree(rows: rows)
        #expect(tree.majors.map(\.major) == [24, 22, 20])

        let v22 = tree.majors.first { $0.major == 22 }
        #expect(v22?.totalCount == 3)
        #expect(v22?.minors.map(\.minor) == [22, 20])
        #expect(v22?.minors.first?.patches.map(\.version.raw) == ["v22.22.1", "v22.22.0"])
    }

    @Test func majorCarriesLTSMarkerFromAnyPatch() {
        let tree = VersionTree(rows: rows)
        #expect(tree.majors.first { $0.major == 22 }?.ltsCodename == "Jod")
        #expect(tree.majors.first { $0.major == 24 }?.ltsCodename == nil)
    }
}
