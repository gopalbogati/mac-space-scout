import Foundation

public enum CandidateCategory: String, Codable, CaseIterable, Sendable {
    case cache, installer, largeFile, modelCache
}

public enum CandidateEligibility: Equatable, Sendable {
    case eligible
    case reviewOnly(String)
}

public struct Candidate: Identifiable, Sendable {
    public let id: String
    public let url: URL
    public let title: String
    public let category: CandidateCategory
    public let allocatedBytes: Int64
    public let modifiedAt: Date
    public let reason: String
    public let eligibility: CandidateEligibility
    public let snapshot: FileSnapshot?
    public var isEligible: Bool { eligibility == .eligible }

    public init(id: String, url: URL, title: String, category: CandidateCategory,
                allocatedBytes: Int64, modifiedAt: Date, reason: String,
                eligibility: CandidateEligibility, snapshot: FileSnapshot? = nil) {
        self.id = id; self.url = url; self.title = title; self.category = category
        self.allocatedBytes = allocatedBytes; self.modifiedAt = modifiedAt
        self.reason = reason; self.eligibility = eligibility; self.snapshot = snapshot
    }
}

public struct ScanIssue: Sendable {
    public let url: URL
    public let message: String
    public init(url: URL, message: String) { self.url = url; self.message = message }
}

public struct ScanProgress: Sendable {
    public let visitedCount: Int
    public let currentURL: URL
}

public struct ScanReport: Sendable {
    public let candidates: [Candidate]
    public let issues: [ScanIssue]
    public let cancelled: Bool
    public let visitedCount: Int
    public init(candidates: [Candidate], issues: [ScanIssue], cancelled: Bool, visitedCount: Int) {
        self.candidates = candidates; self.issues = issues; self.cancelled = cancelled; self.visitedCount = visitedCount
    }
}

public struct ScanLimits: Sendable {
    public let maximumEntries: Int
    public let maximumDepth: Int
    public let maximumDuration: TimeInterval
    public let largeFileThreshold: Int64
    public init(maximumEntries: Int = 100_000, maximumDepth: Int = 64,
                maximumDuration: TimeInterval = 30, largeFileThreshold: Int64 = 100 * 1024 * 1024) {
        self.maximumEntries = max(1, maximumEntries); self.maximumDepth = max(1, maximumDepth)
        self.maximumDuration = max(0.01, maximumDuration); self.largeFileThreshold = max(0, largeFileThreshold)
    }
}

public enum CleanupStatus: String, Sendable { case trashed, refused, failed }
public struct CleanupOutcome: Sendable {
    public let candidateID: String
    public let url: URL
    public let status: CleanupStatus
    public let message: String
    public let allocatedBytes: Int64
}
