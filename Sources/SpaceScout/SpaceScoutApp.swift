import AppKit
import SwiftUI
import SpaceScoutCore

@main struct SpaceScoutApp: App {
    @StateObject private var model: AppModel
    init() {
        if CommandLine.arguments.contains("--scan-json") {
            Self.printScanJSON()
            exit(0)
        }
        _model = StateObject(wrappedValue: AppModel(demo: CommandLine.arguments.contains("--demo")))
        NSApplication.shared.setActivationPolicy(.regular)
    }
    var body: some Scene {
        WindowGroup("SpaceScout") { MainView(model: model) }
            .defaultSize(width: 1180, height: 800)
            .commands { CommandGroup(replacing: .newItem) { }; CommandGroup(after: .appInfo) { Button("Scan storage", action: model.scan).disabled(model.demo || model.busy) } }
    }
    private static func printScanJSON() {
        let demo = CommandLine.arguments.contains("--demo")
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
