// Rysuje ikonę MarkEdit (1024×1024 PNG): kartka przecięta na pół — surowy Markdown | podgląd — i iskra AI.
// Użycie: make_icon <out.png>
import AppKit

let size: CGFloat = 1024
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let base = NSGraphicsContext(bitmapImageRep: rep)!
let ctx = base.cgContext
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)            // układ współrzędnych od lewego górnego rogu
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func fill(_ r: CGRect, _ c: CGColor, radius: CGFloat = 0) {
    ctx.addPath(rounded(r, radius))
    ctx.setFillColor(c)
    ctx.fillPath()
}

func linearGradient(_ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func text(_ s: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight, color c: CGColor) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(cgColor: c)!,
    ]
    (s as NSString).draw(at: p, withAttributes: attrs)
}

func sparkle(center c: CGPoint, radius r: CGFloat, pinch: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let k = r * pinch
    p.move(to: CGPoint(x: c.x, y: c.y - r))
    p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + k, y: c.y - k))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + k, y: c.y + k))
    p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - k, y: c.y + k))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - k, y: c.y - k))
    p.closeSubpath()
    return p
}

// ── Tło: zaokrąglony kwadrat macOS, gradient grafit → indygo ──
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = rounded(body, 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(bodyPath)
ctx.setFillColor(color(0x2E3242))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
linearGradient([color(0x2F3345), color(0x3A3C7A), color(0x4F46E5)],
               from: CGPoint(x: 200, y: 100), to: CGPoint(x: 830, y: 924))
linearGradient([color(0xFFFFFF, 0.16), color(0xFFFFFF, 0)],
               from: CGPoint(x: 512, y: 100), to: CGPoint(x: 512, y: 560))
ctx.restoreGState()

// ── Kartka ──
let card = CGRect(x: 238, y: 206, width: 548, height: 628)
let cardPath = rounded(card, 46)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 44, color: color(0x0B0D1A, 0.55))
ctx.addPath(cardPath)
ctx.setFillColor(color(0xF7F8FC))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(cardPath)
ctx.clip()
fill(CGRect(x: card.minX, y: card.minY, width: card.width / 2, height: card.height), color(0x161925))
fill(CGRect(x: card.midX, y: card.minY, width: card.width / 2, height: card.height), color(0xF7F8FC))

// Lewa połowa: surowy Markdown
let lx: CGFloat = 276
text("#", at: CGPoint(x: lx - 4, y: 236), size: 112, weight: .heavy, color: color(0xA5B4FC))
fill(CGRect(x: lx + 78, y: 292, width: 96, height: 24), color(0xC7D2FE, 0.85), radius: 12)
fill(CGRect(x: lx, y: 388, width: 184, height: 16), color(0x4A5274), radius: 8)
fill(CGRect(x: lx, y: 424, width: 150, height: 16), color(0x4A5274), radius: 8)
fill(CGRect(x: lx, y: 490, width: 20, height: 12), color(0xF472B6), radius: 6)
fill(CGRect(x: lx + 34, y: 488, width: 136, height: 16), color(0x4A5274), radius: 8)
fill(CGRect(x: lx, y: 530, width: 20, height: 12), color(0xF472B6), radius: 6)
fill(CGRect(x: lx + 34, y: 528, width: 108, height: 16), color(0x4A5274), radius: 8)
text("```", at: CGPoint(x: lx - 2, y: 572), size: 46, weight: .bold, color: color(0x34D399))
fill(CGRect(x: lx + 22, y: 648, width: 132, height: 16), color(0x3B4262), radius: 8)
fill(CGRect(x: lx + 22, y: 684, width: 96, height: 16), color(0x3B4262), radius: 8)
text("```", at: CGPoint(x: lx - 2, y: 716), size: 46, weight: .bold, color: color(0x34D399))

// Prawa połowa: wyrenderowany podgląd
let rx: CGFloat = 548
fill(CGRect(x: rx, y: 270, width: 170, height: 38), color(0x1F2433), radius: 10)
fill(CGRect(x: rx, y: 344, width: 196, height: 14), color(0xC3C8D6), radius: 7)
fill(CGRect(x: rx, y: 372, width: 176, height: 14), color(0xC3C8D6), radius: 7)
fill(CGRect(x: rx, y: 400, width: 188, height: 14), color(0xC3C8D6), radius: 7)
ctx.setFillColor(color(0x6366F1))
ctx.fillEllipse(in: CGRect(x: rx + 2, y: 486, width: 16, height: 16))
fill(CGRect(x: rx + 32, y: 487, width: 140, height: 14), color(0xC3C8D6), radius: 7)
ctx.fillEllipse(in: CGRect(x: rx + 2, y: 526, width: 16, height: 16))
fill(CGRect(x: rx + 32, y: 527, width: 112, height: 14), color(0xC3C8D6), radius: 7)
fill(CGRect(x: rx, y: 590, width: 198, height: 176), color(0xE4E7F1), radius: 16)
fill(CGRect(x: rx + 22, y: 620, width: 92, height: 14), color(0x818CF8), radius: 7)
fill(CGRect(x: rx + 22, y: 652, width: 130, height: 14), color(0x9AA3C7), radius: 7)
fill(CGRect(x: rx + 22, y: 684, width: 72, height: 14), color(0x34D399), radius: 7)
fill(CGRect(x: rx + 22, y: 716, width: 112, height: 14), color(0x9AA3C7), radius: 7)

// Linia podziału
fill(CGRect(x: card.midX - 3, y: card.minY, width: 6, height: card.height), color(0x818CF8))
ctx.restoreGState()

// ── Iskra AI ──
func drawSparkle(_ c: CGPoint, _ r: CGFloat) {
    let path = sparkle(center: c, radius: r, pinch: 0.16)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: r * 0.55, color: color(0xA78BFA, 0.95))
    ctx.addPath(path)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    linearGradient([color(0xFFFFFF), color(0xDDD6FE), color(0xA5B4FC)],
                   from: CGPoint(x: c.x - r, y: c.y - r), to: CGPoint(x: c.x + r, y: c.y + r))
    ctx.restoreGState()
}
drawSparkle(CGPoint(x: 792, y: 214), 112)
drawSparkle(CGPoint(x: 868, y: 334), 36)

NSGraphicsContext.current = nil
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: outPath))
print("Zapisano \(outPath)")
