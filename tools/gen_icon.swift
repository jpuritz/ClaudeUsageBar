// Renders the app icon master PNG (1024x1024). Run: swift tools/gen_icon.swift <out.png>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let S: CGFloat = 1024

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx

// Big Sur-style squircle: 824pt centered, radius 185, soft drop shadow.
let squircle = NSBezierPath(
    roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
    xRadius: 185, yRadius: 185
)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.34, alpha: 1).setFill() // fill once for shadow
squircle.fill()
NSShadow().set()

// Terracotta gradient fill.
let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.89, green: 0.52, blue: 0.38, alpha: 1), // #E3856
    ending: NSColor(calibratedRed: 0.72, green: 0.35, blue: 0.24, alpha: 1)
)!
gradient.draw(in: squircle, angle: -60)

let center = NSPoint(x: S / 2, y: S / 2)
let radius: CGFloat = 235
let ringWidth: CGFloat = 108
let cream = NSColor(calibratedRed: 0.965, green: 0.937, blue: 0.894, alpha: 1)

// Ring track.
let track = NSBezierPath()
track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
track.lineWidth = ringWidth
cream.withAlphaComponent(0.25).setStroke()
track.stroke()

// Progress arc: ~72% used, from 12 o'clock clockwise, rounded caps.
let arc = NSBezierPath()
arc.appendArc(
    withCenter: center, radius: radius,
    startAngle: 90, endAngle: 90 - 360 * 0.72, clockwise: true
)
arc.lineWidth = ringWidth
arc.lineCapStyle = .round
cream.setStroke()
arc.stroke()

// Small dot marking the leading edge of the arc.
let endAngle = (90 - 360 * 0.72) * CGFloat.pi / 180
let dotCenter = NSPoint(
    x: center.x + radius * cos(endAngle),
    y: center.y + radius * sin(endAngle)
)
let dot = NSBezierPath(ovalIn: NSRect(
    x: dotCenter.x - 26, y: dotCenter.y - 26, width: 52, height: 52
))
NSColor(calibratedRed: 0.72, green: 0.35, blue: 0.24, alpha: 1).setFill()
dot.fill()

NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
