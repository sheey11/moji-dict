import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: prepare_app_icon.swift input.png output.png\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let pixelSize = 1_024
let canvasSize = NSSize(width: pixelSize, height: pixelSize)
let canvasRect = NSRect(origin: .zero, size: canvasSize)

guard
    let sourceImage = NSImage(contentsOf: inputURL),
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ),
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
else {
    fputs("Unable to create icon bitmap.\n", stderr)
    exit(1)
}

bitmap.size = canvasSize
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.shouldAntialias = true
context.imageInterpolation = NSImageInterpolation.high
NSColor.clear.setFill()
canvasRect.fill()

let mask = NSBezierPath(
    roundedRect: canvasRect,
    xRadius: 224,
    yRadius: 224
)
mask.addClip()
sourceImage.draw(
    in: canvasRect,
    from: NSRect(origin: .zero, size: sourceImage.size),
    operation: .copy,
    fraction: 1
)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(
    using: NSBitmapImageRep.FileType.png,
    properties: [:]
) else {
    fputs("Unable to encode icon PNG.\n", stderr)
    exit(1)
}
try data.write(to: outputURL, options: Data.WritingOptions.atomic)
