import Testing

@testable import NVMCore

/// Fixture shaped like `nvm ls-remote --no-colors` from the README example.
private let sampleOutput = """
        v20.9.0   (Latest LTS: Iron)                        (Aliases: work)
        v21.0.0
        v21.1.0
        v21.2.0                            (Latest: node)   (Aliases: default)
        iojs-v3.3.1
"""

@Suite struct RemoteCatalogTests {
    @Test func parsesAnnotations() {
        let rows = RemoteCatalogParser.parse(sampleOutput)
        #expect(rows.count == 4) // iojs line is skipped

        let v2090 = rows.first { $0.version.raw == "v20.9.0" }
        #expect(v2090?.ltsCodename == "Iron")
        #expect(v2090?.aliasedBy == ["work"])
        #expect(v2090?.isLatestCurrent == false)

        let v2120 = rows.first { $0.version.raw == "v21.2.0" }
        #expect(v2120?.isLatestCurrent == true)
        #expect(v2120?.ltsCodename == nil)
        #expect(v2120?.aliasedBy == ["default"])
    }

    @Test func skipsNoiseLines() {
        #expect(RemoteCatalogParser.parse("command not found\n\n").isEmpty)
    }
}
