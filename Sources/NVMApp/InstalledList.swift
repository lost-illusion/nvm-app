import AppKit
import NVMCore
import SwiftUI

struct InstalledList: View {
    @Environment(NVMModel.self) private var model
    let onInstall: (String) -> Void

    @State private var pendingUninstall: NodeVersion?

    var body: some View {
        List {
            if model.installed.isEmpty {
                Text("No node versions installed yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.installed) { version in
                HStack(spacing: 10) {
                    Text(version.raw)
                        .font(.body.monospaced())
                    if isDefault(version) {
                        VersionBadge(text: "default")
                    }
                    ForEach(aliases(for: version), id: \.self) { name in
                        VersionBadge(text: name, color: .purple)
                    }
                    Spacer()
                    Button("Set default") { Task { await model.setDefault(version.raw) } }
                        .disabled(isDefault(version))
                    Button(role: .destructive) { pendingUninstall = version } label: {
                        Text("Uninstall")
                    }
                }
                .contextMenu {
                    Button("Copy `nvm use` command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.useCommand(for: version.raw), forType: .string)
                    }
                }
            }
        }
        .navigationTitle("Installed")
        .overlay {
            if model.installed.isEmpty && model.status == .ready {
                Button("Install latest LTS") { onInstall("lts/*") }
            }
        }
        .confirmationDialog(
            "Uninstall \(pendingUninstall?.raw ?? "")? Its global npm packages go with it.",
            isPresented: .init(
                get: { pendingUninstall != nil },
                set: { if !$0 { pendingUninstall = nil } }),
            titleVisibility: .visible)
        {
            Button("Uninstall", role: .destructive) {
                if let version = pendingUninstall {
                    Task { await model.uninstall(version.raw) }
                }
                pendingUninstall = nil
            }
        }
    }

    private func isDefault(_ version: NodeVersion) -> Bool {
        normalize(version.raw) == normalize(model.resolvedDefault ?? "")
    }

    private func aliases(for version: NodeVersion) -> [String] {
        model.aliasPairs.compactMap { pair in
            guard pair.name != "default" else { return nil }
            return normalize(pair.target) == normalize(version.raw) ? pair.name : nil
        }
    }

    private func normalize(_ raw: String) -> String {
        raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
    }
}
