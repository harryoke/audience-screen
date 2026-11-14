import AppKit
import Foundation

let destination = CommandLine.arguments[1]
let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".iconset")
try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temp) }
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        NSColor(calibratedRed: 0.04, green: 0.08, blue: 0.16, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: p * 0.04, y: p * 0.04, width: p * 0.92, height: p * 0.92), xRadius: p * 0.2, yRadius: p * 0.2).fill()
        NSColor(calibratedRed: 0.1, green: 0.8, blue: 0.9, alpha: 1).setStroke()
        let screen = NSBezierPath(roundedRect: NSRect(x: p * 0.17, y: p * 0.28, width: p * 0.66, height: p * 0.46), xRadius: p * 0.05, yRadius: p * 0.05)
        screen.lineWidth = p * 0.04; screen.stroke()
        NSColor.white.setFill()
        let play = NSBezierPath()
        play.move(to: NSPoint(x: p * 0.43, y: p * 0.39)); play.line(to: NSPoint(x: p * 0.43, y: p * 0.63)); play.line(to: NSPoint(x: p * 0.64, y: p * 0.51)); play.close(); play.fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: temp.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", temp.path, "-o", destination]
try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
