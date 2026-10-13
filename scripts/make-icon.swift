import AppKit
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconset = root.appendingPathComponent("Sources/YubaiApp/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
func render(_ size: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    let rect = NSRect(x: 0, y: 0, width: 1024, height: 1024)
    NSColor(calibratedRed: 0.09, green: 0.31, blue: 0.26, alpha: 1).setFill(); rect.fill()
    let gradient = NSGradient(starting: NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.38, alpha: 1), ending: NSColor(calibratedRed: 0.06, green: 0.25, blue: 0.22, alpha: 1))!
    gradient.draw(in: rect, angle: -55)
    let circle = NSBezierPath(ovalIn: NSRect(x: 222, y: 222, width: 580, height: 580))
    NSColor(calibratedWhite: 0.98, alpha: 0.97).setFill(); circle.fill()
    let half = NSBezierPath(); half.move(to: NSPoint(x: 512, y: 222)); half.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 290, startAngle: -90, endAngle: 90, clockwise: false); half.close()
    NSColor(calibratedRed: 0.68, green: 0.83, blue: 0.69, alpha: 1).setFill(); half.fill()
    let slit = NSBezierPath(roundedRect: NSRect(x: 494, y: 186, width: 36, height: 652), xRadius: 18, yRadius: 18)
    NSColor(calibratedRed: 0.12, green: 0.37, blue: 0.30, alpha: 1).setFill(); slit.fill()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}
var images: [[String: String]] = []
try render(1024).write(to: iconset.appendingPathComponent("Icon-1024.png"))
images.append(["filename":"Icon-1024.png", "idiom":"universal", "platform":"ios", "size":"1024x1024"])
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] { let name = "Icon-mac-\(size)@\(scale)x.png"; try render(size * scale).write(to: iconset.appendingPathComponent(name)); images.append(["filename":name,"idiom":"mac","size":"\(size)x\(size)","scale":"\(scale)x"]) }
}
let content: [String: Any] = ["images":images,"info":["author":"xcode","version":1]]
try JSONSerialization.data(withJSONObject: content, options: .prettyPrinted).write(to: iconset.appendingPathComponent("Contents.json"))
let assets = iconset.deletingLastPathComponent()
try Data("{\"info\":{\"author\":\"xcode\",\"version\":1}}".utf8).write(to: assets.appendingPathComponent("Contents.json"))
