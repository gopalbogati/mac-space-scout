import AppKit
import SwiftUI

// Draw only this application's own demo window, never the desktop or other apps.
// This uses AppKit's view drawing API and requires no screen-recording permission.
@MainActor enum DemoSnapshot {
    private static var started = false
    private static var snapshotWindow: NSWindow?
    static func start(path: String) {
        DispatchQueue.main.async {
            let size = NSSize(width: 1180, height: 800)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "SpaceScout"
            window.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: MainView(model: AppModel(demo: true)))
            host.frame = NSRect(origin: .zero, size: size)
            window.contentView = host
            snapshotWindow = window
            window.center()
            window.makeKeyAndOrderFront(nil)
            schedule(path: path)
        }
    }
    static func schedule(path: String) {
        guard !started else { return }; started = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            do {
                guard let window = snapshotWindow, let view = window.contentView else {
                    throw SnapshotError.noWindow
                }
                window.setContentSize(NSSize(width: 1180, height: 800))
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
                let bounds = view.bounds
                guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                    pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw SnapshotError.noBitmap }
                bitmap.size = bounds.size
                view.cacheDisplay(in: bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { throw SnapshotError.noBitmap }
                try png.write(to: URL(fileURLWithPath: path), options: .atomic)
                print("Synthetic demo snapshot written: \(path)")
                exit(0)
            } catch {
                fputs("Demo snapshot failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
    }
    enum SnapshotError: LocalizedError {
        case noWindow, noBitmap
        var errorDescription: String? { "The app’s own demo view could not be rendered." }
    }
}
