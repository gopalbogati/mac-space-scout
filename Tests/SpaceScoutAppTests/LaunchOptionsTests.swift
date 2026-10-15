import Testing
@testable import SpaceScout

struct LaunchOptionsTests {
    @Test func snapshotForcesSyntheticModeWithoutDemoFlag() throws {
        let options = try LaunchOptions(["--demo-snapshot", "/private/tmp/sample.png"])
        #expect(options.demo)
        #expect(options.snapshotPath == "/private/tmp/sample.png")
        #expect(!options.scanJSON)
    }
    @Test func missingOrInvalidSnapshotPathFailsBeforeAnyScan() {
        for args in [["--demo-snapshot"], ["--demo-snapshot", "--scan-json"], ["--demo-snapshot", "relative.png"], ["--demo-snapshot", "/private/tmp/example.txt"]] {
            #expect(throws: (any Error).self) { try LaunchOptions(args) }
        }
    }
    @Test func mixedSnapshotAndRealScanFlagsAreRejected() {
        #expect(throws: (any Error).self) { try LaunchOptions(["--demo-snapshot", "/private/tmp/sample.png", "--scan-json"]) }
    }
}
