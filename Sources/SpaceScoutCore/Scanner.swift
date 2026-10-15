import Foundation

/// Metadata-only synchronous work; call from a background task, never the main UI thread.
public struct Scanner: Sendable {
    let policy: ScanPolicy
    let limits: ScanLimits
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                runningBundleIDs: Set<String> = [], limits: ScanLimits = .init()) {
        policy = ScanPolicy(home: home, runningBundleIDs: runningBundleIDs); self.limits = limits
    }
    public func scan(isCancelled: @escaping () -> Bool = { false }, progress: @escaping (ScanProgress) -> Void = { _ in }) -> ScanReport {
        let run = ScanRun(policy: policy, limits: limits, isCancelled: isCancelled, progress: progress)
        return run.perform()
    }
}

private final class ScanRun {
    let policy: ScanPolicy
    let limits: ScanLimits
    let isCancelled: () -> Bool
    let progress: (ScanProgress) -> Void
    let started = ProcessInfo.processInfo.systemUptime
    var visited = 0
    var cancelled = false
    var stopped = false
    var candidates: [Candidate] = []
    var issues: [ScanIssue] = []
    var measured: Set<NodeIdentity> = []
    init(policy: ScanPolicy, limits: ScanLimits, isCancelled: @escaping () -> Bool, progress: @escaping (ScanProgress) -> Void) {
        self.policy = policy; self.limits = limits; self.isCancelled = isCancelled; self.progress = progress
    }
    func issue(_ url: URL, _ message: String) { issues.append(ScanIssue(url: url, message: message)) }
    func mayContinue(_ url: URL) -> Bool {
        if stopped { return false }
        if isCancelled() { cancelled = true; stopped = true; issue(url, "Scan cancelled; partial measurements cannot be cleaned."); return false }
        if visited >= limits.maximumEntries || ProcessInfo.processInfo.systemUptime - started >= limits.maximumDuration {
            stopped = true; issue(url, "Scan limit reached; coverage and measurements are incomplete."); return false
        }
        return true
    }
    func recordVisit(_ url: URL) -> Bool {
        guard mayContinue(url) else { return false }
        visited += 1
        progress(ScanProgress(visitedCount: visited, currentURL: url))
        return true
    }
    func rootIsUsable(_ url: URL, allowProtectedReview: Bool = false) -> Bool {
        guard mayContinue(url) else { return false }
        do {
            // Ancestors are checked before any read through this root.
            _ = try checkedAncestors(of: url)
            let metadata = try NodeMetadata.read(url)
            guard metadata.isDirectory, !metadata.isSymlink, !metadata.isDataless, (allowProtectedReview || !ScanPolicy.isProtected(url)) else {
                issue(url, "Skipped symbolic link, cloud location, protected location, or non-directory root."); return false
            }
            return true
        } catch let error as POSIXError where error.code == .ENOENT { return false }
        catch { issue(url, error.localizedDescription); return false }
    }
    func perform() -> ScanReport {
        do { try policy.validateHome() }
        catch { issue(policy.home, error.localizedDescription); return report() }
        for root in ScanPolicy.cacheRoots {
            let url = policy.home.appendingPathComponent(root.relativePath, isDirectory: true)
            guard rootIsUsable(url) else { continue }
            if !root.bundleIDs.isDisjoint(with: policy.runningBundleIDs) {
                issue(url, "Cache excluded because the associated application is running."); continue
            }
            children(url) { child in self.measure(child, root: url, category: .cache, cleanupAllowed: true) }
        }
        let broad = policy.home.appendingPathComponent("Library/Caches", isDirectory: true)
        if rootIsUsable(broad) {
            let known = Set(ScanPolicy.cacheRoots.map { policy.home.appendingPathComponent($0.relativePath).path })
            children(broad) { child in
                if !known.contains(child.path) { self.measure(child, root: broad, category: .cache, cleanupAllowed: false) }
            }
        }
        let models = policy.home.appendingPathComponent(".cache/huggingface", isDirectory: true)
        if rootIsUsable(models, allowProtectedReview: true) { children(models) { self.measure($0, root: models, category: .modelCache, cleanupAllowed: false) } }
        let downloads = policy.home.appendingPathComponent("Downloads", isDirectory: true)
        if rootIsUsable(downloads) {
            children(downloads) { child in
                do {
                    let metadata = try NodeMetadata.read(child)
                    let installer = metadata.isRegular && ["dmg", "pkg"].contains(child.pathExtension.lowercased())
                    self.measure(child, root: downloads, category: installer ? .installer : .largeFile,
                                 cleanupAllowed: installer, minimumBytes: installer ? 0 : self.limits.largeFileThreshold)
                } catch { self.issue(child, error.localizedDescription) }
            }
        }
        return report()
    }
    func report() -> ScanReport {
        ScanReport(candidates: candidates.sorted { $0.allocatedBytes == $1.allocatedBytes ? $0.url.path < $1.url.path : $0.allocatedBytes > $1.allocatedBytes },
                   issues: issues, cancelled: cancelled, visitedCount: visited)
    }
    func children(_ directory: URL, body: (URL) -> Void) {
        do {
            try visitChildren(of: directory) { child in
                guard self.mayContinue(child) else { return false }
                body(child)
                return !self.stopped
            }
        } catch { issue(directory, error.localizedDescription) }
    }
    func measure(_ url: URL, root: URL, category: CandidateCategory, cleanupAllowed: Bool, minimumBytes: Int64 = 0) {
        var entries: [SnapshotEntry] = []
        var complete = true
        var containsHardlinks = false
        var bytes: Int64 = 0
        var localIDs: Set<NodeIdentity> = []
        let initialAncestors: [AncestorIdentity]
        do { initialAncestors = try checkedAncestors(of: url) }
        catch { issue(url, error.localizedDescription); return }
        func walk(_ node: URL, relative: String, depth: Int) {
            guard recordVisit(node) else { complete = false; return }
            do {
                _ = try checkedAncestors(of: node)
                let metadata = try NodeMetadata.read(node)
                guard !metadata.isSymlink, !metadata.isDataless, (category == .modelCache || !ScanPolicy.isProtected(node)), metadata.isDirectory || metadata.isRegular else {
                    complete = false; issue(node, "Skipped symbolic link, cloud placeholder, protected item, or special file."); return
                }
                entries.append(SnapshotEntry(relativePath: relative, metadata: metadata))
                if metadata.isRegular && metadata.links > 1 { containsHardlinks = true }
                if localIDs.insert(metadata.identity).inserted, !measured.contains(metadata.identity) { bytes += metadata.allocated }
                if metadata.isDirectory {
                    guard depth < limits.maximumDepth else { complete = false; issue(node, "Directory depth limit reached."); return }
                    try visitChildren(of: node) { child in
                        guard self.mayContinue(child) else { complete = false; return false }
                        walk(child, relative: relative.isEmpty ? child.lastPathComponent : relative + "/" + child.lastPathComponent, depth: depth + 1)
                        return !self.stopped
                    }
                    if try NodeMetadata.read(node) != metadata { complete = false; issue(node, "Directory changed during measurement.") }
                }
            } catch { complete = false; issue(node, error.localizedDescription) }
        }
        walk(url, relative: "", depth: 0)
        guard let top = entries.first else { return }
        do { if try checkedAncestors(of: url) != initialAncestors { complete = false; issue(url, "An ancestor changed during measurement.") } }
        catch { complete = false; issue(url, error.localizedDescription) }
        guard bytes >= minimumBytes else { return }
        measured.formUnion(localIDs)
        let snapshot = FileSnapshot(isComplete: complete, url: url.lexicallyNormalized, home: policy.home, root: root,
                                    entries: entries.sorted { $0.relativePath < $1.relativePath }, ancestors: initialAncestors,
                                    containsHardlinks: containsHardlinks)
        let eligibility: CandidateEligibility
        if !complete { eligibility = .reviewOnly("Incomplete or changing measurement. Scan again before cleanup.") }
        else if containsHardlinks { eligibility = .reviewOnly("Contains shared hard links; allocation is counted only once and reclaimable space is uncertain.") }
        else if category == .cache && cleanupAllowed && entries.contains(where: { $0.metadata.modifiedAt > Date().addingTimeInterval(-7 * 86_400) }) {
            eligibility = .reviewOnly("Cache contains data modified within the last 7 days. Recent activity is preserved.")
        }
        else if !cleanupAllowed { eligibility = .reviewOnly(category == .modelCache ? "Model weights may be needed. Review in Finder." : "Personal files and unknown cache locations require review in Finder.") }
        else {
            do { _ = try policy.rootForCleanup(url, metadata: top.metadata); eligibility = .eligible }
            catch { eligibility = .reviewOnly(error.localizedDescription) }
        }
        let reason: String
        switch category {
        case .cache: reason = cleanupAllowed ? "Rebuildable cache estimate. Timestamps do not prove disuse. Close developer tools and related command-line processes before cleanup." : "Unknown application cache; review in Finder."
        case .installer: reason = "Installer download. Age does not prove it is unused; confirm you no longer need it."
        case .largeFile: reason = "Large Downloads item for personal review. Size and age do not prove disuse."
        case .modelCache: reason = "Hugging Face model cache; models are review-only."
        }
        candidates.append(Candidate(id: "\(top.metadata.identity.device):\(top.metadata.identity.inode):\(url.path)", url: url.lexicallyNormalized,
                                    title: url.lastPathComponent, category: category, allocatedBytes: bytes, modifiedAt: top.metadata.modifiedAt,
                                    reason: reason, eligibility: eligibility, snapshot: snapshot))
    }
}
