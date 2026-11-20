// Draws the Lookdown app icon: a formatted page (heading, text, a code block) on a warm squircle.
import AppKit

let size = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: NSColor) {
    c.setFill()
    NSBezierPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), xRadius: h / 2, yRadius: h / 2).fill()
}

// Background squircle: terracotta, lighter at the top.
let bgRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let bg = NSBezierPath(roundedRect: bgRect, xRadius: 185, yRadius: 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: NSColor.black.withAlphaComponent(0.3).cgColor)
color(0xB84E31).setFill()
bg.fill()
ctx.restoreGState()
ctx.saveGState()
bg.addClip()
NSGradient(colors: [color(0xEC8D66), color(0xCF5D3E), color(0xA9432A)])!.draw(in: bgRect, angle: -90)

// The page, with its top-right corner folded.
let x: CGFloat = 262, y: CGFloat = 196, w: CGFloat = 500, h: CGFloat = 632, r: CGFloat = 38, fold: CGFloat = 120
let page = NSBezierPath()
page.move(to: CGPoint(x: x + r, y: y))
page.appendArc(from: CGPoint(x: x + w, y: y), to: CGPoint(x: x + w, y: y + r), radius: r)
page.line(to: CGPoint(x: x + w, y: y + h - fold))
page.line(to: CGPoint(x: x + w - fold, y: y + h))
page.appendArc(from: CGPoint(x: x, y: y + h), to: CGPoint(x: x, y: y + h - r), radius: r)
page.appendArc(from: CGPoint(x: x, y: y), to: CGPoint(x: x + r, y: y), radius: r)
page.close()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: NSColor.black.withAlphaComponent(0.28).cgColor)
color(0xFAF8F2).setFill()
page.fill()
ctx.restoreGState()

let flap = NSBezierPath()
flap.move(to: CGPoint(x: x + w - fold, y: y + h))
flap.line(to: CGPoint(x: x + w - fold, y: y + h - fold + 22))
flap.appendArc(from: CGPoint(x: x + w - fold, y: y + h - fold), to: CGPoint(x: x + w - fold + 22, y: y + h - fold), radius: 22)
flap.line(to: CGPoint(x: x + w, y: y + h - fold))
flap.close()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: -6, height: -6), blur: 14, color: NSColor.black.withAlphaComponent(0.18).cgColor)
color(0xE6DED0).setFill()
flap.fill()
ctx.restoreGState()

// Heading, paragraph lines, and a dark code block with colored "tokens".
let left = x + 64
bar(left, y + h - 156, 262, 44, color(0x2C2A25))
let ink = color(0xCFC7B8)
bar(left, y + h - 236, 368, 22, ink)
bar(left, y + h - 284, 340, 22, ink)
bar(left, y + h - 332, 252, 22, ink)

let code = CGRect(x: left, y: y + 70, width: w - 128, height: 176)
color(0x2B2824).setFill()
NSBezierPath(roundedRect: code, xRadius: 24, yRadius: 24).fill()
bar(code.minX + 36, code.maxY - 58, 70, 20, color(0xF0937A))
bar(code.minX + 122, code.maxY - 58, 128, 20, color(0xA9CC8A))
bar(code.minX + 70, code.maxY - 102, 104, 20, color(0x8CC0EE))
bar(code.minX + 190, code.maxY - 102, 60, 20, color(0xE8B86D))
bar(code.minX + 36, code.maxY - 146, 54, 20, color(0x8A867C))

ctx.restoreGState()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
