import Foundation
import Testing

@testable import NVMCore

@Suite struct HealthChecksTests {
    private func tempDir(_ tag: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nvm-app-health-\(tag)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func check(_ checks: [HealthCheck], _ id: String) -> HealthCheck {
        checks.first { $0.id == id } ?? HealthCheck(id: id, title: "missing", severity: .ok,
                                                    detail: "", fix: nil)
    }

    @Test func npmPrefixOverrideIsAnError() throws {
        let home = tempDir("home")
        try "registry=https://registry.npmjs.org\nprefix=/usr/local\n# prefix=commented\n"
            .write(to: home.appendingPathComponent(".npmrc"), atomically: true, encoding: .utf8)
        let result = check(HealthChecker.run(nvmDir: home, home: home, brewNvmPaths: []), "npm-prefix")
        #expect(result.severity == .error)
        #expect(result.detail.contains("prefix=/usr/local"))
        #expect(result.fix?.contains("Remove the prefix= line") == true)
        try? FileManager.default.removeItem(at: home)
    }

    @Test func commentedOrMissingPrefixIsFine() throws {
        let home = tempDir("home")
        try "# prefix=/usr/local\nregistry=x\n".write(
            to: home.appendingPathComponent(".npmrc"), atomically: true, encoding: .utf8)
        #expect(check(HealthChecker.run(nvmDir: home, home: home, brewNvmPaths: []),
                      "npm-prefix").severity == .ok)
        try? FileManager.default.removeItem(at: home)
        // No .npmrc at all.
        let bare = tempDir("bare")
        #expect(check(HealthChecker.run(nvmDir: bare, home: bare, brewNvmPaths: []),
                      "npm-prefix").severity == .ok)
        try? FileManager.default.removeItem(at: bare)
    }

    @Test func ownershipFlagsForeignFilesWithExactCount() throws {
        let nvm = tempDir("foreign")
        try "x".write(to: nvm.appendingPathComponent("nvm.sh"), atomically: true, encoding: .utf8)
        // Some UID nothing on disk can match: dir itself + the one file = 2 foreign.
        let result = check(HealthChecker.run(nvmDir: nvm, home: nvm, brewNvmPaths: [],
                                             currentUID: 4_294_967_295), "nvm-ownership")
        #expect(result.severity == .error)
        #expect(result.detail.contains("2 file(s)"))
        #expect(result.detail.contains("nvm.sh"))
        #expect(result.fix?.contains("chown") == true)
        try? FileManager.default.removeItem(at: nvm)
    }

    @Test func ownershipOkWhenYouOwnEverything() throws {
        let nvm = tempDir("own")
        try "x".write(to: nvm.appendingPathComponent("nvm.sh"), atomically: true, encoding: .utf8)
        let result = check(HealthChecker.run(nvmDir: nvm, home: nvm, brewNvmPaths: []), "nvm-ownership")
        #expect(result.severity == .ok)
        try? FileManager.default.removeItem(at: nvm)
    }

    @Test func homebrewNvmIsAWarning() throws {
        let brew = tempDir("brew")
        try "#!/bin/sh\n".write(to: brew.appendingPathComponent("nvm.sh"), atomically: true, encoding: .utf8)
        let result = check(HealthChecker.run(nvmDir: tempDir("nvm"), home: tempDir("home2"),
                                             brewNvmPaths: [brew.appendingPathComponent("nvm.sh")]),
                           "homebrew-nvm")
        #expect(result.severity == .warning)
        #expect(result.detail.contains("brew-managed"))
        try? FileManager.default.removeItem(at: brew)
    }

    @Test func cleanMachineReportsAllOK() throws {
        let dir = tempDir("clean")
        let checks = HealthChecker.run(nvmDir: dir, home: dir, brewNvmPaths: [])
        #expect(checks.count == 3)
        #expect(checks.allSatisfy { $0.severity == .ok })
        try? FileManager.default.removeItem(at: dir)
    }
}
