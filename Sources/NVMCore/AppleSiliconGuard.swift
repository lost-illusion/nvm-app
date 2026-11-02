import Darwin
import Foundation

/// Node shipped official arm64 macOS binaries starting at v16; below that,
/// an Apple Silicon Mac gets an x64 binary (needs Rosetta 2) or a source
/// build. Node ≥ 16 is unaffected.
public enum AppleSiliconGuard {
    public static let firstArm64NodeMajor = 16

    /// `hw.optional.arm64` answers "is this an Apple Silicon Mac" even when
    /// the process itself runs translated — `uname -m` would lie under Rosetta.
    public static func isAppleSilicon() -> Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let ok = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return ok == 0 && value == 1
    }

    public static func needsRosetta(major: Int, appleSilicon: Bool) -> Bool {
        appleSilicon && major < firstArm64NodeMajor
    }
}
