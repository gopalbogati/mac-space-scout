import Foundation

struct LaunchOptions {
    let demo: Bool
    let scanJSON: Bool
    let snapshotPath: String?
    init(_ args: [String]) throws {
        scanJSON = args.contains("--scan-json")
        if let index = args.firstIndex(of: "--demo-snapshot") {
            guard !scanJSON, args.filter({ $0 == "--demo-snapshot" }).count == 1,
                  args.indices.contains(index + 1), args[index + 1].hasPrefix("/"),
                  URL(fileURLWithPath: args[index + 1]).pathExtension.lowercased() == "png" else {
                throw LaunchError.invalidSnapshot
            }
            snapshotPath = args[index + 1]
        } else { snapshotPath = nil }
        demo = args.contains("--demo") || snapshotPath != nil
    }
    enum LaunchError: LocalizedError {
        case invalidSnapshot
        var errorDescription: String? { "Use --demo-snapshot /absolute/output.png without --scan-json. Snapshot mode always uses synthetic demo data." }
    }
}
