import Foundation
import Testing

@testable import NVMCore

@Suite struct AutoUseHookTests {
    @Test func absentWhenFileUnrelated() {
        let text = "export EDITOR=vim\nalias ll='ls -la'\n"
        #expect(AutoUseHook.status(in: text) == .absent)
    }

    @Test func installAddsBlockAndIsIdempotent() {
        let original = "# user lines\nexport NVM_DIR=\"$HOME/.nvm\"\n"
        let once = AutoUseHook.install(into: original, autoInstall: true)
        #expect(AutoUseHook.status(in: once) == .installed)
        #expect(once.hasPrefix(original))
        let twice = AutoUseHook.install(into: once, autoInstall: true)
        #expect(twice == once)  // never a second copy
    }

    @Test func autoInstallToggleChangesTheMissingPinLine() {
        let install = AutoUseHook.block(autoInstall: true)
        let notify = AutoUseHook.block(autoInstall: false)
        #expect(install.contains("nvm install"))
        #expect(!install.contains("is not installed — run"))
        #expect(notify.contains("is not installed — run"))
        #expect(!notify.contains("\n      nvm install\n"))
    }

    @Test func removeIsExactAndKeepsUserLines() {
        let original = "# before\nexport NVM_DIR=\"$HOME/.nvm\"\n"
        let installed = AutoUseHook.install(into: original, autoInstall: true) + "export PATHextra\n"
        let removed = AutoUseHook.remove(from: installed)
        #expect(removed == original + "export PATHextra\n")
        #expect(AutoUseHook.status(in: removed) == .absent)
        // Removing again changes nothing.
        #expect(AutoUseHook.remove(from: removed) == removed)
    }

    @Test func foreignHookIsDetected() {
        #expect(AutoUseHook.status(in: "load-nvmrc() { nvm_find_nvmrc }\n") == .foreign)
        #expect(AutoUseHook.status(in: "autoload -U add-zsh-hook\nadd-zsh-hook chpwd my_prompt\n") == .foreign)
    }

    @Test func corruptedWhenOneMarkerIsMissing() {
        let installed = AutoUseHook.install(into: "# user\n", autoInstall: true)
        // Realistic loss: the end marker line is deleted, whole line gone.
        let halfBroken = installed.replacingOccurrences(of: AutoUseHook.endMarker + "\n", with: "")
        #expect(AutoUseHook.status(in: halfBroken) == .corrupted)
        // Remove on an orphaned begin marker drops the recognized body but keeps
        // the user's preceding lines.
        let cleaned = AutoUseHook.remove(from: halfBroken)
        #expect(cleaned == "# user\n")
    }

    @Test func lostEndMarkerNeverTruncatesUserLines() {
        // Regression: hook installed, user later appends their own lines AFTER
        // the block, then the end marker line gets lost. Removal used to cut to
        // EOF and ate the user's lines.
        let installed = AutoUseHook.install(into: "# before\n", autoInstall: true)
        let broken = (installed + "export PATHextra\nalias ll='ls -la'\n")
            .replacingOccurrences(of: AutoUseHook.endMarker + "\n", with: "")
        #expect(AutoUseHook.status(in: broken) == .corrupted)
        let cleaned = AutoUseHook.remove(from: broken)
        #expect(cleaned == "# before\nexport PATHextra\nalias ll='ls -la'\n")
        #expect(AutoUseHook.status(in: cleaned) == .absent)
    }

    @Test func editedCorruptedBlockOnlyLosesItsMarkerLine() {
        // Body edited past recognition: removal must not guess a range. It drops
        // the orphan marker line and leaves the rest for the user (status now foreign).
        let installed = AutoUseHook.install(into: "# before\n", autoInstall: true)
        let edited = installed
            .replacingOccurrences(of: AutoUseHook.endMarker + "\n", with: "")
            .replacingOccurrences(of: "      nvm use", with: "      nvm use --lts")
        #expect(AutoUseHook.status(in: edited) == .corrupted)
        let cleaned = AutoUseHook.remove(from: edited)
        #expect(!cleaned.contains(AutoUseHook.beginMarker))
        #expect(cleaned.contains("nvm use --lts"))  // untouched — no silent truncation
    }

    @Test func statusPrefersOurMarkersOverForeignText() {
        // Our block itself contains nvm_find_nvmrc/add-zsh-hook — installed, not foreign.
        let installed = AutoUseHook.install(into: "", autoInstall: true)
        #expect(AutoUseHook.status(in: installed) == .installed)
    }
}
