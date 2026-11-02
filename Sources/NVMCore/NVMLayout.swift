import Foundation

/// The on-disk state model of an nvm-sh install (see docs/nvm-capabilities.md §2).
/// Installed versions and aliases can be read without invoking a shell;
/// anything that changes state goes through NVMShellRunner.
public struct NVMLayout: Sendable {
    public let nvmDir: URL

    public init(nvmDir: URL) { self.nvmDir = nvmDir }

    public var nvmScript: URL { nvmDir.appendingPathComponent("nvm.sh") }
    public var versionsDir: URL { nvmDir.appendingPathComponent("versions/node", isDirectory: true) }
    public var aliasDir: URL { nvmDir.appendingPathComponent("alias", isDirectory: true) }
    public var cacheLocksDir: URL { nvmDir.appendingPathComponent(".cache/locks", isDirectory: true) }

    public var isInstalled: Bool {
        FileManager.default.isReadableFile(atPath: nvmScript.path)
    }

    /// ~/.nvm, or $XDG_CONFIG_HOME/nvm when set; `override` wins and may contain `~`.
    public static func detect(
        override: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> NVMLayout {
        if let override, !override.isEmpty {
            return NVMLayout(nvmDir: URL(fileURLWithPath: (override as NSString).expandingTildeInPath))
        }
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return NVMLayout(nvmDir: URL(fileURLWithPath: xdg).appendingPathComponent("nvm", isDirectory: true))
        }
        return NVMLayout(nvmDir: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".nvm", isDirectory: true))
    }

    public func installedVersions(fileManager: FileManager = .default) -> [NodeVersion] {
        let names = (try? fileManager.contentsOfDirectory(atPath: versionsDir.path)) ?? []
        return names.compactMap(NodeVersion.parse).sorted(by: >)
    }

    /// `(name, stored target)` for every alias file. `alias/lts/*` is nvm-managed
    /// — display it, never edit it (capabilities doc §5).
    public func aliasPairs(fileManager: FileManager = .default) -> [(name: String, target: String)] {
        var pairs: [(name: String, target: String)] = []
        collectAliases(in: aliasDir, prefix: "", fileManager: fileManager, into: &pairs)
        return pairs.sorted { $0.name < $1.name }
    }

    /// Disk-side facts about an installed version, for table extras.
    public struct InstallExtras: Sendable, Equatable {
        public let globals: Int
        public let sizeBytes: Int64
        public let installedAt: Date?
    }

    /// Walks every installed version's directory (size + mtime + global npm
    /// packages). Heavier than the other reads — call from a background task.
    public func computeExtras(fileManager: FileManager = .default) -> [String: InstallExtras] {
        var result: [String: InstallExtras] = [:]
        for version in installedVersions(fileManager: fileManager) {
            let dir = versionsDir.appendingPathComponent(version.raw, isDirectory: true)
            let attrs = try? fileManager.attributesOfItem(atPath: dir.path)
            let installedAt = attrs?[.creationDate] as? Date

            var size: Int64 = 0
            if let enumerator = fileManager.enumerator(
                at: dir, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
                    size += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
                }
            }

            let modulesDir = dir.appendingPathComponent("lib/node_modules", isDirectory: true)
            let topLevel = (try? fileManager.contentsOfDirectory(atPath: modulesDir.path)) ?? []
            let globals = topLevel.filter { $0 != "npm" && $0 != "corepack" }.count

            result[NodeVersion.normalize(version.raw)] = InstallExtras(
                globals: globals, sizeBytes: size, installedAt: installedAt)
        }
        return result
    }

    private func collectAliases(in dir: URL, prefix: String, fileManager: FileManager,
                                into pairs: inout [(name: String, target: String)]) {
        guard let children = try? fileManager.contentsOfDirectory(atPath: dir.path) else { return }
        for child in children.sorted() {
            let url = dir.appendingPathComponent(child)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                collectAliases(in: url, prefix: prefix + child + "/", fileManager: fileManager, into: &pairs)
            } else if let raw = try? String(contentsOf: url, encoding: .utf8) {
                let target = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !target.isEmpty {
                    pairs.append((name: prefix + child, target: target))
                }
            }
        }
    }
}
