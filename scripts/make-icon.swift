import AppKit
import Foundation

let destination = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let background = NSBezierPath(roundedRect: NSRect(x: 42, y: 42, width: 940, height: 940), xRadius: 210, yRadius: 210)
NSColor(calibratedRed: 0.07, green: 0.17, blue: 0.22, alpha: 1).setFill(); background.fill()
let ring = NSBezierPath(ovalIn: NSRect(x: 225, y: 265, width: 510, height: 510))
ring.lineWidth = 64
NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.72, alpha: 1).setStroke(); ring.stroke()
let handle = NSBezierPath(); handle.move(to: NSPoint(x: 670, y: 320)); handle.line(to: NSPoint(x: 805, y: 185)); handle.lineWidth = 74; handle.lineCapStyle = .round; handle.stroke()
let inner = NSBezierPath(roundedRect: NSRect(x: 335, y: 390, width: 290, height: 240), xRadius: 30, yRadius: 30)
NSColor(calibratedWhite: 0.97, alpha: 1).setFill(); inner.fill()
let slot = NSBezierPath(roundedRect: NSRect(x: 385, y: 550, width: 190, height: 24), xRadius: 12, yRadius: 12)
NSColor(calibratedRed: 0.07, green: 0.17, blue: 0.22, alpha: 1).setFill(); slot.fill()
let light = NSBezierPath(ovalIn: NSRect(x: 540, y: 435, width: 28, height: 28))
NSColor(calibratedRed: 0.0, green: 0.48, blue: 0.45, alpha: 1).setFill(); light.fill()
image.unlockFocus()
let sizes = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]
for (size, scale) in sizes {
    let pixels = size * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    let suffix = scale == 2 ? "@2x" : ""
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(destination)/icon_\(size)x\(size)\(suffix).png"))
}
