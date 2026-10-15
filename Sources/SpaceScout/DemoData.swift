import Foundation
import SpaceScoutCore

enum DemoData {
    static let storage = StorageInfo(totalBytes: 1_000_000_000_000, availableBytes: 284_000_000_000)
    static let report: ScanReport = {
        let entries: [(String, String, CandidateCategory, Int64, String)] = [
            ("Summer footage", "Downloads/Summer footage", .largeFile, 18_400_000_000, "Personal files are always review-only. Review this folder in Finder."),
            ("Local language model", ".cache/huggingface/hub/models--example", .modelCache, 8_200_000_000, "AI models are protected. SpaceScout never offers model cleanup."),
            ("Derived build artifacts", "Library/Developer/Xcode/DerivedData/Example", .cache, 4_600_000_000, "Rebuildable artifacts. Real scans require complete metadata, old activity, and fresh validation."),
            ("CreativeTools installer.dmg", "Downloads/CreativeTools installer.dmg", .installer, 2_100_000_000, "Direct Downloads installer older than 30 days. Review before choosing to move it."),
            ("Package downloads", "Library/Caches/pip/example", .cache, 860_000_000, "Package cache. Close related developer tools before reviewing."),
            ("Archived sketches.zip", "Downloads/Archived sketches.zip", .largeFile, 640_000_000, "Personal archive. Size does not establish whether a file is needed."),
            ("Agent skills", "Library/Caches/example/skills", .cache, 124_000_000, "Installed skills and detected Git projects are protected.")
        ]
        return ScanReport(candidates: entries.enumerated().map { index, entry in
            Candidate(id: "demo-\(index)", url: URL(fileURLWithPath: "/Users/demo/\(entry.1)"), title: entry.0,
                      category: entry.2, allocatedBytes: entry.3, modifiedAt: Date(timeIntervalSince1970: 1_750_000_000),
                      reason: entry.4, eligibility: .reviewOnly("Synthetic demonstration · file operations disabled"))
        }, issues: [], cancelled: false, visitedCount: 24_816)
    }()
}
