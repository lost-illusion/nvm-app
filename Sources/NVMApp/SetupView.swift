import AppKit
import NVMCore
import SwiftUI

struct SetupView: View {
    @Environment(NVMModel.self) private var model

    private static let installCommand = """
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.8/install.sh | bash
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("nvm not found").font(.title2.bold())
            Text("This app drives a real nvm-sh install. It looked for nvm.sh at:")
            Text(model.layout.nvmScript.path)
                .font(.callout.monospaced())
                .textSelection(.enabled)
            Text("Install nvm (Homebrew copies are not supported by nvm-sh):")
                .foregroundStyle(.secondary)
            Text(Self.installCommand)
                .font(.callout.monospaced())
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .textSelection(.enabled)
            HStack {
                Button("Copy command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.installCommand, forType: .string)
                }
                Button("Retry") { Task { await model.refresh() } }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(maxWidth: 560, alignment: .leading)
    }
}
