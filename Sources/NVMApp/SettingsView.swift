import AppKit
import NVMCore
import SwiftUI

struct SettingsView: View {
    let model: NVMModel
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("hookAutoInstall") private var hookAutoInstall = true

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

                Section("Terminal auto-use") {
                    LabeledContent("~/.zshrc hook", value: hookStatusLine)

                    Toggle("Install a missing pinned version automatically on cd", isOn: $hookAutoInstall)
                        .onChange(of: hookAutoInstall) { _, value in
                            if model.hookStatus == .installed { model.reinstallHook(autoInstall: value) }
                        }

                    HStack {
                        Button("Install") { model.installHook(autoInstall: hookAutoInstall) }
                            .disabled(model.hookStatus == .installed
                                      || model.hookStatus == .foreign
                                      || !model.hasNvmInZshrc)
                            .help(model.hasNvmInZshrc
                                  ? "Adds the nvm auto-use block to ~/.zshrc"
                                  : "~/.zshrc does not source nvm.sh — add that first")
                        Button("Remove") { model.removeHook() }
                            .disabled(model.hookStatus != .installed && model.hookStatus != .corrupted)
                    }
                    .disabled(model.hookBusy != .idle)

                    if let message = hookMessageLine {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                    if !model.hasNvmInZshrc {
                        Label("Your ~/.zshrc doesn't source nvm.sh, so the hook would fail on cd.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Text("zsh only. Open a new terminal window for changes to take effect.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Terminal button") {
                    Text("The terminal icon on installed versions and pinned folders opens "
                         + "a shell with that version active: a new tab in Terminal's front "
                         + "window when Terminal is already open, a new window when it isn't. "
                         + "Folder buttons cd into the folder first.")
                        .font(.callout)
                    Text("First use asks for Automation permission (System Settings → "
                         + "Privacy & Security → Automation → Node Versions → Terminal). "
                         + "Reset the prompt with: tccutil reset AppleEvents com.illusion.nvm-app")
                        .font(.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Section("Health") {
                    if problems.isEmpty {
                        Label("No setup problems found", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    ForEach(problems) { check in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: check.severity == .error
                                  ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(check.severity == .error ? Color.red : Color.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(check.title).font(.callout.weight(.semibold))
                                Text(check.detail).font(.caption).foregroundStyle(.secondary)
                                if let fix = check.fix {
                                    Text(fix).font(.caption.monospaced()).textSelection(.enabled)
                                }
                            }
                        }
                    }
                    Button("Re-run checks") { Task { await model.refreshHealth() } }
                }

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

    private var problems: [HealthCheck] {
        model.healthChecks.filter { $0.severity != .ok }
    }

    private var hookStatusLine: String {
        switch model.hookStatus {
        case .absent: "not installed"
        case .installed: "installed"
        case .corrupted: "partial block — press Remove, then Install"
        case .foreign: "your own chpwd hook already exists"
        }
    }

    private var hookMessageLine: String? {
        switch model.hookBusy {
        case .busy(let label): label
        case .failed(let message): message
        case .idle: nil
        }
    }

    private var cacheLine: String {
        guard let fetchedAt = model.distFetchedAt else { return "not fetched yet" }
        return fetchedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}

/// Applies the persisted theme choice to the whole app (nil = follow system).
@MainActor
func applyAppearance(_ name: String) {
    switch name {
    case "light": NSApp.appearance = NSAppearance(named: .aqua)
    case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
    default: NSApp.appearance = nil
    }
}
