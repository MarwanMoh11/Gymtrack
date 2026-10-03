// Turns the iPhone app icon into a Mac one: the square artwork on a 1024
// canvas, inset and cut to the rounded square every Mac app icon uses. iOS
// rounds the corners itself; the Mac draws whatever it is given, and the
// square artwork would sit beside every other notification as a hard tile.
//
//   xcrun swift make-icon.swift <icon-1024.png> <out.png>
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3, let source = NSImage(contentsOfFile: arguments[1]) else {
    FileHandle.standardError.write(Data("usage: make-icon <icon-1024.png> <out.png>\n".utf8))
    exit(2)
}

let canvas = 1024
// The proportions of Apple's macOS icon template: an 824-point body with a
// 185-point corner radius, centred.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 185

guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas,
                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius).addClip()
source.draw(in: body)
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: arguments[2]))
