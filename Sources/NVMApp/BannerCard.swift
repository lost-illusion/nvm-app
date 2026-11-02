import NVMCore
import SwiftUI

/// Home banner: the version new shells start on (the version text itself is the
/// dropdown), what it ships (LTS line, npm, date), installed footprint, and
/// the latest available version with its distance from the default.
struct BannerCard: View {
    let model: NVMModel

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            defaultBlock
            Spacer()
            latestBlock
        }
        .padding(16)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .padding(12)
    }

    // MARK: - default

    private var defaultVersion: NodeVersion? {
        NodeVersion.parse(model.resolvedDefault ?? "")
    }

    private var defaultBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Default version")
                    .font(.caption).foregroundStyle(.secondary)
                if model.installed.isEmpty {
                    Text("· nothing installed").font(.caption).foregroundStyle(.orange)
                } else if defaultVersion == nil {
                    Text("· none set — pick one").font(.caption).foregroundStyle(.orange)
                }
            }

            Menu {
                ForEach(model.installed) { version in
                    Button(model.isDefault(version) ? "\(version.raw) ✓" : version.raw) {
                        Task { await model.setDefault(version.raw) }
                    }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(defaultVersion?.raw ?? "—")
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundStyle(defaultVersion == nil ? Color.secondary : Color.primary)
                    if !model.installed.isEmpty {
                        Image(systemName: "chevron.down")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Switch the default version")

            if let meta = defaultVersion.flatMap(model.distMeta(for:)) {
                HStack(spacing: 8) {
                    if let codename = meta.ltsCodename { VersionBadge(text: "LTS \(codename)", color: .orange) }
                    if let npm = meta.npm { Text("npm \(npm)") }
                    if let date = meta.releaseDate { Text(date.formatted(.dateTime.month(.abbreviated).year())) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }

            installedLine
        }
    }

    private var installedLine: some View {
        let count = model.installed.count
        let bytes = model.extras.values.reduce(Int64(0)) { $0 + $1.sizeBytes }
        return HStack(spacing: 6) {
            Text("\(count) installed")
            if count > 0, bytes > 0 {
                Text("·")
                Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
            }
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    // MARK: - latest

    private var latestEntry: RemoteVersion? {
        model.remote.first(where: \.isLatestCurrent)
            ?? model.remote.max(by: { $0.version < $1.version })
    }

    private var latestBlock: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("Latest available")
                .font(.caption).foregroundStyle(.secondary)
            if let latest = latestEntry {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(latest.version.raw)
                        .font(.system(size: 26, weight: .semibold, design: .monospaced))
                    if let codename = model.ltsCodename(for: latest) {
                        VersionBadge(text: "LTS \(codename)", color: .orange)
                    }
                }
                HStack(spacing: 8) {
                    if let meta = model.distMeta(for: latest.version) {
                        if let npm = meta.npm { Text("npm \(npm)") }
                        if let date = meta.releaseDate { Text(date.formatted(.relative(presentation: .named))) }
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                if let gap = newerThanDefaultCount, gap > 0 {
                    VersionBadge(text: "\(gap) newer than default", color: .green)
                }
            } else if model.remoteBusy != .idle {
                ProgressView().controlSize(.small)
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
    }

    private var newerThanDefaultCount: Int? {
        guard let defaultVersion else { return nil }
        return model.remote.filter { $0.version > defaultVersion }.count
    }
}
