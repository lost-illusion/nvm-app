import NVMCore
import SwiftUI

/// Home banner: the version new shells start on (with a dropdown to switch it),
/// how many versions are installed, and the latest version available remotely.
struct BannerCard: View {
    let model: NVMModel

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Default version")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.resolvedDefault ?? "none")
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                    if !model.installed.isEmpty {
                        Menu {
                            ForEach(model.installed) { version in
                                Button(model.isDefault(version) ? "\(version.raw) ✓" : version.raw) {
                                    Task { await model.setDefault(version.raw) }
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.down.circle")
                                .font(.title2)
                        }
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Switch the default version")
                    }
                }
                Text("\(model.installed.count) installed")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Latest available")
                    .font(.caption).foregroundStyle(.secondary)
                if let latest = latestAvailable {
                    Text(latest)
                        .font(.system(size: 26, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                } else if model.remoteBusy != .idle {
                    ProgressView().controlSize(.small)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .padding(12)
    }

    private var latestAvailable: String? {
        model.remote.first(where: \.isLatestCurrent)?.version.raw
            ?? model.remote.map(\.version).max()?.raw
    }
}
