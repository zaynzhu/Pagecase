import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
  FileHandle.standardError.write(Data("用法：swift generate-icon.swift <输出 PNG>\n".utf8))
  exit(EXIT_FAILURE)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let pixelSize = 1024
let canvas = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)

guard let representation = NSBitmapImageRep(
  bitmapDataPlanes: nil,
  pixelsWide: pixelSize,
  pixelsHigh: pixelSize,
  bitsPerSample: 8,
  samplesPerPixel: 4,
  hasAlpha: true,
  isPlanar: false,
  colorSpaceName: .deviceRGB,
  bytesPerRow: 0,
  bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: representation) else {
  fatalError("无法创建图标画布")
}

representation.size = canvas.size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

let backgroundColor = NSColor(
  calibratedRed: 0.969,
  green: 0.965,
  blue: 0.953,
  alpha: 1
)
let inkColor = NSColor(
  calibratedRed: 0.184,
  green: 0.204,
  blue: 0.216,
  alpha: 1
)

backgroundColor.setFill()
NSBezierPath(roundedRect: canvas, xRadius: 220, yRadius: 220).fill()

let cabinetRect = NSRect(x: 202, y: 180, width: 620, height: 664)
let cabinet = NSBezierPath(roundedRect: cabinetRect, xRadius: 74, yRadius: 74)
cabinet.lineWidth = 28
inkColor.setStroke()
cabinet.stroke()

let divider = NSBezierPath()
divider.move(to: NSPoint(x: 216, y: 402))
divider.line(to: NSPoint(x: 808, y: 402))
divider.lineWidth = 24
divider.lineCapStyle = .round
divider.stroke()

inkColor.setFill()
let handle = NSBezierPath(
  roundedRect: NSRect(x: 417, y: 260, width: 190, height: 34),
  xRadius: 17,
  yRadius: 17
)
handle.fill()

let pageColors = [
  NSColor(calibratedRed: 0.33, green: 0.56, blue: 0.72, alpha: 1),
  NSColor(calibratedRed: 0.38, green: 0.61, blue: 0.43, alpha: 1),
  NSColor(calibratedRed: 0.78, green: 0.65, blue: 0.30, alpha: 1)
]
let pageHeights: [CGFloat] = [292, 346, 254]
let pageOrigins: [CGFloat] = [304, 438, 572]

for index in pageOrigins.indices {
  pageColors[index].setFill()
  NSBezierPath(
    roundedRect: NSRect(
      x: pageOrigins[index],
      y: 430,
      width: 100,
      height: pageHeights[index]
    ),
    xRadius: 24,
    yRadius: 24
  ).fill()
}

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = representation.representation(using: .png, properties: [:]) else {
  fatalError("无法编码图标")
}
try png.write(to: outputURL, options: .atomic)
