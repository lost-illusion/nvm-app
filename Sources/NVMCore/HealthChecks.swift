import Foundation

public struct HealthCheck: Sendable, Identifiable, Equatable {
    public enum Severity: Int, Sendable { case ok = 0, warning = 1, error = 2 }

    public let id: String
    public let title: String
    public let severity: Severity
    public let detail: String
    /// Copy-pasteable repair, when one exists.
    public let fix: String?

    public init(id: String, title: String, severity: Severity, detail: String, fix: String?) {
        self.id = id
        self.title = title
        self.severity = severity
        self.detail = detail
        self.fix = fix
    }
}

/// Setup problems that silently break nvm (capabilities doc §14):
/// an npm `prefix=` override, foreign-owned `~/.nvm` files, Homebrew-nvm.
/// All file work — bounded so even the ownership walk can't hang the app.
public enum HealthChecker {
    public static func run(
        nvmDir: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        brewNvmPaths: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew/opt/nvm/nvm.sh"),
            URL(fileURLWithPath: "/usr/local/opt/nvm/nvm.sh"),
        ],
        currentUID: UInt32 = UInt32(getuid()),
        fileManager: FileManager = .default
    ) -> [HealthCheck] {
        var checks: [HealthCheck] = []
        checks.append(npmPrefix(npmrc: home.appendingPathComponent(".npmrc"), fileManager: fileManager))
        checks.append(ownership(nvmDir: nvmDir, currentUID: currentUID, fileManager: fileManager))
        checks.append(homebrew(brewNvmPaths: brewNvmPaths, fileManager: fileManager))
        return checks
    }

    // MARK: - npm prefix vs nvm

    /// `prefix=` in ~/.npmrc pins npm globals to one location, so each nvm
    /// version sees the same (possibly wrong) globals and `nvm use` stops
    /// isolating them. The nvm README calls this out explicitly.
    static func npmPrefix(npmrc: URL, fileManager: FileManager) -> HealthCheck {
        guard let raw = try? String(contentsOf: npmrc, encoding: .utf8) else {
            return HealthCheck(id: "npm-prefix", title: "npm prefix", severity: .ok,
                               detail: "~/.npmrc sets no prefix override", fix: nil)
        }
        let offenders = raw.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("#") && $0.lowercased().hasPrefix("prefix=") }
        if let first = offenders.first {
            return HealthCheck(id: "npm-prefix", title: "npm prefix conflicts with nvm",
                               severity: .error,
                               detail: "\(npmrc.path) sets “\(first)” — npm globals stop following the active nvm version.",
                               fix: "Remove the prefix= line from ~/.npmrc")
        }
        return HealthCheck(id: "npm-prefix", title: "npm prefix", severity: .ok,
                           detail: "~/.npmrc sets no prefix override", fix: nil)
    }

    // MARK: - ~/.nvm ownership

    /// Files left root-owned by an old `sudo nvm install` make later installs
    /// fail with EACCES. Walk is capped (entries + deadline) so a huge
    /// versions tree never blocks the main actor.
    static func ownership(nvmDir: URL, currentUID: UInt32, fileManager: FileManager) -> HealthCheck {
        var foreignCount = 0
        var examples: [String] = []
        let deadline = Date().addingTimeInterval(8)

        func checkOwner(_ path: String) {
            guard let uid = (try? fileManager.attributesOfItem(atPath: path))?[.ownerAccountID] as? Int,
                  UInt32(uid) != currentUID else { return }
            foreignCount += 1
            if examples.count < 3 { examples.append(path) }
        }

        checkOwner(nvmDir.path)
        var visited = 0
        var capped = false
        if let enumerator = fileManager.enumerator(at: nvmDir, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator {
                checkOwner(url.path)
                visited += 1
                if foreignCount >= 3 || visited >= 5_000 || Date() > deadline { capped = true; break }
            }
        }

        if foreignCount > 0 {
            let sample = examples.joined(separator: "\n")
            let countText = capped ? "3+" : "\(foreignCount)"
            return HealthCheck(id: "nvm-ownership", title: "~/.nvm has files you don’t own",
                               severity: .error,
                               detail: "\(countText) file(s) under \(nvmDir.path) are owned by another user "
                                    + "(usually an old sudo nvm install). Example paths:\n\(sample)",
                               fix: "sudo chown -R \"$(whoami)\" \(nvmDir.path)")
        }
        return HealthCheck(id: "nvm-ownership", title: "~/.nvm ownership", severity: .ok,
                           detail: "every file checked is owned by you", fix: nil)
    }

    // MARK: - Homebrew nvm

    /// Upstream nvm is git-installed into ~/.nvm; Homebrew's formula relocates
    /// it and brew upgrades can change NVM_DIR behind your back.
    static func homebrew(brewNvmPaths: [URL], fileManager: FileManager) -> HealthCheck {
        if let hit = brewNvmPaths.first(where: { fileManager.fileExists(atPath: $0.path) }) {
            return HealthCheck(id: "homebrew-nvm", title: "Homebrew-managed nvm found",
                               severity: .warning,
                               detail: "\(hit.path) exists — a brew-managed nvm isn’t the upstream install; "
                                    + "brew upgrades can move NVM_DIR out from under your shell config.",
                               fix: "Reinstall nvm with the official git installer (clone into ~/.nvm)")
        }
        return HealthCheck(id: "homebrew-nvm", title: "Install source", severity: .ok,
                           detail: "no Homebrew-managed nvm detected", fix: nil)
    }
}
