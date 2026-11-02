import Foundation

public struct ShellResult: Sendable {
    public let status: Int32
    public let output: String
    public var isSuccess: Bool { status == 0 }

    public init(status: Int32, output: String) { self.status = status; self.output = output }
}

/// nvm is a shell function, not a binary (capabilities doc §1): every call goes
/// through a fresh zsh that sources nvm.sh with `--no-use` so nothing is
/// auto-switched just by asking a question. `TERM=dumb` plus explicit
/// `--no-colors` arguments keep output parseable.
public struct NVMShellRunner: Sendable {
    public let layout: NVMLayout

    public init(layout: NVMLayout) { self.layout = layout }

    public func run(_ nvmArguments: [String]) async -> ShellResult {
        await withCheckedContinuation { (continuation: CheckedContinuation<ShellResult, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Self.execute(script: self.makeScript(nvmArguments), environment: self.environment())
                continuation.resume(returning: result)
            }
        }
    }

    public func runStreaming(_ nvmArguments: [String],
                             onChunk: @escaping @Sendable (String) -> Void) async -> ShellResult {
        await withCheckedContinuation { (continuation: CheckedContinuation<ShellResult, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Self.execute(script: self.makeScript(nvmArguments), environment: self.environment(),
                                          onChunk: onChunk)
                continuation.resume(returning: result)
            }
        }
    }

    private func makeScript(_ nvmArguments: [String]) -> String {
        let quoted = nvmArguments.map { arg in
            "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        let dir = layout.nvmDir.path.replacingOccurrences(of: "'", with: "'\\''")
        return """
        export NVM_DIR='\(dir)'
        [ -s "$NVM_DIR/nvm.sh" ] || exit 125
        . "$NVM_DIR/nvm.sh" --no-use >/dev/null 2>&1 || exit 125
        nvm \(quoted.joined(separator: " "))
        """
    }

    private func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["NVM_DIR"] = layout.nvmDir.path
        env["TERM"] = "dumb"
        return env
    }

    private static func execute(script: String, environment: [String: String],
                                onChunk: (@Sendable (String) -> Void)? = nil) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", script]
        process.environment = environment
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        let collector = OutputCollector()
        if onChunk != nil {
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                collector.append(data)
                onChunk?(String(decoding: data, as: UTF8.self))
            }
        }

        do {
            try process.run()
        } catch {
            return ShellResult(status: 127, output: "could not launch zsh: \(error.localizedDescription)")
        }

        // Drain before waiting when there is no streaming handler: ls-remote output
        // can exceed the pipe buffer, and waiting first would deadlock.
        if onChunk == nil {
            collector.append(pipe.fileHandleForReading.readDataToEndOfFile())
        }
        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
        collector.append(pipe.fileHandleForReading.readDataToEndOfFile())

        return ShellResult(status: process.terminationStatus, output: collector.text)
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock(); data.append(chunk); lock.unlock()
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}
