import Testing
import Foundation
import Darwin
@testable import SpaceScoutCore

@Suite(.serialized)
final class StorageEngineTests {
    var home: URL!
    let fm = FileManager.default
    init() throws {
        home = URL(fileURLWithPath: "/private/tmp/SpaceScoutTests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
    }
    deinit { if let home { try? fm.removeItem(at: home) } }
    @discardableResult func file(_ path: String, bytes: Int = 8192, old: Bool = true) throws -> URL {
        let url = home.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 97, count: bytes).write(to: url)
        if old {
            var aging = url
            while aging.path != home.path {
                try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -40 * 86400)], ofItemAtPath: aging.path)
                aging.deleteLastPathComponent()
            }
        }
        return url
    }
    func candidate(_ url: URL, limits: ScanLimits = .init(), running: Set<String> = []) throws -> Candidate {
        try #require(Scanner(home: home, runningBundleIDs: running, limits: limits).scan().candidates.first { $0.url == url })
    }
    func fakeTrash() throws -> (URL) throws -> Void {
        let trash = home.appendingPathComponent("FixtureTrash")
        try fm.createDirectory(at: trash, withIntermediateDirectories: true)
        return { [fm] url in try fm.moveItem(at: url, to: trash.appendingPathComponent(UUID().uuidString)) }
    }
    @Test func testCacheUsesPhysicalAllocationAndDeduplicatesHardlinks() throws {
        let first = try file("Library/Caches/pip/a")
        let second = home.appendingPathComponent("Library/Caches/pip/b")
        try fm.linkItem(at: first, to: second)
        var info = stat(); #expect(lstat(first.path, &info) == 0)
        let report = Scanner(home: home).scan()
        #expect(report.candidates.filter { $0.category == .cache }.reduce(Int64(0)) { $0 + $1.allocatedBytes } == Int64(info.st_blocks) * 512)
        #expect(report.candidates.count == 2)
    }
    @Test func testEligibleCacheMovesOnlyAfterConfirmation() throws {
        let original = try file("Library/Caches/pip/item")
        let item = try candidate(original)
        #expect(item.isEligible)
        let service = CleanupService(home: home, trashOperation: try fakeTrash())
        let refused = service.trash([item], confirmed: false)
        #expect(refused.first?.status == .refused)
        #expect(fm.fileExists(atPath: original.path))
        #expect(service.trash([item], confirmed: true).first?.status == .trashed)
        #expect(!(fm.fileExists(atPath: original.path)))
    }
    @Test func testSiblingPrefixCannotBypassPolicy() throws {
        let allowed = try file("Library/Caches/pip/item")
        let original = try candidate(allowed)
        let sibling = try file("Library/Caches/pip-escape/item")
        let forged = Candidate(id: "forged", url: sibling, title: "forged", category: .cache,
                               allocatedBytes: 1, modifiedAt: Date(), reason: "", eligibility: .eligible, snapshot: original.snapshot)
        #expect(throws: (any Error).self) { try ScanPolicy(home: self.home).validate(forged) }
        let results = CleanupService(home: home, trashOperation: try fakeTrash()).trash([forged], confirmed: true)
        #expect(results.first?.status == .refused)
        #expect(fm.fileExists(atPath: sibling.path))
    }
    @Test func testSymlinkRootIsNeverTraversed() throws {
        let target = try file("outside/item")
        let link = home.appendingPathComponent("Library/Caches/pip")
        try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: link, withDestinationURL: target.deletingLastPathComponent())
        let report = Scanner(home: home).scan()
        #expect(report.candidates.isEmpty)
        #expect(!(report.issues.isEmpty))
    }
    @Test func testSymlinkCandidateIsReviewOnlyAndPolicyRejectsIt() throws {
        let target = try file("outside/file")
        let link = home.appendingPathComponent("Library/Caches/pip/link")
        try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: link, withDestinationURL: target)
        let report = Scanner(home: home).scan()
        #expect(!(report.candidates.contains { $0.isEligible }))
        #expect(!(report.issues.isEmpty))
        let forged = Candidate(id: "link", url: link, title: "link", category: .cache, allocatedBytes: 0,
                               modifiedAt: Date(), reason: "", eligibility: .eligible)
        #expect(throws: (any Error).self) { try ScanPolicy(home: self.home).validate(forged) }
    }
    @Test func testReplacedInodePreventsCleanup() throws {
        let original = try file("Library/Caches/pip/item")
        let item = try candidate(original)
        try fm.moveItem(at: original, to: home.appendingPathComponent("old-inode"))
        try Data("replacement".utf8).write(to: original)
        let result = CleanupService(home: home, trashOperation: try fakeTrash()).trash([item], confirmed: true)
        #expect(result.first?.status == .refused)
        #expect(fm.fileExists(atPath: original.path))
    }
    @Test func testNestedFileChangePreventsDirectoryCleanup() throws {
        let nested = try file("Library/Caches/pip/tree/nested/file")
        let directory = home.appendingPathComponent("Library/Caches/pip/tree")
        let item = try candidate(directory)
        #expect(item.isEligible)
        try Data("changed contents".utf8).write(to: nested)
        let result = CleanupService(home: home, trashOperation: try fakeTrash()).trash([item], confirmed: true)
        #expect(result.first?.status == .refused)
        #expect(fm.fileExists(atPath: nested.path))
    }
    @Test func testCancellationNeverEnablesPartialDirectory() throws {
        for i in 0..<10 { try file("Library/Caches/pip/tree/file\(i)") }
        var stop = false
        let report = Scanner(home: home).scan(isCancelled: { stop }, progress: { if $0.visitedCount >= 4 { stop = true } })
        #expect(report.cancelled)
        #expect(!(report.candidates.contains { $0.isEligible && $0.url.lastPathComponent == "tree" }))
        #expect(!(report.issues.isEmpty))
    }
    @Test func testEntryLimitProducesIncompleteReviewOnlyDirectory() throws {
        for i in 0..<10 { try file("Library/Caches/pip/tree/file\(i)") }
        let report = Scanner(home: home, limits: ScanLimits(maximumEntries: 5)).scan()
        #expect(report.visitedCount <= 5)
        #expect(!(report.issues.isEmpty))
        #expect(!(report.candidates.contains { $0.isEligible }))
    }
    @Test func testPersonalFilesAndModelsAndUnknownCachesRemainReviewOnly() throws {
        let personal = try file("Downloads/video.mov")
        let model = try file(".cache/huggingface/hub/model/weights")
        let unknown = try file("Library/Caches/com.example.unknown/item")
        let report = Scanner(home: home, limits: ScanLimits(largeFileThreshold: 1)).scan()
        #expect(!(try #require(report.candidates.first { $0.url == personal }).isEligible))
        #expect(!(try #require(report.candidates.first { $0.url.path.contains("huggingface") }).isEligible))
        #expect(!(try #require(report.candidates.first { $0.url == unknown.deletingLastPathComponent() }).isEligible))
        #expect(fm.fileExists(atPath: model.path))
    }
    @Test func testOnlyOldDirectInstallerFilesEligible() throws {
        let old = try file("Downloads/old.dmg", old: true)
        let recent = try file("Downloads/recent.pkg", old: false)
        let nested = try file("Downloads/folder/nested.dmg", old: true)
        let report = Scanner(home: home, limits: ScanLimits(largeFileThreshold: 1)).scan()
        #expect(try #require(report.candidates.first { $0.url == old }).isEligible)
        #expect(!(try #require(report.candidates.first { $0.url == recent }).isEligible))
        #expect(!(report.candidates.contains { $0.url == nested && $0.isEligible }))
    }
    @Test func testRunningAppIsExcludedAtScanAndRecheckedAtCleanup() throws {
        let original = try file("Library/Developer/Xcode/DerivedData/project/output")
        let folder = original.deletingLastPathComponent()
        let item = try candidate(folder)
        let report = Scanner(home: home, runningBundleIDs: ["com.apple.dt.Xcode"]).scan()
        #expect(!(report.candidates.contains { $0.isEligible }))
        let result = CleanupService(home: home, runningBundleIDs: ["com.apple.dt.Xcode"], trashOperation: try fakeTrash()).trash([item], confirmed: true)
        #expect(result.first?.status == .refused)
        #expect(fm.fileExists(atPath: original.path))
    }
    @Test func testBatchReportsEachFailureAndRejectsDuplicates() throws {
        let goodURL = try file("Library/Caches/pip/good")
        let badURL = try file("Library/Caches/pip/fail")
        let good = try candidate(goodURL), bad = try candidate(badURL)
        let move = try fakeTrash()
        let service = CleanupService(home: home, trashOperation: { url in
            if url == badURL { throw CocoaError(.fileWriteNoPermission) }
            try move(url)
        })
        let result = service.trash([good, bad], confirmed: true)
        #expect(result.map(\.status) == [.trashed, .failed])
        #expect(!(fm.fileExists(atPath: goodURL.path)))
        #expect(fm.fileExists(atPath: badURL.path))
        let duplicateResults = service.trash([bad, bad], confirmed: true)
        #expect(duplicateResults.map(\.status) == [.refused, .refused])
    }
    @Test func testSymlinkAncestorIntroducedAfterScanIsRefused() throws {
        let original = try file("Library/Caches/pip/tree/file")
        let item = try candidate(original.deletingLastPathComponent())
        let cacheRoot = home.appendingPathComponent("Library/Caches/pip")
        let moved = home.appendingPathComponent("moved")
        try fm.moveItem(at: cacheRoot, to: moved)
        try fm.createSymbolicLink(at: cacheRoot, withDestinationURL: moved)
        #expect(CleanupService(home: home, trashOperation: try fakeTrash()).trash([item], confirmed: true).first?.status == .refused)
        #expect(fm.fileExists(atPath: original.path))
    }
    @Test func testArbitraryHomeCannotReclassifyProtectedDirectories() throws {
        let url = try file("Library/Caches/pip/item")
        let forgedHome = URL(fileURLWithPath: "/System")
        let item = Candidate(id: "protected", url: url, title: "protected", category: .cache,
                             allocatedBytes: 1, modifiedAt: Date(), reason: "", eligibility: .eligible)
        #expect(throws: (any Error).self) { try ScanPolicy(home: forgedHome).validate(item) }
        let report = Scanner(home: forgedHome).scan()
        #expect(report.candidates.isEmpty)
        #expect(!(report.issues.isEmpty))
    }
    @Test func testRecentCacheActivityIsReviewOnly() throws {
        let recent = try file("Library/Caches/pip/recent", old: false)
        #expect(!(try candidate(recent).isEligible))
        let nested = try file("Library/Caches/pip/tree/nested/recent", old: false)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -40 * 86400)], ofItemAtPath: nested.deletingLastPathComponent().deletingLastPathComponent().path)
        let folder = nested.deletingLastPathComponent().deletingLastPathComponent()
        #expect(!(try candidate(folder).isEligible))
    }
    @Test func testModelSkillAndProjectContentsAreProtectedInsideAllowedCache() throws {
        for path in [".codex/skills/tool/SKILL.md", ".agents/skills/tool/data", ".ollama/models/blob", "huggingface/hub/weight", "project/package.json", "model/weights.safetensors"] {
            let nested = try file("Library/Caches/pip/protected/" + path)
            let item = try candidate(home.appendingPathComponent("Library/Caches/pip/protected"))
            #expect(!item.isEligible)
            #expect(CleanupService(home: home, trashOperation: try fakeTrash()).trash([item], confirmed: true).first?.status == .refused)
            #expect(fm.fileExists(atPath: nested.path))
            try fm.removeItem(at: home.appendingPathComponent("Library/Caches/pip/protected"))
        }
    }
    @Test func testOverlapRefusesBothParentAndChildBeforeAnyMutation() throws {
        let nested = try file("Library/Caches/pip/tree/file")
        let parent = try candidate(nested.deletingLastPathComponent())
        let child = Candidate(id: "nested", url: nested, title: "file", category: .cache, allocatedBytes: 1,
                              modifiedAt: Date(), reason: "", eligibility: .eligible, snapshot: parent.snapshot)
        let result = CleanupService(home: home, trashOperation: try fakeTrash()).trash([parent, child], confirmed: true)
        #expect(result.map(\.status) == [.refused, .refused])
        #expect(fm.fileExists(atPath: nested.path))
    }
    @Test func testAddedNestedFilePreventsCleanup() throws {
        let original = try file("Library/Caches/pip/tree/file")
        let item = try candidate(original.deletingLastPathComponent())
        try file("Library/Caches/pip/tree/added")
        #expect(CleanupService(home: home, trashOperation: try fakeTrash()).trash([item], confirmed: true).first?.status == .refused)
        #expect(fm.fileExists(atPath: original.path))
    }
    @Test func testCapacityIsMeasuredAndUnavailablePathFails() throws {
        let capacity = try StorageInfo.read(at: home)
        #expect(capacity.totalBytes > 0)
        #expect(capacity.availableBytes >= 0)
        #expect(capacity.availableBytes <= capacity.totalBytes)
        #expect(throws: (any Error).self) { try StorageInfo.read(at: self.home.appendingPathComponent("does-not-exist")) }
    }

    @Test func testSymbolicLinkDotPathCannotReuseValidSnapshot() throws {
        let original = try file("Library/Caches/pip/item")
        let item = try candidate(original)
        let root = original.deletingLastPathComponent()
        try fm.createDirectory(at: root.appendingPathComponent("dir"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: root.appendingPathComponent("dir"))
        let alias = URL(fileURLWithPath: root.path + "/link/../item")
        let forged = Candidate(id: "dot-alias", url: alias, title: "item", category: .cache, allocatedBytes: 1,
                               modifiedAt: item.modifiedAt, reason: "", eligibility: .eligible, snapshot: item.snapshot)
        #expect(throws: (any Error).self) { try ScanPolicy(home: self.home).validate(forged) }
        #expect(CleanupService(home: home, trashOperation: try fakeTrash()).trash([forged], confirmed: true).first?.status == .refused)
        #expect(fm.fileExists(atPath: original.path))
    }
    @Test func testUnreadableDirectoryIsPartialAndCannotBeCleaned() throws {
        let nested = try file("Library/Caches/pip/tree/file")
        let tree = nested.deletingLastPathComponent()
        #expect(chmod(tree.path, 0) == 0)
        defer { _ = chmod(tree.path, 0o700) }
        let report = Scanner(home: home).scan()
        let item = try #require(report.candidates.first { $0.url == tree })
        #expect(!item.isEligible)
        #expect(item.snapshot?.isComplete == false)
        #expect(!report.issues.isEmpty)
        #expect(CleanupService(home: home, trashOperation: try fakeTrash()).trash([item], confirmed: true).first?.status == .refused)
    }
    @Test func testDepthLimitCannotProduceEligibleDirectory() throws {
        try file("Library/Caches/pip/tree/one/two/three/file")
        let report = Scanner(home: home, limits: ScanLimits(maximumDepth: 2)).scan()
        #expect(!report.candidates.isEmpty)
        #expect(!report.candidates.contains { $0.isEligible })
        #expect(!report.issues.isEmpty)
    }
    @Test func testSparseFileUsesAllocatedBlocksRatherThanLogicalLength() throws {
        let sparse = try file("Library/Caches/pip/sparse", bytes: 0)
        let handle = try FileHandle(forWritingTo: sparse)
        try handle.truncate(atOffset: 128 * 1024 * 1024)
        try handle.close()
        var info = stat(); #expect(lstat(sparse.path, &info) == 0)
        let item = try candidate(sparse)
        #expect(item.allocatedBytes == Int64(info.st_blocks) * 512)
        #expect(item.allocatedBytes < 128 * 1024 * 1024)
    }
    @Test func testHardlinkedCacheCannotBeCleaned() throws {
        let original = try file("Library/Caches/pip/item")
        try fm.linkItem(at: original, to: home.appendingPathComponent("external-hardlink"))
        let item = try candidate(original)
        #expect(!item.isEligible)
        #expect(CleanupService(home: home, trashOperation: try fakeTrash()).trash([item], confirmed: true).first?.status == .refused)
        #expect(fm.fileExists(atPath: original.path))
    }
    @Test func testNoSnapshotCannotAuthorizeAnOtherwiseSupportedItem() throws {
        let original = try file("Library/Caches/pip/item")
        let forged = Candidate(id: "no-evidence", url: original, title: "item", category: .cache,
                               allocatedBytes: 1, modifiedAt: Date(), reason: "", eligibility: .eligible)
        #expect(CleanupService(home: home, trashOperation: try fakeTrash()).trash([forged], confirmed: true).first?.status == .refused)
        #expect(fm.fileExists(atPath: original.path))
    }
    @Test func testNestedSymlinkMakesWholeCandidatePartial() throws {
        let target = try file("outside/file")
        let nested = try file("Library/Caches/pip/tree/original")
        let link = nested.deletingLastPathComponent().appendingPathComponent("link")
        try fm.createSymbolicLink(at: link, withDestinationURL: target)
        let report = Scanner(home: home).scan()
        let item = try #require(report.candidates.first { $0.url == nested.deletingLastPathComponent() })
        #expect(item.snapshot?.isComplete == false)
        #expect(!item.isEligible)
        #expect(report.issues.contains { $0.url == link })
    }

}
