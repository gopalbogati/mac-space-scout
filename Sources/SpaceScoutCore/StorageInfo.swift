import Foundation

public struct StorageInfo: Sendable {
    public let totalBytes: Int64
    public let availableBytes: Int64
    public init(totalBytes: Int64, availableBytes: Int64) {
        self.totalBytes = totalBytes; self.availableBytes = availableBytes
    }
    /// Measured filesystem capacity, separate from allocated candidate estimates.
    public static func read(at url: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> StorageInfo {
        let values = try FileManager.default.attributesOfFileSystem(forPath: url.path)
        guard let total = values[.systemSize] as? NSNumber, let free = values[.systemFreeSize] as? NSNumber else {
            throw PolicyError("Filesystem capacity is unavailable.")
        }
        return StorageInfo(totalBytes: total.int64Value, availableBytes: free.int64Value)
    }
}
