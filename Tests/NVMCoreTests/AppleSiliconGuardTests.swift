import Foundation
import Testing

@testable import NVMCore

@Suite struct AppleSiliconGuardTests {
    @Test func rosettaNeededOnlyBelowV16OnAppleSilicon() {
        #expect(AppleSiliconGuard.needsRosetta(major: 15, appleSilicon: true))
        #expect(AppleSiliconGuard.needsRosetta(major: 8, appleSilicon: true))
        #expect(!AppleSiliconGuard.needsRosetta(major: 16, appleSilicon: true))
        #expect(!AppleSiliconGuard.needsRosetta(major: 26, appleSilicon: true))
        // Intel Mac: x64 binaries are native, nothing to flag.
        #expect(!AppleSiliconGuard.needsRosetta(major: 10, appleSilicon: false))
    }

    @Test func machineAnswerDoesNotCrash() {
        // Can't assert a value across machines; just prove the sysctl call is wired.
        _ = AppleSiliconGuard.isAppleSilicon()
    }
}
