import Foundation
import Darwin

public struct PolicyError: LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

struct CacheRoot {
    let relativePath: String
    let bundleIDs: Set<String>
    let developerTools: Bool
}

/// The allowlist is built into the engine. Injecting arbitrary cleanup roots is unsupported.
public struct ScanPolicy: Sendable {
    let home: URL
    let runningBundleIDs: Set<String>
    static let cacheRoots = [
        CacheRoot(relativePath: "Library/Caches/pip", bundleIDs: [], developerTools: true),
        CacheRoot(relativePath: "Library/Caches/Homebrew", bundleIDs: [], developerTools: true),
        CacheRoot(relativePath: "Library/Caches/org.swift.swiftpm", bundleIDs: ["com.apple.dt.Xcode"], developerTools: true),
        CacheRoot(relativePath: "Library/Caches/com.apple.dt.Xcode", bundleIDs: ["com.apple.dt.Xcode"], developerTools: true),
        CacheRoot(relativePath: "Library/Developer/Xcode/DerivedData", bundleIDs: ["com.apple.dt.Xcode"], developerTools: true),
        CacheRoot(relativePath: ".npm/_cacache", bundleIDs: [], developerTools: true),
        CacheRoot(relativePath: ".cache/pip", bundleIDs: [], developerTools: true),
        CacheRoot(relativePath: ".cache/uv", bundleIDs: [], developerTools: true)
    ]
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, runningBundleIDs: Set<String> = []) {
        self.home = home.lexicallyNormalized
        self.runningBundleIDs = runningBundleIDs
    }
    static func contains(_ child: URL, in parent: URL, allowEqual: Bool = false) -> Bool {
        let childParts = child.lexicallyNormalized.pathComponents, parentParts = parent.lexicallyNormalized.pathComponents
        return childParts.starts(with: parentParts) && (allowEqual || childParts.count > parentParts.count)
    }
    func validateHome() throws {
        guard home.isFileURL, home.path != "/" else { throw PolicyError("Unsupported home directory.") }
        let actualHome = FileManager.default.homeDirectoryForCurrentUser.lexicallyNormalized
        // Alternate homes exist solely for isolated fixture directories, never arbitrary system roots.
        let temporaryFixture = home.deletingLastPathComponent().path == "/private/tmp"
        guard home == actualHome || temporaryFixture else { throw PolicyError("Alternate home must be an isolated directory directly inside /private/tmp.") }
        _ = try checkedAncestors(of: home)
        let metadata = try NodeMetadata.read(home)
        guard metadata.isDirectory, !metadata.isSymlink, !metadata.isDataless, metadata.owner == getuid() else {
            throw PolicyError("Home must be an owned local directory without symbolic links.")
        }
    }
    static func isProtected(_ url: URL) -> Bool {
        let denied: Set<String> = ["cloudstorage", "mobile documents", "application support", "backups.backupdb", ".git", ".svn", ".trash",
                                   ".codex", ".agents", ".ollama", ".lmstudio", ".huggingface", "huggingface", "skills", "models"]
        let projectMarkers: Set<String> = ["skill.md", "package.swift", "package.json", "cargo.toml", "pyproject.toml", "go.mod", "cmakelists.txt", ".gitignore"]
        let modelExtensions: Set<String> = ["gguf", "ggml", "safetensors", "ckpt", "pt", "pth", "onnx", "h5", "tflite", "model", "bin"]
        return url.pathComponents.contains {
            let part = $0.lowercased()
            return denied.contains(part) || projectMarkers.contains(part) || part.hasSuffix(".photoslibrary")
                || part.hasSuffix(".photolibrary") || part.hasSuffix(".app") || part.hasSuffix(".xcodeproj")
                || part.hasSuffix(".xcworkspace") || modelExtensions.contains((part as NSString).pathExtension)
        }
    }
    /// A project or skill marker protects siblings and all descendants of its directory.
    /// Probe a fixed set of names, avoiding unbounded directory enumeration during policy checks.
    private func validateContainingDirectories(of url: URL, isDirectory: Bool) throws {
        let markers = [".git", ".svn", ".gitignore", "SKILL.md", "Package.swift", "package.json",
                       "Cargo.toml", "pyproject.toml", "go.mod", "CMakeLists.txt"]
        var directory = isDirectory ? url : url.deletingLastPathComponent()
        while Self.contains(directory, in: home, allowEqual: true) {
            _ = try checkedAncestors(of: directory)
            let metadata = try NodeMetadata.read(directory)
            guard metadata.isDirectory, !metadata.isSymlink, !metadata.isDataless else {
                throw PolicyError("A containing directory is unsupported or changed.")
            }
            for marker in markers {
                do {
                    _ = try NodeMetadata.read(directory.appendingPathComponent(marker))
                    throw PolicyError("A containing directory has project or skill metadata; preserve all its contents.")
                } catch let error as POSIXError where error.code == .ENOENT { continue }
            }
            if directory.path == home.path { break }
            directory.deleteLastPathComponent()
        }
    }
    func rootForCleanup(_ url: URL, metadata: NodeMetadata, now: Date = Date()) throws -> URL {
        try validateHome()
        let url = url.lexicallyNormalized
        guard !Self.isProtected(url), Self.contains(url, in: home) else { throw PolicyError("Protected or unsupported location.") }
        try validateContainingDirectories(of: url, isDirectory: metadata.isDirectory)
        for root in Self.cacheRoots {
            let rootURL = home.appendingPathComponent(root.relativePath, isDirectory: true)
            if Self.contains(url, in: rootURL) {
                guard root.bundleIDs.isDisjoint(with: runningBundleIDs) else { throw PolicyError("Close the associated running application before cleaning its cache.") }
                return rootURL
            }
        }
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        if url.deletingLastPathComponent() == downloads, metadata.isRegular,
           ["dmg", "pkg"].contains(url.pathExtension.lowercased()),
           metadata.modifiedAt <= now.addingTimeInterval(-30 * 86_400) { return downloads }
        throw PolicyError("Only allowlisted cache contents and direct Downloads installers at least 30 days old can be moved to Trash.")
    }
    /// Validates policy and complete scan evidence, independently of a UI selection or category.
    public func validate(_ candidate: Candidate) throws {
        guard candidate.isEligible else { throw PolicyError("This item is for review only.") }
        _ = try checkedAncestors(of: candidate.url)
        let metadata = try NodeMetadata.read(candidate.url)
        guard !metadata.isSymlink, !metadata.isDataless, metadata.isRegular || metadata.isDirectory else { throw PolicyError("Symbolic links, cloud placeholders, and special files are unsupported.") }
        let root = try rootForCleanup(candidate.url, metadata: metadata)
        guard let snapshot = candidate.snapshot, snapshot.isComplete, !snapshot.containsHardlinks,
              snapshot.url == candidate.url.lexicallyNormalized, snapshot.home == home, snapshot.root == root,
              snapshot.entries.first(where: { $0.relativePath.isEmpty })?.metadata == metadata else {
            throw PolicyError("Missing, incomplete, or changed scan evidence. Scan again.")
        }
        if Self.cacheRoots.contains(where: { home.appendingPathComponent($0.relativePath, isDirectory: true).path == root.path }) {
            guard snapshot.entries.allSatisfy({ $0.metadata.modifiedAt <= Date().addingTimeInterval(-7 * 86_400) }) else {
                throw PolicyError("Cache was modified within the last 7 days; keep recently active data.")
            }
        }
        guard try checkedAncestors(of: candidate.url) == snapshot.ancestors else {
            throw PolicyError("A path ancestor was replaced. Scan again.")
        }
    }
}
