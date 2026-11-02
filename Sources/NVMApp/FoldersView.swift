import AppKit
import NVMCore
import SwiftUI

/// Folders page: per-folder `.nvmrc` pins. Scan a directory (or the whole
/// home/disk) to discover `.nvmrc` files, or point one folder without scanning.
/// Hiding a folder only drops it from the watch list — the file is untouched
/// and the folder returns via the Hidden menu.
struct FoldersView: View {
    let model: NVMModel
    let onEdit: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let info = model.scanInfo {
                Text(info)
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.top, 4)
            }
            if model.projectFolders.isEmpty {
                ContentUnavailableView("No watched folders",
                                       systemImage: "folder",
                                       description: Text("Scan for .nvmrc files, or add a folder directly."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.projectFolders, id: \.path) { folder in
                        pinRow(folder)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Project folders").font(.headline)
            Button("Scan…") { pickAndScan() }.controlSize(.small)
            Button("Scan home") {
                Task { await model.scanForPins(under: FileManager.default.homeDirectoryForCurrentUser, label: "home") }
            }
            .controlSize(.small)
            .help("Recursive search under ~/ — skips node_modules, Library, caches")
            Button("Scan disk") {
                Task { await model.scanForPins(under: URL(fileURLWithPath: "/"), label: "whole disk") }
            }
            .controlSize(.small)
            .help("Whole-disk search — system trees are skipped, ~90 s budget, max 300 hits")
            Button("Add folder…") { addFolder() }.controlSize(.small).help("Watch one folder without scanning")
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
            switch model.scanBusy {
            case .busy(let label): ProgressView(label).controlSize(.small)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
            case .idle: EmptyView()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .disabled(model.scanBusy != .idle)
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

            if let resolved = state.resolved {
                Button { model.openFolderInTerminal(folder, spec: resolved) } label: {
                    Image(systemName: "terminal")
                }
                .buttonStyle(.borderless)
                .help("Open Terminal in \(folder.lastPathComponent) with \(resolved) — "
                      + "new tab if Terminal is already open, new window otherwise")
            }
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

    private func pickAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        panel.message = "Pick a directory to search for .nvmrc files"
        if panel.runModal() == .OK, let url = panel.url {
            Task { await model.scanForPins(under: url, label: url.lastPathComponent) }
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
