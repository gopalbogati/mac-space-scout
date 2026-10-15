import AppKit
import SwiftUI
import SpaceScoutCore

@main struct SpaceScoutApp: App {
    @StateObject private var model: AppModel
    private let options: LaunchOptions
    init() {
        do { options = try LaunchOptions(Array(CommandLine.arguments.dropFirst())) }
        catch { fputs("\(error.localizedDescription)\n", stderr); exit(2) }
        if options.scanJSON {
            Self.printScanJSON(demo: options.demo)
            exit(0)
        }
        let isDemo = options.demo
        _model = StateObject(wrappedValue: AppModel(demo: isDemo))
        NSApplication.shared.setActivationPolicy(.regular)
        if let path = options.snapshotPath {
            DemoSnapshot.start(path: path)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                fputs("Demo snapshot failed: rendering timed out.\n", stderr); exit(1)
            }
        }
    }
    var body: some Scene {
        WindowGroup("SpaceScout") {
            MainView(model: model)
        }
            .defaultSize(width: 1180, height: 800)
            .commands { CommandGroup(replacing: .newItem) { }; CommandGroup(after: .appInfo) { Button("Scan storage", action: model.scan).disabled(model.demo || model.busy) } }
    }
    private static func printScanJSON(demo: Bool) {
        let ids = demo ? Set<String>() : Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let report = demo ? DemoData.report : Scanner(runningBundleIDs: ids, limits: appScanLimits).scan()
        let capacity = demo ? DemoData.storage : try? StorageInfo.read()
        let object: [String: Any] = [
            "readOnly": true, "demo": demo, "cancelled": report.cancelled, "visitedCount": report.visitedCount,
            "capacity": capacity.map { ["totalBytes": $0.totalBytes, "availableBytes": $0.availableBytes] } ?? [:],
            "candidates": report.candidates.map { item -> [String: Any] in
                var object: [String: Any] = ["path": item.url.path, "title": item.title, "category": item.category.rawValue,
                  "allocatedBytes": item.allocatedBytes, "reason": item.reason, "eligible": item.isEligible]
                if case .reviewOnly(let reason) = item.eligibility { object["reviewOnlyReason"] = reason }
                return object
            },
            "issues": report.issues.map { ["path": $0.url.path, "message": $0.message] }
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
        } catch { fputs("Could not encode scan output: \(error.localizedDescription)\n", stderr); exit(1) }
    }
}
