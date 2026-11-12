import AppKit
import ImageIO
import UniformTypeIdentifiers
// icon <outdir>: the app icon at every macOS size — a blue tile, three sheets of glass stacked, an accent tab on the front one.
let out = CommandLine.arguments[1]
func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}
func draw(_ px: Int) -> CGImage {
    let s = CGFloat(px)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let inset = s * 0.098, side = s - inset * 2
    let tile = CGRect(x: inset, y: inset, width: side, height: side)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: side * 0.225, cornerHeight: side * 0.225, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: c(0x0B1437, 0.35))
    ctx.addPath(tilePath); ctx.setFillColor(c(0x3B6FE0)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(tilePath); ctx.clip()
    let ground = CGGradient(colorsSpace: nil, colors: [c(0x6FA8FF), c(0x3B6FE0), c(0x2A3F9E)] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(ground, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
    // A soft light from the top.
    let glow = CGGradient(colorsSpace: nil, colors: [c(0xFFFFFF, 0.28), c(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: tile.midX - side * 0.15, y: tile.maxY), startRadius: 0,
                           endCenter: CGPoint(x: tile.midX - side * 0.15, y: tile.maxY), endRadius: side * 0.75, options: [])
    ctx.restoreGState()
    // Three sheets, stepped up and to the right; the back ones are glass.
    let w = side * 0.50, h = side * 0.60, r = side * 0.06, step = side * 0.058
    let front = CGRect(x: tile.midX - w / 2 - step, y: tile.midY - h / 2 - step, width: w, height: h)
    for (i, alpha) in [(2, CGFloat(0.26)), (1, 0.50), (0, 1.0)] as [(Int, CGFloat)] {
        let sheet = front.offsetBy(dx: step * CGFloat(i), dy: step * CGFloat(i))
        let path = CGPath(roundedRect: sheet, cornerWidth: r, cornerHeight: r, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.010), blur: s * 0.028, color: c(0x0B1437, i == 0 ? 0.32 : 0.14))
        ctx.addPath(path); ctx.setFillColor(c(0xFFFFFF, alpha)); ctx.fillPath()
        ctx.restoreGState()
        if i > 0 {  // the glass sheets' rim
            ctx.addPath(path); ctx.setStrokeColor(c(0xFFFFFF, 0.55)); ctx.setLineWidth(max(1, s * 0.004)); ctx.strokePath()
        }
    }
    // The front sheet: a soft paper gradient, an accent tab, lines of text.
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: front, cornerWidth: r, cornerHeight: r, transform: nil)); ctx.clip()
    let paper = CGGradient(colorsSpace: nil, colors: [c(0xFFFFFF), c(0xEEF2FB)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(paper, start: CGPoint(x: 0, y: front.maxY), end: CGPoint(x: 0, y: front.minY), options: [])
    ctx.restoreGState()
    let tab = CGRect(x: front.minX + w * 0.12, y: front.maxY - h * 0.24, width: w * 0.24, height: h * 0.105)
    ctx.addPath(CGPath(roundedRect: tab, cornerWidth: tab.height / 2, cornerHeight: tab.height / 2, transform: nil))
    ctx.setFillColor(c(0xFF9F0A)); ctx.fillPath()
    for (i, part) in [CGFloat(1.0), 0.72, 0.88, 0.46].enumerated() {
        let y = front.maxY - h * (0.40 + CGFloat(i) * 0.135)
        let line = CGRect(x: front.minX + w * 0.12, y: y, width: w * 0.76 * part, height: h * 0.042)
        ctx.addPath(CGPath(roundedRect: line, cornerWidth: line.height / 2, cornerHeight: line.height / 2, transform: nil))
        ctx.setFillColor(c(0x2A3F9E, 0.26)); ctx.fillPath()
    }
    return ctx.makeImage()!
}
for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128),
                   ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "\(out)/\(name).png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, draw(px), nil); CGImageDestinationFinalize(d)
}
