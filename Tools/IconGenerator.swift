import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: CleanNestIconGenerator <AppIcon.iconset>\n", stderr)
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func renderIcon(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    canvas.fill()

    let inset = CGFloat(size) * 0.055
    let tile = canvas.insetBy(dx: inset, dy: inset)
    let radius = CGFloat(size) * 0.22
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)
    NSColor(calibratedRed: 0.29, green: 0.40, blue: 0.82, alpha: 1).setFill()
    tilePath.fill()

    let innerInset = CGFloat(size) * 0.12
    let inner = tile.insetBy(dx: innerInset, dy: innerInset)
    let innerPath = NSBezierPath(roundedRect: inner, xRadius: CGFloat(size) * 0.16, yRadius: CGFloat(size) * 0.16)
    NSColor.white.withAlphaComponent(0.075).setFill()
    innerPath.fill()

    let symbolConfiguration = NSImage.SymbolConfiguration(
        pointSize: CGFloat(size) * 0.49,
        weight: .semibold
    ).applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let leaf = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfiguration) {
        let symbolSize = CGFloat(size) * 0.56
        let symbolRect = NSRect(
            x: (CGFloat(size) - symbolSize) / 2,
            y: (CGFloat(size) - symbolSize) / 2 - CGFloat(size) * 0.015,
            width: symbolSize,
            height: symbolSize
        )
        leaf.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    let sparkCenter = NSPoint(x: CGFloat(size) * 0.72, y: CGFloat(size) * 0.71)
    let sparkRadius = CGFloat(size) * 0.042
    let spark = NSBezierPath()
    spark.move(to: NSPoint(x: sparkCenter.x, y: sparkCenter.y + sparkRadius))
    spark.line(to: NSPoint(x: sparkCenter.x + sparkRadius * 0.38, y: sparkCenter.y + sparkRadius * 0.2))
    spark.line(to: NSPoint(x: sparkCenter.x + sparkRadius, y: sparkCenter.y))
    spark.line(to: NSPoint(x: sparkCenter.x + sparkRadius * 0.38, y: sparkCenter.y - sparkRadius * 0.2))
    spark.line(to: NSPoint(x: sparkCenter.x, y: sparkCenter.y - sparkRadius))
    spark.line(to: NSPoint(x: sparkCenter.x - sparkRadius * 0.38, y: sparkCenter.y - sparkRadius * 0.2))
    spark.line(to: NSPoint(x: sparkCenter.x - sparkRadius, y: sparkCenter.y))
    spark.line(to: NSPoint(x: sparkCenter.x - sparkRadius * 0.38, y: sparkCenter.y + sparkRadius * 0.2))
    spark.close()
    NSColor(calibratedRed: 1, green: 0.77, blue: 0.28, alpha: 1).setFill()
    spark.fill()

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return data
}

for (filename, size) in variants {
    try renderIcon(size: size).write(
        to: outputDirectory.appendingPathComponent(filename),
        options: .atomic
    )
}
