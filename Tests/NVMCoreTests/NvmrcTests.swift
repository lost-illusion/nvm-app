import Foundation
import Testing

@testable import NVMCore

@Suite struct NvmrcTests {
    private func tempFolder() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nvm-app-nvmrc-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func roundTrip() throws {
        let folder = tempFolder()
        #expect(Nvmrc.read(in: folder) == nil)

        Nvmrc.write("22.20.0", in: folder)
        #expect(Nvmrc.read(in: folder) == "22.20.0")

        Nvmrc.write("lts/*", in: folder)
        #expect(Nvmrc.read(in: folder) == "lts/*")

        Nvmrc.remove(from: folder)
        #expect(Nvmrc.read(in: folder) == nil)
        try? FileManager.default.removeItem(at: folder)
    }

    @Test func skipsCommentsAndBlankLines() throws {
        let folder = tempFolder()
        try "\n# nvm pin\n\n  v20.19.0  \n\n".write(
            to: folder.appendingPathComponent(".nvmrc"), atomically: true, encoding: .utf8)
        #expect(Nvmrc.read(in: folder) == "v20.19.0")
        try? FileManager.default.removeItem(at: folder)
    }

    @Test func blankFileReadsAsNoPin() throws {
        let folder = tempFolder()
        try "\n\n".write(to: folder.appendingPathComponent(".nvmrc"), atomically: true, encoding: .utf8)
        #expect(Nvmrc.read(in: folder) == nil)
        try? FileManager.default.removeItem(at: folder)
    }

    @Test func scannerFindsNestedPinsAndSkipsNoise() throws {
        let root = tempFolder()
        let fm = FileManager.default
        for dir in ["api", "web/sub", "web/node_modules/pkg", "web/.git/hooks"] {
            let url = root.appendingPathComponent(dir, isDirectory: true)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            try "22\n".write(to: url.appendingPathComponent(".nvmrc"), atomically: true, encoding: .utf8)
        }
        let scanRoot = root.resolvingSymlinksInPath()
        let paths = Set(NvmrcScanner.scan(under: root).map(\.path))
        #expect(paths.contains(scanRoot.appendingPathComponent("api").path))
        #expect(paths.contains(scanRoot.appendingPathComponent("web/sub").path))
        #expect(!paths.contains(scanRoot.appendingPathComponent("web/node_modules/pkg").path))
        #expect(!paths.contains(scanRoot.appendingPathComponent("web/.git/hooks").path))
        try? fm.removeItem(at: root)
    }

    @Test func scannerHonorsResultLimit() throws {
        let root = tempFolder()
        let fm = FileManager.default
        for index in 0..<12 {
            let url = root.appendingPathComponent("p\(index)", isDirectory: true)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            try "22\n".write(to: url.appendingPathComponent(".nvmrc"), atomically: true, encoding: .utf8)
        }
        var limits = NvmrcScanner.Limits()
        limits.maxResults = 5
        #expect(NvmrcScanner.scan(under: root, limits: limits).count == 5)
        try? fm.removeItem(at: root)
    }
}
