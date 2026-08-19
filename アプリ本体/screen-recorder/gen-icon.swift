import AppKit
let s: CGFloat = 1024
let img = NSImage(size: NSSize(width: s, height: s))
img.lockFocus()
NSColor.white.setFill(); NSRect(x: 0, y: 0, width: s, height: s).fill()
let r = NSRect(x: 112, y: 112, width: 800, height: 800)
NSColor(red: 0.9, green: 0.12, blue: 0.12, alpha: 1).setFill()
NSBezierPath(ovalIn: r).fill()
let t = NSAttributedString(string: "R", attributes: [
    .font: NSFont.systemFont(ofSize: 520, weight: .bold),
    .foregroundColor: NSColor.white])
let ts = t.size()
t.draw(in: NSRect(x: (s-ts.width)/2, y: (s-ts.height)/2-40, width: ts.width, height: ts.height))
img.unlockFocus()
let bmp = NSBitmapImageRep(cgImage: img.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
try! bmp.representation(using: .png, properties: [.compressionFactor: 1])!.write(to: URL(fileURLWithPath: "icon.png"))
