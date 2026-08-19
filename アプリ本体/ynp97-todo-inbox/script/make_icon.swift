import AppKit
import Foundation

let outputDirectory = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.iconset"
let outputURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
let icnsURL: URL = {
    if CommandLine.arguments.count > 2 {
        return URL(fileURLWithPath: CommandLine.arguments[2])
    }
    return outputURL.deletingPathExtension().appendingPathExtension("icns")
}()
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let icons: [(name: String, pixels: Int)] = [
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

func drawIcon(size: Int) throws -> Data {
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
    ) else {
        throw NSError(domain: "IconRender", code: 1)
    }

    guard let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "IconRender", code: 3)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    defer { NSGraphicsContext.restoreGraphicsState() }

    let context = graphics.cgContext
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let radius = CGFloat(size) * 0.215
    let background = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.12, alpha: 1.0).setFill()
    background.fill()

    let innerRect = rect.insetBy(dx: CGFloat(size) * 0.055, dy: CGFloat(size) * 0.055)
    let inner = NSBezierPath(roundedRect: innerRect, xRadius: radius * 0.78, yRadius: radius * 0.78)
    NSColor(calibratedRed: 1.0, green: 0.91, blue: 0.32, alpha: 1.0).setFill()
    inner.fill()

    let text = "T" as NSString
    let fontSize = CGFloat(size) * 0.76
    let font = NSFont.systemFont(ofSize: fontSize, weight: .black)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(calibratedWhite: 0.08, alpha: 1.0),
        .paragraphStyle: paragraph
    ]
    let textSize = text.size(withAttributes: attributes)
    let textRect = CGRect(
        x: 0,
        y: (CGFloat(size) - textSize.height) / 2 - CGFloat(size) * 0.035,
        width: CGFloat(size),
        height: textSize.height
    )
    text.draw(in: textRect, withAttributes: attributes)

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconRender", code: 2)
    }
    return data
}

for icon in icons {
    let data = try drawIcon(size: icon.pixels)
    try data.write(to: outputURL.appendingPathComponent(icon.name), options: .atomic)
}

func appendFourCC(_ value: String, to data: inout Data) throws {
    guard let encoded = value.data(using: .ascii), encoded.count == 4 else {
        throw NSError(domain: "IconRender", code: 4)
    }
    data.append(encoded)
}

func appendUInt32BE(_ value: UInt32, to data: inout Data) {
    var bigEndian = value.bigEndian
    withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
}

let icnsChunks: [(type: String, file: String)] = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]

let payloads = try icnsChunks.map { chunk in
    (chunk.type, try Data(contentsOf: outputURL.appendingPathComponent(chunk.file)))
}

let totalLength = payloads.reduce(8) { total, payload in
    total + 8 + payload.1.count
}

var icns = Data()
try appendFourCC("icns", to: &icns)
appendUInt32BE(UInt32(totalLength), to: &icns)
for payload in payloads {
    try appendFourCC(payload.0, to: &icns)
    appendUInt32BE(UInt32(payload.1.count + 8), to: &icns)
    icns.append(payload.1)
}
try icns.write(to: icnsURL, options: .atomic)
