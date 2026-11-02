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
