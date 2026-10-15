import Foundation

/// Moves confirmed, unchanged supported items to macOS Trash. There is no permanent-delete path.
public struct CleanupService {
    let policy: ScanPolicy
    let trashOperation: (URL) throws -> Void
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                runningBundleIDs: Set<String> = [], trashOperation: ((URL) throws -> Void)? = nil) {
        policy = ScanPolicy(home: home, runningBundleIDs: runningBundleIDs)
        self.trashOperation = trashOperation ?? { url in try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
    }
    public func trash(_ candidates: [Candidate], confirmed: Bool) -> [CleanupOutcome] {
        let overlapping = Set(candidates.indices.filter { index in
            candidates.indices.contains { other in
                guard index != other else { return false }
                return ScanPolicy.contains(candidates[index].url, in: candidates[other].url, allowEqual: true)
                    || ScanPolicy.contains(candidates[other].url, in: candidates[index].url, allowEqual: true)
            }
        })
        return candidates.enumerated().map { index, candidate in
            func result(_ status: CleanupStatus, _ message: String) -> CleanupOutcome {
                CleanupOutcome(candidateID: candidate.id, url: candidate.url, status: status, message: message,
                               allocatedBytes: status == .trashed ? candidate.allocatedBytes : 0)
            }
            guard confirmed else { return result(.refused, "Explicit confirmation is required.") }
            guard !overlapping.contains(index) else { return result(.refused, "Duplicate or overlapping selections are refused.") }
            do {
                try policy.validate(candidate)
                try validateTree(candidate)
                // Recheck ancestor identities and item metadata immediately before the OS operation.
                try policy.validate(candidate)
            } catch { return result(.refused, error.localizedDescription) }
            do {
                try trashOperation(candidate.url)
                return result(.trashed, "Moved to Trash. Space is not reclaimed until Trash is emptied.")
            } catch { return result(.failed, error.localizedDescription) }
        }
    }
    private func validateTree(_ candidate: Candidate) throws {
        guard let snapshot = candidate.snapshot else { throw PolicyError("Missing scan evidence.") }
        var current: [SnapshotEntry] = []
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        func walk(_ url: URL, relative: String, depth: Int) throws {
            guard current.count < snapshot.entries.count, depth <= 256,
                  ProcessInfo.processInfo.systemUptime < deadline else { throw PolicyError("Tree grew or could not be fully revalidated. Scan again.") }
            _ = try checkedAncestors(of: url)
            let metadata = try NodeMetadata.read(url)
            guard !metadata.isSymlink, !metadata.isDataless, !ScanPolicy.isProtected(url), metadata.isRegular || metadata.isDirectory else {
                throw PolicyError("Tree contains a symbolic link, protected item, cloud placeholder, or special file.")
            }
            current.append(SnapshotEntry(relativePath: relative, metadata: metadata))
            if metadata.isDirectory {
                var failure: Error?
                try visitChildren(of: url) { child in
                    do { try walk(child, relative: relative.isEmpty ? child.lastPathComponent : relative + "/" + child.lastPathComponent, depth: depth + 1) }
                    catch { failure = error; return false }
                    return true
                }
                if let failure { throw failure }
                guard try NodeMetadata.read(url) == metadata else { throw PolicyError("Tree changed during validation.") }
            }
        }
        try walk(candidate.url, relative: "", depth: 0)
        guard current.sorted(by: { $0.relativePath < $1.relativePath }) == snapshot.entries else {
            throw PolicyError("Item or nested contents changed since scanning. Scan again.")
        }
    }
}
