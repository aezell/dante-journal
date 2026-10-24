// Draws the app icon with AppKit and writes an .iconset; iconutil then makes
// AppIcon.icns. Run: swift macos/make_icon.swift macos
// Warm paper square with an ember initial, matching the app's palette.
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let set = URL(fileURLWithPath: out).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let size = NSSize(width: pixels, height: pixels)
    let image = NSImage(size: size)
    image.lockFocus()
    let s = CGFloat(pixels)
    let inset = s * 0.08
    let square = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = square.width * 0.22
    let bg = NSBezierPath(roundedRect: square, xRadius: radius, yRadius: radius)
    NSColor(calibratedRed: 0x1B / 255, green: 0x19 / 255, blue: 0x17 / 255, alpha: 1).setFill()
    bg.fill()
    // A quiet inner border in the surface tone.
    NSColor(calibratedRed: 0x33 / 255, green: 0x2E / 255, blue: 0x29 / 255, alpha: 1).setStroke()
    bg.lineWidth = max(1, s * 0.012)
    bg.stroke()
    // Three faint ruled lines, like a page.
    NSColor(calibratedRed: 0x33 / 255, green: 0x2E / 255, blue: 0x29 / 255, alpha: 1).setStroke()
    for i in 0..<3 {
        let y = square.minY + square.height * (0.30 + CGFloat(i) * 0.12)
        let line = NSBezierPath()
        line.move(to: NSPoint(x: square.minX + square.width * 0.56, y: y))
        line.line(to: NSPoint(x: square.maxX - square.width * 0.14, y: y))
        line.lineWidth = max(1, s * 0.014)
        line.stroke()
    }
    // The ember initial.
    let font = NSFont(name: "Georgia-Bold", size: s * 0.62) ?? NSFont.boldSystemFont(ofSize: s * 0.62)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(calibratedRed: 0xE0 / 255, green: 0x93 / 255, blue: 0x3A / 255, alpha: 1),
    ]
    let text = NSAttributedString(string: "D", attributes: attrs)
    let bounds = text.boundingRect(with: size, options: [.usesLineFragmentOrigin])
    let origin = NSPoint(x: square.minX + square.width * 0.16, y: square.midY - bounds.height / 2 - s * 0.02)
    text.draw(at: origin)
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print(set.path)
