// Renders the app icon into an .iconset directory: swift make-icon.swift <out.iconset>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels) / 1024

    // Icon body on the standard 1024 grid (824 pt squircle, 100 pt margin).
    let body = NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s),
                            xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: NSColor(srgbRed: 0.36, green: 0.47, blue: 1.0, alpha: 1),
               ending: NSColor(srgbRed: 0.16, green: 0.21, blue: 0.74, alpha: 1))!.draw(in: body, angle: -90)

    // A sharp-cornered window.
    let window = NSRect(x: 220 * s, y: 250 * s, width: 560 * s, height: 470 * s)
    NSColor.white.setFill()
    NSBezierPath(rect: window).fill()
    NSColor(white: 0.88, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: window.minX, y: window.maxY - 92 * s, width: window.width, height: 5 * s)).fill()
    for (index, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: window.minX + (36 + CGFloat(index) * 56) * s, y: window.maxY - 66 * s,
                                    width: 40 * s, height: 40 * s)).fill()
    }

    // Corner bracket pointing at the square top-right corner.
    let corner = NSPoint(x: window.maxX + 44 * s, y: window.maxY + 44 * s)
    let bracket = NSBezierPath()
    bracket.lineWidth = 26 * s
    bracket.lineJoinStyle = .miter
    bracket.lineCapStyle = .butt
    bracket.move(to: NSPoint(x: corner.x - 170 * s, y: corner.y))
    bracket.line(to: corner)
    bracket.line(to: NSPoint(x: corner.x, y: corner.y - 170 * s))
    NSColor(srgbRed: 1.0, green: 0.8, blue: 0.24, alpha: 1).setStroke()
    bracket.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
             ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]
for (name, pixels) in sizes {
    try render(pixels: pixels).write(to: output.appending(path: "icon_\(name).png"))
}
