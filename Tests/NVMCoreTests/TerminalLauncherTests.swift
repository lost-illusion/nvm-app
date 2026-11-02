import Foundation
import Testing

@testable import NVMCore

@Suite struct TerminalLauncherTests {
    @Test func sanitizedKeepsRealSpecsAndDropsShellMetacharacters() {
        #expect(TerminalLauncher.sanitized("lts/*") == "lts/*")
        #expect(TerminalLauncher.sanitized("22.20.0") == "22.20.0")
        #expect(TerminalLauncher.sanitized("default") == "default")
        #expect(TerminalLauncher.sanitized("v24.22.2") == "v24.22.2")
        #expect(TerminalLauncher.sanitized("22\"; rm -rf ~; \"") == "22rm-rf")
        #expect(TerminalLauncher.sanitized("$(whoami)") == "whoami")
        #expect(TerminalLauncher.sanitized("").isEmpty)
    }

    @Test func emptySpecRefusesToBuildAScript() {
        #expect(TerminalLauncher.appleScriptSource(spec: "\"\"",
                                                   nvmDir: URL(fileURLWithPath: "/x/.nvm")) == nil)
        let warning = TerminalLauncher.openTerminal(using: "\"\"",
                                                    nvmDir: URL(fileURLWithPath: "/x/.nvm"))
        #expect(warning != nil)  // returns an error without touching Terminal
    }

    @Test func scriptQuotesNvmDirAndEscapesForAppleScript() {
        let source = TerminalLauncher.appleScriptSource(
            spec: "lts/*",
            nvmDir: URL(fileURLWithPath: "/Users/ill usion/.nvm"))
        #expect(source != nil)
        let text = source!
        #expect(text.contains("tell application \"Terminal\""))
        // NVM_DIR path is double-quoted for the shell and re-escaped for AppleScript.
        #expect(text.contains("set nvmCommand to \"export NVM_DIR=\\\"/Users/ill usion/.nvm\\\""))
        #expect(text.contains("nvm use 'lts/*'"))  // single quotes stop zsh globbing
        // Tab when Terminal is already open, window when it is not.
        #expect(text.contains("if (count of windows) = 0 then"))
        #expect(text.contains("do script nvmCommand in front window"))
    }

    @Test func folderVariantCdFirst() {
        let text = TerminalLauncher.appleScriptSource(
            spec: "22.20.0",
            nvmDir: URL(fileURLWithPath: "/x/.nvm"),
            cd: URL(fileURLWithPath: "/tmp/pin-demo/api"))!
        #expect(text.contains("cd \\\"/tmp/pin-demo/api\\\" && nvm use '22.20.0'"))
    }

    @Test func shellEscapeCoversCommandSubstitutionAndBackticks() {
        #expect(TerminalLauncher.shellEscape("a$b`c\"d\\e") == #"a\$b\`c\"d\\e"#)
    }
}
