import NVMCore
import SwiftUI

struct InstallSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: NVMModel
    let version: String
    let installed: [String]

    @State private var offline = false
    @State private var migrateFrom: String?
    @State private var started = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Install \(version)").font(.title2.bold())

            if let parsed = NodeVersion.parse(version), model.needsRosetta(parsed) {
                Label("Below v16: no arm64 macOS binaries — nvm will use Rosetta 2 or a source build.",
                      systemImage: "cpu")
                    .font(.callout).foregroundStyle(.orange)
            }

            Toggle("Offline (cached download only, no network)", isOn: $offline)

            Picker("Migrate global packages from", selection: $migrateFrom) {
                Text("No migration").tag(String?.none)
                Text("default").tag(String?.some("default"))
                Text("current").tag(String?.some("current"))
                ForEach(installed, id: \.self) { raw in
                    Text(raw).tag(String?.some(raw))
                }
            }
            .pickerStyle(.menu)

            if started {
                switch model.installBusy {
                case .busy(let label):
                    Label(label, systemImage: "hammer")
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                case .idle:
                    Label("Installed \(version).", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                ScrollView {
                    Text(model.installLog.isEmpty ? "…" : model.installLog)
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 180)
            }

            HStack {
                Spacer()
                if started, model.installBusy == .idle || isFailed(model.installBusy) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Install") {
                        started = true
                        Task { await model.install(raw: version, offline: offline, migrateFrom: migrateFrom) }
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
        .padding(20)
        .frame(width: 540)
    }

    private func isFailed(_ action: BusyAction) -> Bool {
        if case .failed = action { return true }
        return false
    }
}
