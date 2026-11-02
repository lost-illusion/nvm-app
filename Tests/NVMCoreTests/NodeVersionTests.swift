import Testing

@testable import NVMCore

@Suite struct NodeVersionTests {
    @Test func parsesFullVersions() {
        let v = NodeVersion.parse("v22.22.1")
        #expect(v?.major == 22 && v?.minor == 22 && v?.patch == 1)
        #expect(v?.prerelease == nil)
    }

    @Test func parsesPrerelease() {
        let v = NodeVersion.parse("v27.0.0-alpha.1.0.0")
        #expect(v?.major == 27 && v?.patch == 0)
        #expect(v?.prerelease == "alpha.1.0.0")
    }

    @Test func rejectsGarbage() {
        #expect(NodeVersion.parse("node") == nil)
        #expect(NodeVersion.parse("18.x") == nil)
        #expect(NodeVersion.parse("") == nil)
    }

    @Test func ordersBySemverWithPrereleaseBelowRelease() {
        let all = ["v18.16.0", "v22.22.1", "v27.0.0-alpha.1.0.0", "v27.0.0", "v9.11.2"]
            .compactMap(NodeVersion.parse)
        let sorted = all.sorted(by: >)
        #expect(sorted.map(\.raw) == ["v27.0.0", "v27.0.0-alpha.1.0.0", "v22.22.1", "v18.16.0", "v9.11.2"])
    }
}
