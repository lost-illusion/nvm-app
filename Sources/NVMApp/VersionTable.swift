import Foundation
import NVMCore
import SwiftUI

private enum SortKey: Equatable { case version, released }

struct VersionTable: View {
    let model: NVMModel
    let filter: VersionFilter
    let style: TableStyle
    let onInstallWithOptions: (String) -> Void
    let onUninstall: (String) -> Void

    @State private var expandedMajors: Set<Int> = []
    @State private var expandedMinors: Set<String> = []
    @State private var sortKey: SortKey = .version
    @State private var sortDescending = true
    @State private var pendingRosetta: InstallTarget?

    // Shared column widths so header, major/minor labels and patch rows align.
    // Sized so header + one dense badge row fit a ~800 pt window; wider Status
    // overflow would clip the actions column off-screen.
    private static let colVersion: CGFloat = 110
    private static let colVersions: CGFloat = 90
    private static let colReleased: CGFloat = 72
    private static let colAge: CGFloat = 78
    private static let colNpm: CGFloat = 78  // fits compact "10.2.4–11.20.0"
    private static let colDisk: CGFloat = 58
    private static let colInstalled: CGFloat = 90  // compact-only column
    private static let colActions: CGFloat = 68  // terminal + trash on installed rows

    var body: some View {
        List {
            headerRow.listRowSeparator(.hidden)
            switch style {
            case .full:
                ForEach(sortedFullRows) { entry in
                    versionRow(entry, indent: 0)
                }
            case .compact:
                ForEach(tree.majors) { major in
                    Button { toggleMajor(major.major) } label: { majorLabel(major) }
                        .buttonStyle(.plain)
                    if expandedMajors.contains(major.major) {
                        ForEach(major.minors) { minor in
                            Button { toggleMinor(minor.id) } label: { minorLabel(minor) }
                                .buttonStyle(.plain)
                            if expandedMinors.contains(minor.id) {
                                ForEach(minor.patches) { entry in
                                    versionRow(entry, indent: 34)
                                }
                            }
                        }
                    }
                }
            }
        }
        .overlay { emptyOverlay }
        .confirmationDialog(
            pendingRosetta.map {
                "\($0.raw) is below v16 — no arm64 macOS binaries. nvm will run it under "
                + "Rosetta 2, or build from source (slow, needs Xcode tools)."
            } ?? "",
            isPresented: .init(
                get: { pendingRosetta != nil },
                set: { if !$0 { pendingRosetta = nil } }),
            titleVisibility: .visible)
        {
            Button("Install anyway") {
                if let target = pendingRosetta { Task { await model.install(raw: target.raw) } }
                pendingRosetta = nil
            }
            Button("Cancel", role: .cancel) { pendingRosetta = nil }
        }
    }

    // MARK: - data

    private var sourceRows: [RemoteVersion] {
        switch filter {
        case .all:
            return model.remote
        case .lts:
            // With dist metadata every LTS patch carries its own codename; without
            // it, fall back to whole majors (ls-remote marks only latest patches).
            if model.distEntries.isEmpty {
                let ltsMajors = Set(model.remote.compactMap { $0.ltsCodename != nil ? $0.version.major : nil })
                return model.remote.filter { ltsMajors.contains($0.version.major) }
            }
            return model.remote.filter { model.ltsCodename(for: $0) != nil }
        case .installed:
            if model.remote.isEmpty {
                // Before the catalog loads, disk state alone answers this filter.
                return model.installed.map {
                    RemoteVersion(version: $0, isLatestCurrent: false, ltsCodename: nil, aliasedBy: [])
                }
            }
            return model.remote.filter { model.isInstalled($0.version) }
        }
    }

    private var sortedFullRows: [RemoteVersion] {
        switch sortKey {
        case .version:
            let rows = sourceRows.sorted { $0.version > $1.version }
            return sortDescending ? rows : rows.reversed()
        case .released:
            return sourceRows.sorted { a, b in
                let dateA = model.distMeta(for: a.version)?.releaseDate ?? .distantPast
                let dateB = model.distMeta(for: b.version)?.releaseDate ?? .distantPast
                if dateA == dateB { return a.version > b.version }
                return sortDescending ? dateA > dateB : dateA < dateB
            }
        }
    }

    private var tree: VersionTree { VersionTree(rows: sourceRows) }

    // MARK: - header

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: 8) {
            switch style {
            case .full:
                sortButton("Version", .version).frame(width: Self.colVersion, alignment: .leading)
                Text("Status").frame(maxWidth: .infinity, alignment: .leading)
                sortButton("Released", .released).frame(width: Self.colReleased, alignment: .trailing)
                Text("Age").frame(width: Self.colAge, alignment: .trailing)
                Text("npm").frame(width: Self.colNpm, alignment: .trailing)
                Text("On disk").frame(width: Self.colDisk, alignment: .trailing)
                Spacer().frame(width: Self.colActions)
            case .compact:
                Text("Major").frame(width: Self.colVersion, alignment: .leading)
                Text("LTS").frame(maxWidth: .infinity, alignment: .leading)
                Text("Versions").frame(width: Self.colVersions, alignment: .trailing)
                Text("Last release").frame(width: Self.colReleased, alignment: .trailing)
                Text("npm range").frame(width: Self.colNpm, alignment: .trailing)
                Text("Installed").frame(width: Self.colInstalled, alignment: .trailing)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func sortButton(_ title: String, _ key: SortKey) -> some View {
        Button {
            if sortKey == key { sortDescending.toggle() }
            else { sortKey = key; sortDescending = true }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                if sortKey == key {
                    Image(systemName: sortDescending ? "chevron.down" : "chevron.up")
                        .font(.caption2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - patch rows (shared by full + expanded compact)

    private func versionRow(_ entry: RemoteVersion, indent: CGFloat) -> some View {
        let meta = model.distMeta(for: entry.version)
        let extras = model.extras(for: entry.version)
        return HStack(spacing: 8) {
            Text(entry.version.raw)
                .font(.body.monospaced())
                .padding(.leading, indent)
                .frame(width: Self.colVersion, alignment: .leading)
            HStack(spacing: 6) {
                if entry.isLatestCurrent { VersionBadge(text: "latest", color: .green) }
                if let codename = model.ltsCodename(for: entry) {
                    VersionBadge(text: "LTS \(codename)", color: .orange)
                }
                if meta?.security == true { VersionBadge(text: "security", color: .red) }
                if model.needsRosetta(entry.version) { VersionBadge(text: "rosetta", color: .orange) }
                ForEach(entry.aliasedBy, id: \.self) { name in
                    VersionBadge(text: name, color: .purple)
                }
                if model.isInstalled(entry.version) {
                    VersionBadge(text: "installed", color: .blue)
                    if model.isDefault(entry.version) { VersionBadge(text: "default") }
                    // Only show a pkg badge when there actually are globals.
                    if let extras, extras.globals > 0 {
                        VersionBadge(text: "\(extras.globals) pkg", color: .secondary)
                    }
                }
                if model.isNewSinceLaunch(entry.version) { VersionBadge(text: "new", color: .green) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            tableCell(meta?.releaseDate.map { $0.formatted(.dateTime.month(.abbreviated).year()) } ?? "—",
                      width: Self.colReleased)
            tableCell(meta?.releaseDate.map { $0.formatted(.relative(presentation: .named)) } ?? "—",
                      width: Self.colAge)
            tableCell(meta?.npm ?? "—", width: Self.colNpm)
            tableCell(extras.map { ByteCountFormatter.string(fromByteCount: $0.sizeBytes, countStyle: .file) } ?? "",
                      width: Self.colDisk)
            if model.isInstalled(entry.version) {
                HStack(spacing: 6) {
                    Button { model.runInTerminal(entry.version.raw) } label: {
                        Image(systemName: "terminal")
                    }
                    .buttonStyle(.borderless)
                    .help("Open Terminal with \(entry.version.raw) — new tab if Terminal "
                          + "is already open, new window otherwise")
                    Button { onUninstall(entry.version.raw) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .tint(.red)
                    .help("Uninstall \(entry.version.raw)")
                }
                .frame(width: Self.colActions)
            } else {
                Button {
                    if model.needsRosetta(entry.version) {
                        pendingRosetta = InstallTarget(raw: entry.version.raw)
                    } else {
                        Task { await model.install(raw: entry.version.raw) }
                    }
                } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .buttonStyle(.borderless)
                .disabled(model.installBusy != .idle)
                .help("Install \(entry.version.raw)")
                .frame(width: Self.colActions)
            }
        }
        .contextMenu {
            Button("Install with options…") { onInstallWithOptions(entry.version.raw) }
            if model.projectFolders.count == 1 {
                let folder = model.projectFolders[0]
                Button("Pin \(entry.version.raw) in \(folder.lastPathComponent)/.nvmrc") {
                    Task { await model.writePin(entry.version.raw, for: folder) }
                }
            } else if !model.projectFolders.isEmpty {
                Menu("Pin \(entry.version.raw) in .nvmrc") {
                    ForEach(model.projectFolders, id: \.path) { folder in
                        Button(folder.lastPathComponent) {
                            Task { await model.writePin(entry.version.raw, for: folder) }
                        }
                    }
                }
            }
        }
    }

    private func tableCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .trailing)
    }

    // MARK: - compact labels (column-aligned with header)

    private func majorLabel(_ major: VersionTree.Major) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: expandedMajors.contains(major.major) ? "chevron.down" : "chevron.right")
                    .font(.caption).foregroundStyle(.secondary)
                Text("v\(major.major)")
                    .font(.body.monospaced().weight(.semibold))
            }
            .frame(width: Self.colVersion, alignment: .leading)
            HStack(spacing: 6) {
                if let codename = majorLTS(major) { VersionBadge(text: "LTS \(codename)", color: .orange) }
                if model.isAppleSilicon, major.major < AppleSiliconGuard.firstArm64NodeMajor {
                    VersionBadge(text: "rosetta", color: .orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            tableCell("\(major.totalCount) versions", width: Self.colVersions)
            tableCell(lastRelease(in: major).map { $0.formatted(.dateTime.month(.abbreviated).year()) } ?? "—",
                      width: Self.colReleased)
            tableCell(npmRange(in: major) ?? "—", width: Self.colNpm)
            HStack(spacing: 6) {
                let installed = installedCount(in: major)
                if installed > 0 { VersionBadge(text: "\(installed) installed", color: .blue) }
            }
            .frame(width: Self.colInstalled, alignment: .trailing)
        }
    }

    private func minorLabel(_ minor: VersionTree.Minor) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: expandedMinors.contains(minor.id) ? "chevron.down" : "chevron.right")
                    .font(.caption).foregroundStyle(.secondary)
                Text("v\(minor.major).\(minor.minor)")
                    .font(.body.monospaced())
                    .padding(.leading, 18)
            }
            .frame(width: Self.colVersion, alignment: .leading)
            Spacer()
            tableCell("\(minor.patches.count) patches", width: Self.colVersions)
            tableCell(lastRelease(in: minor).map { $0.formatted(.dateTime.month(.abbreviated).year()) } ?? "—",
                      width: Self.colReleased)
            tableCell("", width: Self.colNpm)
            tableCell("", width: Self.colInstalled)
        }
    }

    /// Newest release date in a line — patches inside majors/minors are sorted
    /// newest-first, so the first entry that carries metadata answers this.
    private func lastRelease(in major: VersionTree.Major) -> Date? {
        for patch in major.minors.flatMap(\.patches) {
            if let date = model.distMeta(for: patch.version)?.releaseDate { return date }
        }
        return nil
    }

    private func lastRelease(in minor: VersionTree.Minor) -> Date? {
        for patch in minor.patches {
            if let date = model.distMeta(for: patch.version)?.releaseDate { return date }
        }
        return nil
    }

    /// Lowest → highest bundled npm across the line, e.g. "10.2.4–11.20.0".
    private func npmRange(in major: VersionTree.Major) -> String? {
        let values = major.minors.flatMap(\.patches).compactMap { npmPair(for: $0) }
        return npmRange(values)
    }

    private func npmRange(_ values: [(version: NodeVersion, raw: String)]) -> String? {
        guard let low = values.min(by: { $0.version < $1.version }),
              let high = values.max(by: { $0.version < $1.version }) else { return nil }
        return low.raw == high.raw ? low.raw : "\(low.raw)–\(high.raw)"
    }

    private func npmPair(for entry: RemoteVersion) -> (version: NodeVersion, raw: String)? {
        guard let raw = model.distMeta(for: entry.version)?.npm,
              let version = NodeVersion.parse(raw) else { return nil }
        return (version, raw)
    }

    private func majorLTS(_ major: VersionTree.Major) -> String? {
        for patch in major.minors.flatMap(\.patches) {
            if let codename = model.ltsCodename(for: patch) { return codename }
        }
        return nil
    }

    private func installedCount(in major: VersionTree.Major) -> Int {
        major.minors.flatMap(\.patches).filter { model.isInstalled($0.version) }.count
    }

    private func toggleMajor(_ major: Int) {
        if expandedMajors.contains(major) { expandedMajors.remove(major) }
        else { expandedMajors.insert(major) }
    }

    private func toggleMinor(_ id: String) {
        if expandedMinors.contains(id) { expandedMinors.remove(id) }
        else { expandedMinors.insert(id) }
    }

    // MARK: - empty states

    @ViewBuilder
    private var emptyOverlay: some View {
        if sourceRows.isEmpty {
            if filter == .installed {
                Text("No versions installed yet.")
                    .foregroundStyle(.secondary)
            } else {
                switch model.remoteBusy {
                case .busy(let label): ProgressView(label)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                case .idle:
                    Button("Fetch versions") {
                        Task {
                            await withTaskGroup(of: Void.self) { group in
                                group.addTask { await model.loadRemote() }
                                group.addTask { await model.refreshDist() }
                            }
                        }
                    }
                }
            }
        }
    }
}
