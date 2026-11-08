import AppKit

let output = CommandLine.arguments[1]
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor(red: 0.0, green: 0.40, blue: 0.91, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 190, yRadius: 190).fill()
NSColor.white.withAlphaComponent(0.12).setFill()
let window = NSBezierPath(roundedRect: NSRect(x: 220, y: 280, width: 584, height: 464), xRadius: 64, yRadius: 64)
window.fill()
NSColor.white.setStroke()
window.lineWidth = 28
window.stroke()
let bar = NSBezierPath()
bar.move(to: NSPoint(x: 228, y: 638)); bar.line(to: NSPoint(x: 796, y: 638))
bar.lineWidth = 24; bar.stroke()
for x in [280, 320, 360] {
    NSColor.white.withAlphaComponent(0.9).setFill()
    NSBezierPath(ovalIn: NSRect(x: x, y: 677, width: 16, height: 16)).fill()
}
let prompt = NSBezierPath()
prompt.move(to: NSPoint(x: 330, y: 560)); prompt.line(to: NSPoint(x: 410, y: 490)); prompt.line(to: NSPoint(x: 330, y: 420))
prompt.lineWidth = 40; prompt.lineCapStyle = .round; prompt.lineJoinStyle = .round; prompt.stroke()
let underscore = NSBezierPath()
underscore.move(to: NSPoint(x: 485, y: 420)); underscore.line(to: NSPoint(x: 645, y: 420))
underscore.lineWidth = 40; underscore.lineCapStyle = .round; underscore.stroke()
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
