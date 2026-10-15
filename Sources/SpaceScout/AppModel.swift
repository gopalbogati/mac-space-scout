import AppKit
import SwiftUI
import SpaceScoutCore

struct ReviewState {
    var candidates: [Candidate] = []
    private(set) var selectedIDs: Set<String> = []
    let demo: Bool
    mutating func receive(_ report: ScanReport) {
        candidates = report.candidates
        selectedIDs.removeAll()
    }
    mutating func toggle(_ candidate: Candidate) {
        guard !demo, let recorded = candidates.first(where: { $0.id == candidate.id }), recorded.isEligible else { return }
        if selectedIDs.contains(candidate.id) { selectedIDs.remove(candidate.id) }
        else { selectedIDs.insert(candidate.id) }
    }
    var selected: [Candidate] { candidates.filter { $0.isEligible && selectedIDs.contains($0.id) } }
    mutating func removeTrashed(_ ids: Set<String>) {
        candidates.removeAll { ids.contains($0.id) }
        selectedIDs.removeAll()
    }
}

// Workers update one locked slot; the UI samples it five times per second.
// No main-actor task is enqueued for individual filesystem entries.
final class ScanMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var latest: ScanProgress?
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func isCancelled() -> Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func update(_ value: ScanProgress) { lock.lock(); latest = value; lock.unlock() }
    func read() -> ScanProgress? { lock.lock(); defer { lock.unlock() }; return latest }
}

@MainActor final class AppModel: ObservableObject {
    @Published var review: ReviewState
    @Published var storage: StorageInfo?
    @Published var capacityError: String?
    @Published var phase = "Ready to explore"
    @Published var busy = false
    @Published var cleaning = false
    @Published var progressCount = 0
    @Published var currentPath = ""
    @Published var issues: [ScanIssue] = []
    @Published var outcomes: [CleanupOutcome] = []
    @Published var hasScanned = false
    @Published var search = ""
    @Published var category: CandidateCategory?
    @Published var largestFirst = true
    @Published var inspector: Candidate?
    @Published var confirming = false
    private var mailbox: ScanMailbox?
    let demo: Bool
    init(demo: Bool = false) {
        self.demo = demo
        review = ReviewState(demo: demo)
        if demo {
            review.receive(DemoData.report)
            storage = DemoData.storage
            hasScanned = true
            phase = "Demo scan complete · synthetic data"
        } else { refreshCapacity() }
    }
    var selected: [Candidate] { review.selected }
    var selectedBytes: Int64 { selected.reduce(0) { $0 + $1.allocatedBytes } }
    var eligibleBytes: Int64 { review.candidates.filter(\.isEligible).reduce(0) { $0 + $1.allocatedBytes } }
    var visibleCandidates: [Candidate] {
        review.candidates.filter { item in
            (category == nil || item.category == category) &&
            (search.isEmpty || item.title.localizedCaseInsensitiveContains(search) || item.url.path.localizedCaseInsensitiveContains(search))
        }.sorted { largestFirst ? $0.allocatedBytes > $1.allocatedBytes : $0.allocatedBytes < $1.allocatedBytes }
    }
    var runningIDs: Set<String> { Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)) }
    func toggle(_ candidate: Candidate) { guard !busy else { return }; review.toggle(candidate) }
    func scan() {
        guard !demo, !busy else { return }
        busy = true; hasScanned = true; issues = []; progressCount = 0; currentPath = ""
        phase = "Scanning local metadata…"; inspector = nil
        review.receive(ScanReport(candidates: [], issues: [], cancelled: false, visitedCount: 0))
        let channel = ScanMailbox(); mailbox = channel
        let ids = runningIDs
        Task {
            let polling = Task { @MainActor in
                while !Task.isCancelled {
                    if let value = channel.read() { progressCount = value.visitedCount; currentPath = value.currentURL.path }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
            let report = await Task.detached(priority: .userInitiated) {
                Scanner(runningBundleIDs: ids, limits: appScanLimits).scan(isCancelled: { channel.isCancelled() }, progress: { channel.update($0) })
            }.value
            polling.cancel(); mailbox = nil; review.receive(report); issues = report.issues
            progressCount = report.visitedCount; busy = false
            phase = report.cancelled ? "Scan cancelled · partial results" : (report.issues.isEmpty ? "Scan complete" : "Scan complete · some locations could not be measured")
            refreshCapacity()
        }
    }
    func cancel() { guard busy, !cleaning else { return }; mailbox?.cancel(); phase = "Cancelling scan…" }
    func requestConfirmation() { guard !demo, !busy, !selected.isEmpty else { return }; confirming = true }
    func trashConfirmed() {
        guard !demo, !busy, confirming, !selected.isEmpty else { return }
        let items = selected; let ids = runningIDs
        confirming = false; busy = true; cleaning = true; phase = "Revalidating selected items and moving to Trash…"
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                CleanupService(runningBundleIDs: ids).trash(items, confirmed: true)
            }.value
            outcomes.append(contentsOf: result)
            review.removeTrashed(Set(result.filter { $0.status == .trashed }.map(\.candidateID)))
            cleaning = false; busy = false
            phase = result.allSatisfy { $0.status == .trashed } ? "Moved to Trash · available space measured separately" : "Review the cleanup results below"
            refreshCapacity()
        }
    }
    func refreshCapacity() {
        guard !demo else { return }
        Task {
            let result = await Task.detached(priority: .utility) { Result { try StorageInfo.read() } }.value
            switch result {
            case .success(let value): storage = value; capacityError = nil
            case .failure(let error): storage = nil; capacityError = error.localizedDescription
            }
        }
    }
    func reveal(_ candidate: Candidate) { guard !demo else { return }; NSWorkspace.shared.activateFileViewerSelecting([candidate.url]) }
    func openTrash() {
        guard !demo else { return }
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
    }
}

func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
extension CandidateCategory {
    var label: String {
        switch self { case .cache: return "Developer caches"; case .installer: return "Old installers"; case .largeFile: return "Large files"; case .modelCache: return "AI models" }
    }
    var symbol: String {
        switch self { case .cache: return "shippingbox"; case .installer: return "opticaldisc"; case .largeFile: return "doc"; case .modelCache: return "sparkles" }
    }
}

let appScanLimits = ScanLimits(maximumEntries: 500_000, maximumDuration: 60)
