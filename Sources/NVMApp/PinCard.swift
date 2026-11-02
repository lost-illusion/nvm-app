import AppKit
import NVMCore
import SwiftUI

/// Watch list of project folders and their `.nvmrc` pins. Hiding a folder only
/// drops it from the watch list — the file is untouched and the folder returns
/// via the Hidden menu.
struct PinCard: View {
    let model: NVMModel
    let onEdit: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Label("Projects .nvmrc", systemImage: "folder")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Add folder…") { addFolder() }.controlSize(.small)
                if !model.hiddenFolders.isEmpty {
                    Menu("Hidden (\(model.hiddenFolders.count))") {
                        ForEach(model.hiddenFolders, id: \.path) { url in
                            Button("Show \(url.lastPathComponent)") {
                                Task { await model.showHiddenFolder(url) }
                            }
                        }
                    }
                    .controlSize(.small)
                }
                Spacer()
            }

            if model.projectFolders.isEmpty {
                Text("No watched folders — add a project folder to see its pin.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(model.projectFolders, id: \.path) { folder in
                    pinRow(folder)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.30), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
    }

    private func pinRow(_ folder: URL) -> some View {
        let state = model.pinState(for: folder)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(folder.lastPathComponent)
                    .font(.callout.weight(.semibold))
                Text(folder.path)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(minWidth: 180, alignment: .leading)

            Spacer(minLength: 8)

            statusArea(folder, state)

            Button { onEdit(folder) } label: { Image(systemName: "square.and.pencil") }
                .buttonStyle(.borderless)
                .help("Edit this project’s .nvmrc")
            Button { model.hideFolder(folder) } label: { Image(systemName: "eye.slash") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Hide from watch list — the .nvmrc file is not touched")
        }
    }

    @ViewBuilder
    private func statusArea(_ folder: URL, _ state: NVMModel.PinState) -> some View {
        switch state.busy {
        case .busy(let label):
            ProgressView(label).controlSize(.small)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.red)
        case .idle:
            if state.spec == nil {
                Text("no .nvmrc here").font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Text("“\(state.spec ?? "")”").font(.callout.italic())
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                    Text(state.resolved ?? "?").font(.callout.monospaced())
                    if model.pinIsDefault(state.resolved) {
                        VersionBadge(text: "default", color: .accentColor)
                    } else if model.pinInstalled(state.resolved) {
                        VersionBadge(text: "installed", color: .blue)
                        Button("Set default") {
                            if let resolved = state.resolved {
                                Task { await model.setDefault(resolved) }
                            }
                        }
                        .controlSize(.small)
                    } else {
                        VersionBadge(text: "not installed", color: .orange)
                        Button("Install it") {
                            if let resolved = state.resolved {
                                Task { await model.install(raw: resolved) }
                            }
                        }
                        .controlSize(.small)
                        .disabled(model.installBusy != .idle)
                    }
                }
            }
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Watch"
        panel.message = "Pick a project folder to watch its .nvmrc"
        if panel.runModal() == .OK, let url = panel.url {
            Task { await model.watchFolder(url) }
        }
    }
}

/// Sheet to write or remove the `.nvmrc` pin of one watched folder.
struct PinEditor: View {
    let model: NVMModel
    let folder: URL
    @Environment(\.dismiss) private var dismiss
    @State private var spec = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pin a version in \(folder.lastPathComponent)/.nvmrc")
                .font(.headline)

            TextField("spec: 22 · 22.20.0 · lts/* · node", text: $spec)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)

            VStack(alignment: .leading, spacing: 6) {
                Text("Suggestions").font(.caption).foregroundStyle(.secondary)
                HStack {
                    ForEach(model.installed.prefix(4)) { version in
                        Button(version.raw) { spec = version.raw }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                    Button("lts/*") { spec = "lts/*" }.buttonStyle(.bordered).controlSize(.small)
                    if let latest = model.remote.first?.version.raw {
                        Button(latest) { spec = latest }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }

            HStack(spacing: 8) {
                Button("Save") {
                    Task { await model.writePin(spec.trimmingCharacters(in: .whitespaces), for: folder); dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(spec.trimmingCharacters(in: .whitespaces).isEmpty)

                if model.pinState(for: folder).spec != nil {
                    Button("Remove .nvmrc", role: .destructive) {
                        model.clearPin(for: folder)
                        dismiss()
                    }
                }

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 440)
        .onAppear { spec = model.pinState(for: folder).spec ?? model.installed.first?.raw ?? "" }
    }
}
