// Draws an app icon from the approved mockup: Tidy's rings on green, Ward's shield on indigo.
//
//   swift scripts/make-icon.swift tidy build/Tidy.iconset
//   swift scripts/make-icon.swift ward build/Ward.iconset

import AppKit

func color(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func bitmap(_ pixels: Int, draw: (NSRect) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

guard CommandLine.arguments.count == 3, ["tidy", "ward"].contains(CommandLine.arguments[1]) else {
    print("Usage: swift make-icon.swift tidy|ward OUTPUT.iconset")
    exit(1)
}
let isTidy = CommandLine.arguments[1] == "tidy"

/// A point of the mockup's glyph grid (origin top left, `size` units across) on the 1024 master.
func point(_ x: CGFloat, _ y: CGFloat, size: CGFloat, span: CGFloat) -> NSPoint {
    let unit = span / size
    return NSPoint(x: 512 + (x - size / 2) * unit, y: 512 - (y - size / 2) * unit)
}

/// The 1024-pixel master, on Apple's icon grid: an 824-pixel tile with a 100-pixel margin.
let master = bitmap(1024) { _ in
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    color(isTidy ? 0x1E8A4C : 0x4F4DD0).setFill()
    tile.fill()
    NSColor.white.set()

    if isTidy {
        // Two rings on a 30-unit grid, 494 pixels across.
        let unit: CGFloat = 494 / 30
        for radius in [10.5, 4.5] as [CGFloat] {
            let ring = NSBezierPath(
                ovalIn: NSRect(
                    x: 512 - radius * unit, y: 512 - radius * unit, width: radius * unit * 2,
                    height: radius * unit * 2))
            ring.lineWidth = 2.4 * unit
            ring.stroke()
        }
    } else {
        // A shield with its left half filled, on a 16-unit grid, 478 pixels across.
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { point(x, y, size: 16, span: 478) }
        let outline = NSBezierPath()
        outline.move(to: p(8, 1.8))
        outline.line(to: p(13, 3.6))
        outline.line(to: p(13, 7.7))
        outline.curve(to: p(8, 14.2), controlPoint1: p(13, 10.7), controlPoint2: p(10.9, 13.1))
        outline.curve(to: p(3, 7.7), controlPoint1: p(5.1, 13.1), controlPoint2: p(3, 10.7))
        outline.line(to: p(3, 3.6))
        outline.close()
        outline.lineWidth = 1.1 * 478 / 16
        outline.lineJoinStyle = .round
        outline.stroke()

        let half = NSBezierPath()
        half.move(to: p(8, 1.8))
        half.line(to: p(8, 14.2))
        half.curve(to: p(3, 7.7), controlPoint1: p(5.1, 13.1), controlPoint2: p(3, 10.7))
        half.line(to: p(3, 3.6))
        half.close()
        half.fill()
    }
}

let folder = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

let source = NSImage(size: NSSize(width: 1024, height: 1024))
source.addRepresentation(master)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let rep = bitmap(pixels) { area in
            NSGraphicsContext.current?.imageInterpolation = .high
            source.draw(in: area)
        }
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
    }
}
