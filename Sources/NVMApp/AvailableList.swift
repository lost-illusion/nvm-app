import NVMCore
import SwiftUI

struct AvailableList: View {
    @Environment(NVMModel.self) private var model
    let onInstall: (String) -> Void

    @State private var search = ""
    @State private var ltsOnly = false

    var body: some View {
        List(filtered) { row in
            HStack(spacing: 10) {
                Text(row.version.raw)
                    .font(.body.monospaced())
                if row.isLatestCurrent { VersionBadge(text: "latest", color: .green) }
                if let codename = row.ltsCodename {
                    VersionBadge(text: "LTS \(codename)", color: .orange)
                }
                ForEach(row.aliasedBy, id: \.self) { name in
                    VersionBadge(text: name, color: .purple)
                }
                Spacer()
                Button("Install") { onInstall(row.version.raw) }
                    .disabled(model.installBusy != .idle)
            }
        }
        .navigationTitle("Available")
        .searchable(text: $search, prompt: "Filter versions")
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $ltsOnly) { Text("LTS lines") }
                    .help("Show only release lines that have an LTS entry")
            }
            ToolbarItem {
                Button { Task { await model.loadRemote() } } label: {
                    Label("Fetch list", systemImage: "cloud.download")
                }
                .disabled(model.remoteBusy != .idle)
            }
        }
        .overlay {
            if model.remote.isEmpty {
                switch model.remoteBusy {
                case .busy(let label): ProgressView(label)
                case .failed(let message): Label(message, systemImage: "exclamationmark.triangle")
                default:
                    VStack(spacing: 8) {
                        Text("Remote catalog not loaded yet")
                        Button("Fetch the version list") { Task { await model.loadRemote() } }
                    }
                }
            }
        }
    }

    private var filtered: [RemoteVersion] {
        // An LTS marker only appears on the latest patch of each LTS line, so
        // filter whole release lines: majors that carry at least one marker.
        let ltsMajors = Set(model.remote.compactMap { $0.ltsCodename != nil ? $0.version.major : nil })
        return model.remote.filter { row in
            if ltsOnly && !ltsMajors.contains(row.version.major) { return false }
            if search.isEmpty { return true }
            return row.version.raw.localizedCaseInsensitiveContains(search)
        }
    }
}
