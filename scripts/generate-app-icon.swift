// Run from the project root: swift scripts/generate-app-icon.swift
// Original vector artwork: docs/design/app-icon.svg.
import AppKit
import Foundation

let output = URL(fileURLWithPath: "Clear Stuff/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let sizes = [16, 32, 128, 256, 512]
var images: [[String: String]] = []
for size in sizes {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            fatalError("Could not create icon drawing context")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let cg = context.cgContext
        cg.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        cg.translateBy(x: 0, y: 1024)
        cg.scaleBy(x: 1, y: -1)
        cg.setFillColor(CGColor(srgbRed: 32 / 255, green: 32 / 255, blue: 32 / 255, alpha: 1))
        cg.addPath(CGPath(roundedRect: CGRect(x: 80, y: 80, width: 864, height: 864), cornerWidth: 190, cornerHeight: 190, transform: nil))
        cg.fillPath()
        cg.setFillColor(CGColor(gray: 1, alpha: 1))
        let sparkle = CGMutablePath()
        sparkle.move(to: CGPoint(x: 512, y: 258))
        for point in [CGPoint(x: 544, y: 360), CGPoint(x: 640, y: 392), CGPoint(x: 544, y: 424),
                      CGPoint(x: 512, y: 526), CGPoint(x: 480, y: 424), CGPoint(x: 384, y: 392), CGPoint(x: 480, y: 360)] {
            sparkle.addLine(to: point)
        }
        sparkle.closeSubpath()
        cg.addPath(sparkle)
        cg.fillPath()
        let tray = CGMutablePath()
        tray.move(to: CGPoint(x: 300, y: 524))
        tray.addLine(to: CGPoint(x: 270, y: 672))
        tray.addQuadCurve(to: CGPoint(x: 330, y: 732), control: CGPoint(x: 270, y: 732))
        tray.addLine(to: CGPoint(x: 694, y: 732))
        tray.addQuadCurve(to: CGPoint(x: 754, y: 672), control: CGPoint(x: 754, y: 732))
        tray.addLine(to: CGPoint(x: 724, y: 524))
        cg.setStrokeColor(CGColor(gray: 1, alpha: 1))
        cg.setLineWidth(48)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        cg.addPath(tray)
        cg.strokePath()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)@\(scale)x.png"
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not encode icon") }
        try png.write(to: output.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name])
    }
}
let manifest: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
print("Generated all 10 macOS icon slots (16–1024 pixels).")
