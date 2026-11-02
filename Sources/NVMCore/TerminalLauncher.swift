import AppKit
import Foundation

/// Opens a Terminal window with the interactive shell switched to one nvm
/// version. The GUI cannot reach shells that already exist (capabilities doc
/// §13.3), so this drives Terminal.app through AppleScript: `do script` runs
/// inside the *interactive* shell, so `nvm use` actually sticks there.
public enum TerminalLauncher {
    /// Whitelist for the version spec — keeps `lts/*`, `22.20.0`, `default`
    /// and prunes anything that could break out of the quoted shell command.
    public static func sanitized(_ spec: String) -> String {
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-/+*:=")
        return String(spec.unicodeScalars.filter { allowed.contains($0) })
    }

    /// Escape for a POSIX double-quoted shell string.
    static let shellSpecial: Set<Character> = ["$", "`", "\"", "\\"]
    static func shellEscape(_ text: String) -> String {
        var out = ""
        for ch in text {
            if shellSpecial.contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    /// Escape for the inside of an AppleScript double-quoted string.
    static func appleScriptEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// `cd` is prepended when given — the new shell starts inside that folder.
    public static func appleScriptSource(spec: String, nvmDir: URL, cd: URL? = nil) -> String? {
        let safeSpec = sanitized(spec)
        guard !safeSpec.isEmpty else { return nil }
        var steps = "export NVM_DIR=\"\(shellEscape(nvmDir.path))\"; . \"$NVM_DIR/nvm.sh\""
        if let cd { steps += " && cd \"\(shellEscape(cd.path))\"" }
        steps += " && nvm use '\(safeSpec)'"
        // Terminal already open → new tab in its front window; closed → new window.
        return """
        tell application "Terminal"
            activate
            set nvmCommand to "\(appleScriptEscape(steps))"
            if (count of windows) = 0 then
                do script nvmCommand
            else
                do script nvmCommand in front window
            end if
        end tell
        """
    }

    /// Returns nil on success, otherwise the error to show the user.
    @discardableResult
    public static func openTerminal(using spec: String, nvmDir: URL, cd: URL? = nil) -> String? {
        guard let source = appleScriptSource(spec: spec, nvmDir: nvmDir, cd: cd) else {
            return "Nothing left of “\(spec)” after sanitizing — refusing to build a command"
        }
        guard let script = NSAppleScript(source: source) else {
            return "Could not build the Terminal automation script"
        }
        var info: NSDictionary?
        script.executeAndReturnError(&info)
        if let info {
            let message = info[NSAppleScript.errorMessage] as? String
            return message ?? "Terminal automation failed (is Automation permission granted?)"
        }
        return nil
    }
}
