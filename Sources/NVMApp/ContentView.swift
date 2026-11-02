import NVMCore
import SwiftUI

enum VersionFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case lts = "LTS"
    case installed = "Installed"
    var id: String { rawValue }
}

enum TableStyle: String, CaseIterable, Identifiable {
    case full = "Full"
    case compact = "Compact"
    var id: String { rawValue }
}

struct InstallTarget: Identifiable, Hashable {
    let raw: String
    var id: String { raw }
}

struct FolderTarget: Identifiable, Hashable {
    let url: URL
    var id: String { url.path }
}

struct ContentView: View {
    @Environment(NVMModel.self) private var model
    @State private var filter: VersionFilter = .all
    @State private var tableStyle: TableStyle = .full
    @State private var installingTarget: InstallTarget?
    @State private var pendingUninstall: String?
    @State private var pinTarget: FolderTarget?

    var body: some View {
        Group {
            switch model.status {
            case .checking:
                ProgressView("Looking for nvm…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notInstalled:
                SetupView()
            case .ready:
                home
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
        .sheet(item: $installingTarget) { target in
            InstallSheet(model: model, version: target.raw, installed: model.installed.map(\.raw))
        }
        .sheet(item: $pinTarget) { target in
            PinEditor(model: model, folder: target.url)
        }
        .confirmationDialog(
            "Uninstall \(pendingUninstall ?? "")? Its global npm packages go with it.",
            isPresented: .init(
                get: { pendingUninstall != nil },
                set: { if !$0 { pendingUninstall = nil } }),
            titleVisibility: .visible)
        {
            Button("Uninstall", role: .destructive) {
                if let raw = pendingUninstall {
                    Task { await model.uninstall(raw) }
                }
                pendingUninstall = nil
            }
        }
    }

    private var home: some View {
        VStack(spacing: 0) {
            BannerCard(model: model)
            PinCard(model: model, onEdit: { pinTarget = FolderTarget(url: $0) })
            controls
            Divider()
            VersionTable(model: model, filter: filter, style: tableStyle,
                         onInstallWithOptions: { installingTarget = InstallTarget(raw: $0) },
                         onUninstall: { pendingUninstall = $0 })
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("Filter", selection: $filter) {
                ForEach(VersionFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .labelsHidden()

            Picker("Table style", selection: $tableStyle) {
                ForEach(TableStyle.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 170)
            .labelsHidden()

            Spacer()

            Button {
                Task {
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask { await model.loadRemote() }
                        group.addTask { await model.refreshDist() }
                    }
                    await model.refreshExtras()
                }
            } label: {
                Label("Update versions", systemImage: "arrow.clockwise")
            }
            .disabled(model.remoteBusy != .idle || model.distBusy != .idle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var statusBar: some View {
        VStack(spacing: 2) {
            if let busy = activeBusy {
                Label(busyMessage(busy), systemImage: busyImage(busy))
                    .font(.callout)
                    .foregroundStyle(busyColor(busy))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
            }
            HStack {
                Text("nvm \(model.nvmVersionLabel ?? "—")")
                Text("·").foregroundStyle(.secondary)
                Text(model.layout.nvmDir.path).font(.caption).foregroundStyle(.secondary)
                if let fetchedAt = model.distFetchedAt {
                    Text("·").foregroundStyle(.secondary)
                    Text("metadata \(fetchedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }

    private var activeBusy: BusyAction? {
        for candidate in [model.installBusy, model.actionBusy, model.remoteBusy]
        where candidate != .idle { return candidate }
        return nil
    }

    private func busyMessage(_ busy: BusyAction) -> String {
        switch busy {
        case .idle: return ""
        case .busy(let label): return label
        case .failed(let message): return message
        }
    }

    private func busyImage(_ busy: BusyAction) -> String {
        switch busy {
        case .idle: return ""
        case .busy: return "hammer"
        case .failed: return "exclamationmark.octagon"
        }
    }

    private func busyColor(_ busy: BusyAction) -> AnyShapeStyle {
        switch busy {
        case .failed: AnyShapeStyle(Color.red)
        default: AnyShapeStyle(Color.secondary)
        }
    }
}

struct VersionBadge: View {
    let text: String
    var color: Color = Color.accentColor
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
