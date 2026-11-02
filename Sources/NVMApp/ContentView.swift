import NVMCore
import SwiftUI

enum Pane: String, CaseIterable, Identifiable {
    case installed = "Installed"
    case available = "Available"
    var id: String { rawValue }
}

struct InstallTarget: Identifiable, Hashable {
    let raw: String
    var id: String { raw }
}

struct ContentView: View {
    @Environment(NVMModel.self) private var model
    @State private var pane: Pane = .installed
    @State private var installingTarget: InstallTarget?

    var body: some View {
        Group {
            switch model.status {
            case .checking:
                ProgressView("Looking for nvm…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notInstalled:
                SetupView()
            case .ready:
                NavigationSplitView {
                    List(Pane.allCases, selection: $pane) { pane in
                        Label(pane.rawValue, systemImage: pane == .installed ? "checkmark.circle" : "cloud")
                    }
                    .navigationSplitViewColumnWidth(min: 150, ideal: 170)
                } detail: {
                    detail
                        .toolbar {
                            ToolbarItem {
                                Button { Task { await model.refresh() } } label: {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                }
                            }
                        }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
        .sheet(item: $installingTarget) { target in
            InstallSheet(model: model, version: target.raw, installed: model.installed.map(\.raw))
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch pane {
        case .installed: InstalledList(onInstall: { installingTarget = InstallTarget(raw: $0) })
        case .available: AvailableList(onInstall: { installingTarget = InstallTarget(raw: $0) })
        }
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
                Text("default: \(model.resolvedDefault ?? "none")")
                Spacer()
                Text(model.layout.nvmDir.path).font(.caption).foregroundStyle(.secondary)
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
