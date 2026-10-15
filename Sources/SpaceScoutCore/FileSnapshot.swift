import Foundation
import Darwin

/// Opaque evidence from a complete metadata scan. Callers cannot manufacture a snapshot.
public struct FileSnapshot: Sendable {
    public let isComplete: Bool
    public var entryCount: Int { entries.count }
    let url: URL
    let home: URL
    let root: URL
    let entries: [SnapshotEntry]
    let ancestors: [AncestorIdentity]
    let containsHardlinks: Bool
}

struct NodeIdentity: Equatable, Hashable, Sendable {
    let device: UInt64
    let inode: UInt64
}
struct NodeMetadata: Equatable, Sendable {
    let identity: NodeIdentity
    let mode: UInt16
    let size: Int64
    let allocated: Int64
    let modifiedSeconds: Int64
    let modifiedNanos: Int64
    let changedSeconds: Int64
    let changedNanos: Int64
    let links: UInt16
    let flags: UInt32
    let owner: UInt32
    var isDirectory: Bool { mode & UInt16(S_IFMT) == UInt16(S_IFDIR) }
    var isRegular: Bool { mode & UInt16(S_IFMT) == UInt16(S_IFREG) }
    var isSymlink: Bool { mode & UInt16(S_IFMT) == UInt16(S_IFLNK) }
    var isDataless: Bool { flags & UInt32(SF_DATALESS) != 0 }
    var modifiedAt: Date { Date(timeIntervalSince1970: Double(modifiedSeconds) + Double(modifiedNanos) / 1_000_000_000) }
    static func read(_ url: URL) throws -> NodeMetadata {
        var value = stat()
        guard lstat(url.path, &value) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return NodeMetadata(identity: NodeIdentity(device: UInt64(UInt32(bitPattern: value.st_dev)), inode: UInt64(value.st_ino)),
                            mode: value.st_mode, size: value.st_size, allocated: max(0, Int64(value.st_blocks) * 512),
                            modifiedSeconds: Int64(value.st_mtimespec.tv_sec), modifiedNanos: Int64(value.st_mtimespec.tv_nsec),
                            changedSeconds: Int64(value.st_ctimespec.tv_sec), changedNanos: Int64(value.st_ctimespec.tv_nsec),
                            links: value.st_nlink, flags: value.st_flags, owner: value.st_uid)
    }
}
struct SnapshotEntry: Equatable, Sendable {
    let relativePath: String
    let metadata: NodeMetadata
}
struct AncestorIdentity: Equatable, Sendable {
    let path: String
    let identity: NodeIdentity
}

/// Reject links in every component, including a linked home or cache root.
func checkedAncestors(of url: URL) throws -> [AncestorIdentity] {
    guard url.isFileURL, (url.host == nil || url.host == "" || url.host == "localhost"), url.path.hasPrefix("/"), !url.path.contains("\0"), !url.pathComponents.contains(".."), !url.pathComponents.contains(".") else { throw PolicyError("A local absolute file URL is required.") }
    var current = URL(fileURLWithPath: "/", isDirectory: true)
    var result: [AncestorIdentity] = []
    for component in url.lexicallyNormalized.pathComponents.dropFirst() {
        let metadata = try NodeMetadata.read(current)
        guard metadata.isDirectory, !metadata.isSymlink, !metadata.isDataless else {
            throw PolicyError("A path ancestor is a symbolic link, cloud placeholder, or non-directory.")
        }
        result.append(AncestorIdentity(path: current.path, identity: metadata.identity))
        current.appendPathComponent(component)
    }
    return result
}

/// Calls the body lazily, so entry limits and cancellation bound traversal and memory.
func visitChildren(of directory: URL, _ body: (URL) -> Bool) throws {
    _ = try checkedAncestors(of: directory)
    let before = try NodeMetadata.read(directory)
    guard before.isDirectory, !before.isSymlink, !before.isDataless else { throw PolicyError("Unsupported directory.") }
    let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    var opened = stat()
    guard fstat(descriptor, &opened) == 0,
          before.identity == NodeIdentity(device: UInt64(UInt32(bitPattern: opened.st_dev)), inode: UInt64(opened.st_ino)) else {
        close(descriptor); throw PolicyError("Directory identity changed while opening it.")
    }
    guard let handle = fdopendir(descriptor) else {
        let savedError = errno; close(descriptor)
        throw POSIXError(POSIXErrorCode(rawValue: savedError) ?? .EIO)
    }
    defer { closedir(handle) }
    while true {
        errno = 0
        guard let entry = readdir(handle) else {
            if errno != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            break
        }
        let name = withUnsafePointer(to: &entry.pointee.d_name) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
        }
        if name == "." || name == ".." { continue }
        if !body(directory.appendingPathComponent(name)) { break }
    }
}

// Foundation's standardizedFileURL rewrites /private/tmp to its symlink alias /tmp.
// Normalize dot segments lexically, preserving component spelling for lstat checks.
extension URL {
    var lexicallyNormalized: URL {
        var parts: [String] = []
        for part in pathComponents where part != "/" && part != "." {
            if part == ".." { if !parts.isEmpty { parts.removeLast() } }
            else { parts.append(part) }
        }
        return URL(fileURLWithPath: "/" + parts.joined(separator: "/"), isDirectory: hasDirectoryPath)
    }
}
