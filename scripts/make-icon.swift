import AppKit
let base = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
func draw(size: Int) throws {
    let side = CGFloat(size)
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { exit(1) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: side / 1024, y: side / 1024)
    let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 208, yRadius: 208)
    let gradient = NSGradient(starting: NSColor(calibratedRed: 0.62, green: 0.38, blue: 1.0, alpha: 1), ending: NSColor(calibratedRed: 0.36, green: 0.16, blue: 0.82, alpha: 1))!
    gradient.draw(in: tile, angle: -90)
    NSColor.white.withAlphaComponent(0.95).setStroke()
    let tube = NSBezierPath(roundedRect: NSRect(x: 310, y: 350, width: 130, height: 415), xRadius: 65, yRadius: 65)
    tube.lineWidth = 36; tube.stroke()
    NSColor.white.withAlphaComponent(0.95).setFill()
    NSBezierPath(ovalIn: NSRect(x: 265, y: 245, width: 220, height: 220)).fill()
    let stem = NSBezierPath(roundedRect: NSRect(x: 353, y: 366, width: 44, height: 245), xRadius: 22, yRadius: 22)
    stem.fill()
    let drop = NSBezierPath()
    drop.move(to: NSPoint(x: 663, y: 665))
    drop.curve(to: NSPoint(x: 548, y: 428), controlPoint1: NSPoint(x: 628, y: 590), controlPoint2: NSPoint(x: 548, y: 500))
    drop.curve(to: NSPoint(x: 778, y: 428), controlPoint1: NSPoint(x: 548, y: 274), controlPoint2: NSPoint(x: 778, y: 274))
    drop.curve(to: NSPoint(x: 663, y: 665), controlPoint1: NSPoint(x: 778, y: 500), controlPoint2: NSPoint(x: 696, y: 590))
    drop.close(); NSColor(calibratedRed: 0.89, green: 0.83, blue: 1.0, alpha: 1).setFill(); drop.fill()
    NSGraphicsContext.restoreGraphicsState()
    let png = bitmap.representation(using: .png, properties: [:])!
    let names: [Int: [String]] = [16:["icon_16x16.png"],32:["icon_16x16@2x.png","icon_32x32.png"],64:["icon_32x32@2x.png"],128:["icon_128x128.png"],256:["icon_128x128@2x.png","icon_256x256.png"],512:["icon_256x256@2x.png","icon_512x512.png"],1024:["icon_512x512@2x.png"]]
    for name in names[size]! { try png.write(to: base.appendingPathComponent(name)) }
}
for size in [16,32,64,128,256,512,1024] { try draw(size: size) }
