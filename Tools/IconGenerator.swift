import AppKit
import Foundation
import SwiftUI

@main
struct CleanNestIconGenerator {
    private static let variants: [(String, Int)] = [
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

    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fputs("usage: CleanNestIconGenerator <AppIcon.iconset>\n", stderr)
            exit(2)
        }

        let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        for (filename, size) in variants {
            try renderIcon(size: size).write(
                to: outputDirectory.appendingPathComponent(filename),
                options: .atomic
            )
        }
    }

    @MainActor
    private static func renderIcon(size: Int) throws -> Data {
        let dimension = CGFloat(size)
        let renderer = ImageRenderer(content: CNNestAppIconArtwork(size: dimension))
        renderer.proposedSize = ProposedViewSize(width: dimension, height: dimension)
        renderer.scale = 1
        renderer.isOpaque = false

        guard let image = renderer.cgImage else {
            throw CocoaError(.fileWriteUnknown)
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }
}
