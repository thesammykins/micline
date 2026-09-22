#!/usr/bin/env swift

import AppKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 2 else {
    fail("usage: generate-dmg-background.swift OUTPUT.png")
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let width = 660
let height = 440

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fail("could not allocate image")
}

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fail("could not create graphics context")
}
NSGraphicsContext.current = context

let canvas = NSRect(x: 0, y: 0, width: width, height: height)
let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.035, green: 0.055, blue: 0.10, alpha: 1),
    ending: NSColor(calibratedRed: 0.075, green: 0.12, blue: 0.18, alpha: 1)
)
gradient?.draw(in: canvas, angle: -28)

// A restrained waveform makes the installer identifiable without competing
// with the two Finder icons placed over the left and right wells.
let waveform = NSBezierPath()
waveform.lineWidth = 2
let waveformColor = NSColor(calibratedRed: 0.20, green: 0.91, blue: 0.76, alpha: 0.22)
waveformColor.setStroke()
for x in stride(from: 24, through: width - 24, by: 5) {
    let phase = Double(x) / 27
    let envelope = 18 + 24 * exp(-pow((Double(x) - 330) / 190, 2))
    let y = 208 + sin(phase) * envelope + sin(phase * 0.43) * 8
    if x == 24 {
        waveform.move(to: NSPoint(x: x, y: Int(y)))
    } else {
        waveform.line(to: NSPoint(x: x, y: Int(y)))
    }
}
waveform.stroke()

// Finder controls native icon-label color. A single neutral rail gives both
// genuine labels enough contrast without imitating per-item buttons.
NSColor(calibratedWhite: 0.463, alpha: 1).setFill()
NSRect(x: 0, y: 126, width: width, height: 36).fill()

let wellColor = NSColor(calibratedWhite: 1, alpha: 0.055)
for centerX in [170, 490] {
    let well = NSBezierPath(roundedRect: NSRect(x: centerX - 68, y: 142, width: 136, height: 136), xRadius: 32, yRadius: 32)
    wellColor.setFill()
    well.fill()
}

let arrow = NSBezierPath()
arrow.lineWidth = 4
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 267, y: 210))
arrow.line(to: NSPoint(x: 393, y: 210))
arrow.move(to: NSPoint(x: 374, y: 228))
arrow.line(to: NSPoint(x: 393, y: 210))
arrow.line(to: NSPoint(x: 374, y: 192))
NSColor(calibratedRed: 0.32, green: 0.95, blue: 0.80, alpha: 0.90).setStroke()
arrow.stroke()

let centered = NSMutableParagraphStyle()
centered.alignment = .center
let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 32, weight: .bold),
    .foregroundColor: NSColor.white,
    .paragraphStyle: centered,
]
let instructionAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 17, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.92, alpha: 1),
    .paragraphStyle: centered,
]
let detailAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 12, weight: .regular),
    .foregroundColor: NSColor(calibratedWhite: 0.72, alpha: 1),
    .paragraphStyle: centered,
]

("MicLine" as NSString).draw(in: NSRect(x: 40, y: 350, width: 580, height: 44), withAttributes: titleAttributes)
("Drag MicLine to Applications" as NSString).draw(in: NSRect(x: 40, y: 310, width: 580, height: 28), withAttributes: instructionAttributes)
("Native microphone processing, installed locally" as NSString).draw(in: NSRect(x: 40, y: 38, width: 580, height: 20), withAttributes: detailAttributes)

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fail("could not encode PNG")
}

do {
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try png.write(to: outputURL, options: .atomic)
} catch {
    fail("could not write \(outputURL.path): \(error)")
}
