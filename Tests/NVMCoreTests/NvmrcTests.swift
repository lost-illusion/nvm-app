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
}
