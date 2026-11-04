import Foundation

/// The zsh `chpwd` auto-use hook from nvm's README, written by the app as a
/// marker-delimited block so install/remove is exact and never rewrites the
/// user's own lines. Removal never reads past the block it recognizes, even
/// when a marker has been lost.
public enum AutoUseHook {
    public static let beginMarker = "# >>> nvm-app auto-use >>>"
    public static let endMarker = "# <<< nvm-app auto-use <<<"

    public enum Status: Sendable, Equatable {
        case absent       // nothing there — safe to install
        case installed    // our intact block
        case corrupted    // one marker present, its pair missing
        case foreign      // user's own chpwd/nvm_find_nvmrc hook — hands off
    }

    public static func status(in zshrc: String) -> Status {
        let hasBegin = zshrc.contains(beginMarker)
        let hasEnd = zshrc.contains(endMarker)
        if hasBegin && hasEnd { return .installed }
        if hasBegin || hasEnd { return .corrupted }
        if zshrc.contains("nvm_find_nvmrc")
            || (zshrc.contains("add-zsh-hook") && zshrc.contains("chpwd")) {
            return .foreign
        }
        return .absent
    }

    public static func install(into zshrc: String, autoInstall: Bool) -> String {
        guard status(in: zshrc) == .absent else { return zshrc }  // idempotent
        return zshrc + "\n" + block(autoInstall: autoInstall)
    }

    public static func remove(from zshrc: String) -> String {
        // 1. Exact inverse of install(): delete the known block verbatim
        //    (either autoInstall variant). This cannot touch user lines.
        var result = zshrc
        for autoInstall in [true, false] {
            let exact = "\n" + block(autoInstall: autoInstall)
            while let r = result.range(of: exact) { result.removeSubrange(r) }
        }
        if AutoUseHook.status(in: result) != .corrupted { return result }

        // 2. Corrupted: a marker survived but its pair is gone. Work line-wise
        //    and never read past what we recognize as our block — losing a
        //    marker must not truncate the user's own lines (issue: .zshrc got cut).
        let lines = result.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let trimmed = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        let beginIdx = trimmed.firstIndex(of: beginMarker)
        let endIdx = trimmed.firstIndex(of: endMarker)

        if let beginIdx, let endIdx, beginIdx < endIdx {
            // Both markers, body edited between them: the markers still bound
            // what is ours, so drop begin..end inclusive (and the blank line
            // install prepended). Deleting the end marker line also drops its
            // newline; anything the user wrote after stays untouched.
            var lo = beginIdx
            if lo > 0, lines[lo - 1].isEmpty { lo -= 1 }
            var l = lines
            l.removeSubrange(lo..<endIdx + 1)
            return l.joined(separator: "\n")
        }
        if let beginIdx {
            // Orphan begin marker (end marker lost). Remove only a verbatim
            // match of the known body right after it; never reach EOF blindly.
            var matchedBody: [String]?
            for autoInstall in [true, false] {
                let body = Self.blockLines(autoInstall: autoInstall)
                    .dropFirst()                    // begin marker
                    .dropLast(2)                    // end marker + trailing newline
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                guard beginIdx + body.count < lines.count else { continue }
                if Array(trimmed[(beginIdx + 1)...(beginIdx + body.count)]) == body {
                    matchedBody = body
                    break
                }
            }
            var l = lines
            if let body = matchedBody {
                // Consume the blank line install prepended; deleting the last
                // body line also drops its newline — user lines after resume right there.
                var lo = beginIdx
                if lo > 0, l[lo - 1].isEmpty { lo -= 1 }
                l.removeSubrange(lo..<beginIdx + 1 + body.count)
            } else {
                // Body edited past recognition: drop only the orphan marker
                // line and hand the rest to the user (status becomes foreign).
                l.remove(at: beginIdx)
            }
            return l.joined(separator: "\n")
        }
        if endIdx != nil {
            // Orphan end marker: drop just that line, keep everything else.
            return lines.enumerated().filter { $0.offset != endIdx }.map(\.element).joined(separator: "\n")
        }
        return result
    }

    private static func blockLines(autoInstall: Bool) -> [String] {
        block(autoInstall: autoInstall)
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)
    }

    public static func block(autoInstall: Bool) -> String {
        let missingLine = autoInstall
            ? "      nvm install"
            : "      echo \"nvm-app: pin $(cat \"${nvmrc_path}\") is not installed — run: nvm install\""
        let lines = [
            beginMarker,
            "autoload -U add-zsh-hook",
            "load-nvmrc() {",
            "  local node_version=\"$(nvm version)\"",
            "  local nvmrc_path=\"$(nvm_find_nvmrc)\"",
            "",
            "  if [ -n \"$nvmrc_path\" ]; then",
            "    local nvmrc_node_version=\"$(nvm version \"$(cat \"${nvmrc_path}\")\")\"",
            "",
            "    if [ \"$nvmrc_node_version\" = \"N/A\" ]; then",
            missingLine,
            "    elif [ \"$nvmrc_node_version\" != \"$node_version\" ]; then",
            "      nvm use",
            "    fi",
            "  elif [ \"$node_version\" != \"$(nvm version default)\" ]; then",
            "    echo \"Reverting to nvm default version\"",
            "    nvm use default",
            "  fi",
            "}",
            "add-zsh-hook chpwd load-nvmrc",
            "load-nvmrc",
            endMarker,
            "",
        ]
        return lines.joined(separator: "\n")
    }
}
