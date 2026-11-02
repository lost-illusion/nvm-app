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
    public private(set) var aliasPairs: [(name: String, target: String)] = []
    /// `nvm version default` output: a resolved `vX.Y.Z` or `N/A`.
    public private(set) var resolvedDefault: String?

    public private(set) var remote: [RemoteVersion] = []
    public private(set) var remoteBusy: BusyAction = .idle

    public private(set) var installBusy: BusyAction = .idle
    public private(set) var installLog: String = ""

    public private(set) var actionBusy: BusyAction = .idle

    public let layout: NVMLayout
    private let runner: NVMShellRunner

    public init(layout: NVMLayout) {
        self.layout = layout
        self.runner = NVMShellRunner(layout: layout)
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

    /// Copy-pasteable command the user can run in their own terminal to switch
    /// an existing shell — the GUI cannot reach other shells (capabilities doc §13.3).
    public func useCommand(for raw: String) -> String { "nvm use \(raw)" }
}
