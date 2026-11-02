import AppKit
import NVMCore
import SwiftUI

struct SettingsView: View {
    let model: NVMModel
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Picker("Theme", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                .onChange(of: appearance) { _, value in applyAppearance(value) }

                Section("Version data") {
                    LabeledContent("nvm", value: model.nvmVersionLabel ?? "—")
                    LabeledContent("NVM_DIR", value: model.layout.nvmDir.path)
                    LabeledContent("Catalog cache", value: cacheLine)
                }
            }
            .formStyle(.grouped)
            Spacer()
        }
        .frame(maxWidth: 620, alignment: .leading)
        .padding(.leading, 16)
    }

    private var cacheLine: String {
        guard let fetchedAt = model.distFetchedAt else { return "not fetched yet" }
        return fetchedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}

/// Applies the persisted theme choice to the whole app (nil = follow system).
func applyAppearance(_ name: String) {
    switch name {
    case "light": NSApp.appearance = NSAppearance(named: .aqua)
    case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
    default: NSApp.appearance = nil
    }
}
