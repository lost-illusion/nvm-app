import Foundation
import Observation

public enum NVMStatus: Sendable {
    case checking
    case notInstalled
    case ready
}

public enum BusyAction: Sendable, Equatable {
    case idle
    case busy(String)
    case failed(String)
}

/// The app-facing state. Reads come from disk (NVMLayout); every mutation runs a
/// real `nvm` command so nvm's own rules (locks, alias files, .nvmrc) stay intact.
@MainActor
@Observable
public final class NVMModel {
    public private(set) var status: NVMStatus = .checking
    public private(set) var nvmVersionLabel: String?
    public private(set) var installed: [NodeVersion] = []
    /// Normalized raws of installed versions, for cheap catalog-row lookups.
    public private(set) var installedNormalized: Set<String> = []
    public private(set) var aliasPairs: [(name: String, target: String)] = []
    /// `nvm version default` output: a resolved `vX.Y.Z` or `N/A`.
    public private(set) var resolvedDefault: String?

    public private(set) var remote: [RemoteVersion] = []
    public private(set) var remoteBusy: BusyAction = .idle

    public private(set) var installBusy: BusyAction = .idle
    public private(set) var installLog: String = ""

    public private(set) var actionBusy: BusyAction = .idle

    /// nodejs.org dist/index.json metadata, keyed by normalized version ("22.22.1").
    public private(set) var distEntries: [String: DistEntry] = [:]
    public private(set) var distFetchedAt: Date?
    public private(set) var distBusy: BusyAction = .idle

    /// Disk extras for installed versions, keyed like distEntries.
    public private(set) var extras: [String: NVMLayout.InstallExtras] = [:]

    /// Project `.nvmrc` awareness: watched folders (plus a hidden list — hiding
    /// only removes the watch, never touches the real `.nvmrc`), each with the
    /// folder's raw spec and the concrete version nvm maps it to.
    public struct PinState: Sendable, Equatable {
        public var spec: String?
        public var resolved: String?
        public var busy: BusyAction = .idle
    }

    public private(set) var projectFolders: [URL] = []
    public private(set) var hiddenFolders: [URL] = []
    public private(set) var pinStates: [String: PinState] = [:]  // keyed by folder path
    public private(set) var scanBusy: BusyAction = .idle
    public private(set) var scanInfo: String?

    /// Versions released after the app launched get a "new" badge.
    public let launchedAt = Date()

    /// Refresh the dist cache when it is older than this (background, non-blocking).
    public static let maxCacheAge: TimeInterval = 24 * 3600

    public let layout: NVMLayout
    private let runner: NVMShellRunner
    private let distStore: DistIndexStore

    public init(layout: NVMLayout,
                cacheDirectory: URL = FileManager.default
                    .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                    .appendingPathComponent("nvm-app", isDirectory: true)) {
        self.layout = layout
        self.runner = NVMShellRunner(layout: layout)
        self.distStore = DistIndexStore(directory: cacheDirectory)
        let defaults = UserDefaults.standard
        func urls(forKey key: String) -> [URL] {
            (defaults.stringArray(forKey: key) ?? [])
                .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        }
        var visible = urls(forKey: "projectFolders")
        // Migrate the single-folder key from the first .nvmrc iteration.
        if let legacy = defaults.string(forKey: "projectFolder") {
            let legacyURL = URL(fileURLWithPath: (legacy as NSString).expandingTildeInPath)
            if !visible.contains(where: { $0.path == legacyURL.path }) { visible.append(legacyURL) }
            defaults.removeObject(forKey: "projectFolder")
        }
        self.projectFolders = visible
        self.hiddenFolders = urls(forKey: "hiddenProjectFolders")
    }

    public func refresh() async {
        guard layout.isInstalled else {
            status = .notInstalled
            return
        }
        let versionResult = await runner.run(["--version"])
        guard versionResult.isSuccess else {
            status = .notInstalled
            return
        }
        nvmVersionLabel = versionResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        installed = layout.installedVersions()
        installedNormalized = Set(installed.map { NodeVersion.normalize($0.raw) })
        aliasPairs = layout.aliasPairs()
        let defaultResult = await runner.run(["version", "default"])
        resolvedDefault = defaultResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        status = .ready
    }

    public func loadRemote() async {
        guard status == .ready else { return }
        remoteBusy = .busy("Fetching the remote version list…")
        let result = await runner.run(["ls-remote", "--no-colors"])
        if result.isSuccess {
            remote = RemoteCatalogParser.parse(result.output)
            remoteBusy = .idle
        } else {
            remoteBusy = .failed("ls-remote failed (exit \(result.status)): network or mirror problem")
        }
    }

    /// Launch path: render instantly from the on-disk cache, then re-fetch in the
    /// background only when the cache is missing or older than maxCacheAge.
    public func prepareDistAtLaunch() async {
        let store = distStore
        let snapshot = await Task.detached(priority: .userInitiated) { store.load() }.value
        if let snapshot {
            distEntries = Self.index(snapshot.entries)
            distFetchedAt = snapshot.fetchedAt
            if Date().timeIntervalSince(snapshot.fetchedAt) > Self.maxCacheAge {
                await refreshDist()
            }
        } else {
            await refreshDist()
        }
    }

    /// Background download of nodejs.org/dist/index.json (gzip-requested).
    /// Fetch + JSON decode + cache write all run off the main actor.
    public func refreshDist() async {
        distBusy = .busy("Downloading version metadata…")
        let store = distStore
        let outcome: Result<[DistEntry], any Error> = await Task.detached(priority: .userInitiated) {
            do {
                let entries = try await DistFetcher.fetch()
                store.save(entries, fetchedAt: Date())
                return .success(entries)
            } catch {
                return .failure(error)
            }
        }.value
        switch outcome {
        case .success(let entries):
            distEntries = Self.index(entries)
            distFetchedAt = Date()
            distBusy = .idle
        case .failure:
            // Cache (if any) stays usable; say so rather than blanking the table.
            distBusy = .failed(distEntries.isEmpty
                ? "Could not download version metadata (offline?)"
                : "Metadata refresh failed — showing cached data")
        }
    }

    public func refreshExtras() async {
        let layout = self.layout
        extras = await Task.detached(priority: .userInitiated) { layout.computeExtras() }.value
    }

    public func pinState(for folder: URL) -> PinState {
        pinStates[folder.path] ?? PinState()
    }

    public func watchFolder(_ url: URL) async {
        hiddenFolders.removeAll { $0.path == url.path }
        if !projectFolders.contains(where: { $0.path == url.path }) {
            projectFolders.append(url)
        }
        persistFolders()
        await refreshPin(for: url)
    }

    public func showHiddenFolder(_ url: URL) async {
        hiddenFolders.removeAll { $0.path == url.path }
        if !projectFolders.contains(where: { $0.path == url.path }) {
            projectFolders.append(url)
        }
        persistFolders()
        await refreshPin(for: url)
    }

    /// Watch-only hide: the folder's `.nvmrc` file is left untouched, and the
    /// folder returns via the Hidden menu.
    public func hideFolder(_ url: URL) {
        projectFolders.removeAll { $0.path == url.path }
        if !hiddenFolders.contains(where: { $0.path == url.path }) {
            hiddenFolders.append(url)
        }
        pinStates.removeValue(forKey: url.path)
        persistFolders()
    }

    /// Walks `dir` for `.nvmrc` files and watches every hit (hidden folders
    /// stay hidden — a hide outranks a rediscovery).
    public func scanForPins(under dir: URL, label: String) async {
        scanBusy = .busy("Scanning \(label) for .nvmrc…")
        let found = await Task.detached(priority: .userInitiated) {
            NvmrcScanner.scan(under: dir)
        }.value
        var added = 0
        for folder in found {
            guard !projectFolders.contains(where: { $0.path == folder.path }),
                  !hiddenFolders.contains(where: { $0.path == folder.path }) else { continue }
            projectFolders.append(folder)
            added += 1
        }
        persistFolders()
        scanInfo = "Found \(found.count) .nvmrc under \(dir.path) — \(added) newly watched"
        scanBusy = .idle
        await refreshAllPins()
    }

    /// Pins resolve through zsh, so refresh in bounded chunks rather than
    /// spawning one shell per watched folder after a big scan.
    public func refreshAllPins() async {
        let folders = projectFolders
        var start = 0
        while start < folders.count {
            let end = min(start + 6, folders.count)
            await withTaskGroup(of: Void.self) { group in
                for folder in folders[start..<end] {
                    group.addTask { await self.refreshPin(for: folder) }
                }
            }
            start = end
        }
    }

    /// Read `<folder>/.nvmrc` and ask nvm what it resolves to.
    public func refreshPin(for folder: URL) async {
        var state = pinState(for: folder)
        state.spec = Nvmrc.read(in: folder)
        guard let spec = state.spec else {
            state.resolved = nil
            state.busy = .idle
            pinStates[folder.path] = state
            return
        }
        state.busy = .busy("Resolving…")
        pinStates[folder.path] = state

        // `nvm version` resolves locally (alias or installed version); N/A means
        // nothing local matches, so ask the remote catalog via `version-remote`.
        let local = await runner.run(["version", spec])
        let localOut = local.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if local.isSuccess, !localOut.isEmpty, localOut != "N/A" {
            state.resolved = localOut
            state.busy = .idle
            pinStates[folder.path] = state
            return
        }
        let remote = await runner.run(["version-remote", spec])
        let remoteOut = remote.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if remote.isSuccess, !remoteOut.isEmpty, remoteOut != "N/A" {
            state.resolved = remoteOut
            state.busy = .idle
        } else {
            state.resolved = nil
            state.busy = .failed("nvm can’t resolve “\(spec)”")
        }
        pinStates[folder.path] = state
    }

    public func writePin(_ spec: String, for folder: URL) async {
        Nvmrc.write(spec, in: folder)
        await refreshPin(for: folder)
    }

    public func clearPin(for folder: URL) {
        Nvmrc.remove(from: folder)
        var state = pinState(for: folder)
        state.spec = nil
        state.resolved = nil
        state.busy = .idle
        pinStates[folder.path] = state
    }

    public func pinInstalled(_ resolved: String?) -> Bool {
        NodeVersion.parse(resolved ?? "").map(isInstalled) ?? false
    }

    public func pinIsDefault(_ resolved: String?) -> Bool {
        NodeVersion.parse(resolved ?? "").map(isDefault) ?? false
    }

    private func persistFolders() {
        let defaults = UserDefaults.standard
        defaults.set(projectFolders.map(\.path), forKey: "projectFolders")
        defaults.set(hiddenFolders.map(\.path), forKey: "hiddenProjectFolders")
    }

    // MARK: - terminal auto-use hook (~/.zshrc chpwd)

    public private(set) var hookStatus: AutoUseHook.Status = .absent
    public private(set) var hookBusy: BusyAction = .idle
    /// Whether ~/.zshrc sources nvm.sh — the hook calls nvm functions, so
    /// without this it would error on every `cd`.
    public private(set) var hasNvmInZshrc = false

    public var zshrcURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zshrc")
    }
    private var zshrcBackupURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zshrc.bak-nvm-app")
    }

    public func refreshHookStatus() {
        let text = (try? String(contentsOf: zshrcURL, encoding: .utf8)) ?? ""
        hasNvmInZshrc = text.contains("nvm.sh")
        hookStatus = AutoUseHook.status(in: text)
    }

    public func installHook(autoInstall: Bool) {
        hookBusy = .busy("Updating ~/.zshrc…")
        let text = (try? String(contentsOf: zshrcURL, encoding: .utf8)) ?? ""
        var base = text
        switch AutoUseHook.status(in: base) {
        case .installed:
            hookBusy = .idle
            refreshHookStatus()
            return
        case .foreign:
            hookBusy = .failed("~/.zshrc already has its own chpwd hook — leaving it alone")
            return
        case .corrupted:
            // Strip the orphan block first, then write a fresh one.
            base = AutoUseHook.remove(from: base)
        case .absent:
            break
        }
        backupZshrcOnce()
        let updated = AutoUseHook.install(into: base, autoInstall: autoInstall)
        try? updated.write(to: zshrcURL, atomically: true, encoding: .utf8)
        hookBusy = .idle
        refreshHookStatus()
    }

    public func removeHook() {
        guard hookStatus == .installed || hookStatus == .corrupted else { return }
        hookBusy = .busy("Updating ~/.zshrc…")
        let text = (try? String(contentsOf: zshrcURL, encoding: .utf8)) ?? ""
        backupZshrcOnce()
        let updated = AutoUseHook.remove(from: text)
        try? updated.write(to: zshrcURL, atomically: true, encoding: .utf8)
        hookBusy = .idle
        refreshHookStatus()
    }

    /// Re-write our block after the auto-install toggle changes.
    public func reinstallHook(autoInstall: Bool) {
        guard hookStatus == .installed else { return }
        removeHook()
        installHook(autoInstall: autoInstall)
    }

    private func backupZshrcOnce() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: zshrcBackupURL.path),
              fm.fileExists(atPath: zshrcURL.path) else { return }
        try? fm.copyItem(at: zshrcURL, to: zshrcBackupURL)
    }

    public func distMeta(for version: NodeVersion) -> DistEntry? {
        distEntries[NodeVersion.normalize(version.raw)]
    }

    public func extras(for version: NodeVersion) -> NVMLayout.InstallExtras? {
        extras[NodeVersion.normalize(version.raw)]
    }

    /// LTS codename for a row: per-patch metadata wins over ls-remote's
    /// latest-patch-only marker.
    public func ltsCodename(for entry: RemoteVersion) -> String? {
        distMeta(for: entry.version)?.ltsCodename ?? entry.ltsCodename
    }

    public func isNewSinceLaunch(_ version: NodeVersion) -> Bool {
        guard let date = distMeta(for: version)?.releaseDate else { return false }
        return date > launchedAt
    }

    private static func index(_ entries: [DistEntry]) -> [String: DistEntry] {
        Dictionary(entries.map { (NodeVersion.normalize($0.version), $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func install(raw: String, offline: Bool = false, migrateFrom: String? = nil) async {
        guard status == .ready else { return }
        var arguments = ["install"]
        if offline { arguments.append("--offline") }
        if let migrateFrom, !migrateFrom.isEmpty {
            arguments.append("--reinstall-packages-from=\(migrateFrom)")
        }
        arguments.append(raw)

        installBusy = .busy("Installing \(raw)…")
        installLog = ""
        let result = await runner.runStreaming(arguments) { chunk in
            Task { @MainActor in self.installLog += chunk }
        }
        if result.isSuccess {
            installBusy = .idle
            await refresh()
        } else {
            installBusy = .failed("install \(raw) failed (exit \(result.status)) — see log")
        }
    }

    public func uninstall(_ raw: String) async {
        await runAction(["uninstall", raw], label: "Uninstalling \(raw)…")
    }

    public func setDefault(_ raw: String) async {
        await runAction(["alias", "default", raw], label: "Setting default to \(raw)…")
    }

    private func runAction(_ arguments: [String], label: String) async {
        guard status == .ready else { return }
        actionBusy = .busy(label)
        let result = await runner.run(arguments)
        if result.isSuccess {
            actionBusy = .idle
            await refresh()
        } else {
            actionBusy = .failed("\(label.components(separatedBy: "…")[0]) failed "
                + "(exit \(result.status)): \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    public func isInstalled(_ version: NodeVersion) -> Bool {
        installedNormalized.contains(NodeVersion.normalize(version.raw))
    }

    public func isDefault(_ version: NodeVersion) -> Bool {
        NodeVersion.normalize(version.raw) == NodeVersion.normalize(resolvedDefault ?? "")
    }

    /// Copy-pasteable command the user can run in their own terminal to switch
    /// an existing shell — the GUI cannot reach other shells (capabilities doc §13.3).
    public func useCommand(for raw: String) -> String { "nvm use \(raw)" }
}
