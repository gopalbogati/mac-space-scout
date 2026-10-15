import Testing
import Foundation
import SpaceScoutCore
@testable import SpaceScout

struct ReviewStateTests {
    func item(_ id: String, eligible: Bool = true) -> Candidate {
        Candidate(id: id, url: URL(fileURLWithPath: "/Users/demo/Library/Caches/pip/\(id)"), title: id,
                  category: .cache, allocatedBytes: 4096, modifiedAt: .distantPast,
                  reason: "fixture", eligibility: eligible ? .eligible : .reviewOnly("Protected"))
    }
    @Test func reportNeverPreselectsAndRescanClearsSelection() {
        let a = item("a"); var state = ReviewState(demo: false)
        let report = ScanReport(candidates: [a], issues: [], cancelled: false, visitedCount: 1)
        state.receive(report); #expect(state.selected.isEmpty)
        state.toggle(a); #expect(state.selected.count == 1)
        state.receive(report); #expect(state.selected.isEmpty)
    }
    @Test func protectedAndUnknownRowsCannotBeSelected() {
        let protected = item("model", eligible: false); let missing = item("missing")
        var state = ReviewState(demo: false)
        state.receive(ScanReport(candidates: [protected], issues: [], cancelled: false, visitedCount: 1))
        state.toggle(protected); state.toggle(missing)
        #expect(state.selectedIDs.isEmpty)
    }
    @Test func demoSelectionCannotAuthorizeFileOperations() {
        let a = item("a"); var state = ReviewState(demo: true)
        state.receive(ScanReport(candidates: [a], issues: [], cancelled: false, visitedCount: 1))
        state.toggle(a); #expect(state.selected.isEmpty)
    }
    @Test func togglingRemovesSelection() {
        let a = item("a"); var state = ReviewState(demo: false)
        state.receive(ScanReport(candidates: [a], issues: [], cancelled: false, visitedCount: 1))
        state.toggle(a); state.toggle(a); #expect(state.selected.isEmpty)
    }
}

struct AppSafetyTests {
    @MainActor @Test func demoCannotStartRealScanOrConfirmation() {
        let model = AppModel(demo: true)
        model.scan()
        model.requestConfirmation()
        model.trashConfirmed()
        #expect(!model.busy)
        #expect(!model.confirming)
        #expect(model.review.candidates.count == 7)
        #expect(model.outcomes.isEmpty)
        #expect(model.review.candidates.allSatisfy { !$0.isEligible })
    }
    @Test func successfulItemsAreRemovedWhileUnmovedItemsRemainReviewable() {
        let fixtures = ReviewStateTests()
        let moved = fixtures.item("moved"), refused = fixtures.item("refused")
        var state = ReviewState(demo: false)
        state.receive(ScanReport(candidates: [moved, refused], issues: [], cancelled: false, visitedCount: 2))
        state.toggle(moved); state.toggle(refused)
        state.removeTrashed(["moved"])
        #expect(state.candidates.map(\.id) == ["refused"])
        #expect(state.selected.isEmpty)
    }
}

struct FileAccessTests {
    @MainActor @Test func missingFileOpenShowsErrorAndNeverSelectsItem() {
        let model = AppModel(demo: false)
        let missing = Candidate(id: "missing", url: URL(fileURLWithPath: "/private/tmp/SpaceScoutMissing-\(UUID().uuidString)"), title: "Missing fixture", category: .largeFile, allocatedBytes: 0, modifiedAt: .distantPast, reason: "Fixture", eligibility: .reviewOnly("Personal file"))
        model.open(missing)
        #expect(model.actionError != nil)
        #expect(model.selected.isEmpty)
    }
    @MainActor @Test func demoOpenIsDisabledEvenForExistingRealPath() {
        let model = AppModel(demo: true)
        let existing = Candidate(id: "root", url: URL(fileURLWithPath: "/"), title: "Fixture", category: .largeFile, allocatedBytes: 0, modifiedAt: .distantPast, reason: "Fixture", eligibility: .reviewOnly("Protected"))
        model.open(existing)
        #expect(model.actionError == nil)
        #expect(model.selected.isEmpty)
    }
}
