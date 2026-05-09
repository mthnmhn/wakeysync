import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let assetsURL = root.appendingPathComponent("App/Assets")
let sourceURL = assetsURL.appendingPathComponent("wakey_device.png")
let iconsetURL = assetsURL.appendingPathComponent("AppIcon.iconset")
let icnsURL = assetsURL.appendingPathComponent("AppIcon.icns")

guard let deviceImage = NSImage(contentsOf: sourceURL) else {
    fputs("Could not load \(sourceURL.path)\n", stderr)
    exit(1)
}

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func renderIcon(pixels: Int) throws -> Data {
    let canvas = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "WakeySyncIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create bitmap"])
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    let fullRect = NSRect(x: 0, y: 0, width: canvas, height: canvas)
    NSColor.clear.setFill()
    fullRect.fill()

    let tileRect = fullRect.insetBy(dx: canvas * 0.055, dy: canvas * 0.055)
    let tilePath = NSBezierPath(
        roundedRect: tileRect,
        xRadius: canvas * 0.21,
        yRadius: canvas * 0.21
    )

    let top = NSColor(calibratedRed: 0.91, green: 0.99, blue: 1.0, alpha: 1)
    let bottom = NSColor(calibratedRed: 0.82, green: 0.95, blue: 0.97, alpha: 1)
    NSGradient(starting: top, ending: bottom)?.draw(in: tilePath, angle: -90)

    NSColor.white.withAlphaComponent(0.34).setFill()
    NSBezierPath(ovalIn: NSRect(
        x: canvas * 0.18,
        y: canvas * 0.56,
        width: canvas * 0.64,
        height: canvas * 0.26
    )).fill()

    NSColor.black.withAlphaComponent(0.14).setFill()
    NSBezierPath(ovalIn: NSRect(
        x: canvas * 0.18,
        y: canvas * 0.25,
        width: canvas * 0.64,
        height: canvas * 0.08
    )).fill()

    let imageSize = deviceImage.size
    let targetWidth = canvas * 0.78
    let targetHeight = targetWidth * imageSize.height / max(imageSize.width, 1)
    let deviceRect = NSRect(
        x: (canvas - targetWidth) / 2,
        y: canvas * 0.32,
        width: targetWidth,
        height: targetHeight
    )

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current?.cgContext.setShadow(
        offset: CGSize(width: 0, height: -canvas * 0.018),
        blur: canvas * 0.028,
        color: NSColor.black.withAlphaComponent(0.12).cgColor
    )
    deviceImage.draw(in: deviceRect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "WakeySyncIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode png"])
    }

    return data
}

for size in sizes {
    let data = try renderIcon(pixels: size.pixels)
    try data.write(to: iconsetURL.appendingPathComponent(size.name), options: .atomic)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    fputs("iconutil failed\n", stderr)
    exit(process.terminationStatus)
}

print(icnsURL.path)
