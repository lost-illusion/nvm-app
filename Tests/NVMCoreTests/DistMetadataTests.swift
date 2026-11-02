import Foundation
import Testing

@testable import NVMCore

@Suite struct DistMetadataTests {
    // Shape of real index.json entries: lts as codename/bool, security optional,
    // extra fields (files, v8, …) must be ignored.
    private let sample = """
        [
          {"version":"v22.22.1","date":"2026-01-13","npm":"10.9.4","v8":"12.4",
           "files":["osx-arm64-tar"],"lts":"Jod","security":true},
          {"version":"v24.0.0","date":"2025-10-15","npm":"11.4.2","lts":false},
          {"version":"v6.0.0","date":"2016-04-26"}
        ]
        """

    private func decode() throws -> [DistEntry] {
        try JSONDecoder().decode([DistEntry].self, from: Data(sample.utf8))
    }

    @Test func decodesOptionalAndVariantFields() throws {
        let entries = try decode()
        #expect(entries.count == 3)

        #expect(entries[0].ltsCodename == "Jod")
        #expect(entries[0].security)
        #expect(entries[0].npm == "10.9.4")
        #expect(entries[0].releaseDate != nil)

        #expect(entries[1].lts == .none)
        #expect(!entries[1].security)

        #expect(entries[2].npm == nil)
        #expect(entries[2].lts == .none)
        var utc = Calendar.current
        utc.timeZone = TimeZone(identifier: "UTC")!
        let components = utc.dateComponents([.year, .month, .day], from: try #require(entries[2].releaseDate))
        #expect(components == DateComponents(year: 2016, month: 4, day: 26))
    }

    @Test func cacheRoundTripPreservesEntriesAndTimestamp() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nvm-app-test-\(UUID().uuidString)", isDirectory: true)
        let store = DistIndexStore(directory: dir)
        let fetchedAt = Date(timeIntervalSince1970: 1_765_000_000)

        store.save(try decode(), fetchedAt: fetchedAt)
        let snapshot = try #require(store.load())
        #expect(snapshot.entries.count == 3)
        #expect(snapshot.entries[0].ltsCodename == "Jod")
        #expect(abs(snapshot.fetchedAt.timeIntervalSince(fetchedAt)) < 1)

        try? FileManager.default.removeItem(at: dir)
    }

    @Test func gunzipsGzipMagicAndIgnoresPlainData() throws {
        // gzip -n of {"ok":1}
        let gzipped = Data(base64Encoded: "H4sIAAAAAAAAA6tWys9WsjKsBQAJjFQQCAAAAA==")!
        #expect(DistFetcher.gunzipped(gzipped) == Data(#"{"ok":1}"#.utf8))
        #expect(DistFetcher.gunzipped(Data("plain".utf8)) == nil)
    }

    @Test func missingCacheLoadsAsNil() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nvm-app-test-\(UUID().uuidString)", isDirectory: true)
        #expect(DistIndexStore(directory: dir).load() == nil)
    }
}
