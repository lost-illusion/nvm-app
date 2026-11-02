import Foundation

/// The zsh `chpwd` auto-use hook from nvm's README, written by the app as a
/// marker-delimited block so install/remove is exact and never rewrites the
/// user's own lines.
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
        let begin = zshrc.range(of: beginMarker)
        let end = zshrc.range(of: endMarker)
        var result = zshrc
        // install() prepends one newline before the begin marker; consume it (and
        // one newline after the end marker) so removal restores the file exactly.
        func consumingEdges(_ lower: String.Index, _ upper: String.Index) -> (String.Index, String.Index) {
            var lo = lower
            var hi = upper
            if lo != result.startIndex, result[result.index(before: lo)] == "\n" { lo = result.index(before: lo) }
            if hi != result.endIndex, result[hi] == "\n" { hi = result.index(after: hi) }
            return (lo, hi)
        }
        if let begin, let end, begin.upperBound <= end.lowerBound {
            let (lo, hi) = consumingEdges(begin.lowerBound, end.upperBound)
            result.removeSubrange(lo..<hi)
            return result
        }
        if let begin {
            // Orphaned block: we only ever append at the end, so delete to EOF.
            let (lo, _) = consumingEdges(begin.lowerBound, result.endIndex)
            result.removeSubrange(lo..<result.endIndex)
            return result
        }
        if end != nil {
            // Orphan end marker: drop just that line, keep everything else.
            result = result.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
                .filter { $0.trimmingCharacters(in: .whitespaces) != endMarker }
                .joined(separator: "\n")
            return result
        }
        return result
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
