import AppKit

let destination = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedRed: 0.12, green: 0.31, blue: 0.76, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 208, yRadius: 208).fill()
let text: NSString = "S"
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 650, weight: .medium), .foregroundColor: NSColor.white
]
let size = text.size(withAttributes: attributes)
text.draw(at: NSPoint(x: 435 - size.width / 2, y: 485 - size.height / 2), withAttributes: attributes)
NSColor(calibratedRed: 0.62, green: 0.85, blue: 1, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 697, y: 261, width: 34, height: 500), xRadius: 12, yRadius: 12).fill()
image.unlockFocus()
let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
try representation.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
