import AppKit

@MainActor
struct MenuBarMeterReading: Equatable {
    static let thresholds: [Double] = [-60, -48, -36, -24, -18, -12, -9, -3]
    let rmsDBFS: Int
    let segments: Int

    init(_ db: Double) {
        rmsDBFS = Int(db)
        segments = Self.thresholds.prefix { db >= $0 }.count
    }
}

@MainActor
final class MenuBarMeterImages {
    private var appearance: (colour: Bool, dark: Bool)?
    private var images: [Int: NSImage] = [:]

    func image(segments: Int, running: Bool, colour: Bool, dark: Bool) -> NSImage {
        if appearance?.colour != colour || appearance?.dark != dark {
            images.removeAll(keepingCapacity: true)
            appearance = (colour, dark)
        }
        let key = running ? segments : -1
        if let image = images[key] { return image }
        // At most nine active images plus the stopped image for one appearance.
        // Stable NSImage identities let AppKit reuse its rendered representations.
        let symbol = running ? "mic.fill" : "mic.slash"
        let foreground: NSColor = colour ? (dark ? .white : .black) : .black
        let coloured = colour
        let image = NSImage(size: NSSize(width: 52, height: 18), flipped: false) { _ in
            if let mic = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(paletteColors: [foreground])) {
                mic.draw(in: NSRect(x: 0, y: 1, width: 13, height: 16))
            }
            for (index, threshold) in MenuBarMeterReading.thresholds.enumerated() {
                let lit = running && index < segments
                let zone: NSColor = threshold >= -9 ? .systemRed : threshold >= -18 ? .systemOrange : .systemGreen
                (lit ? (coloured ? zone : foreground) : foreground.withAlphaComponent(0.24)).setFill()
                NSBezierPath(roundedRect: NSRect(x: 18 + CGFloat(index) * 4,
                    y: 4, width: 2.5, height: 10), xRadius: 1.25, yRadius: 1.25).fill()
            }
            return true
        }
        image.isTemplate = !colour
        images[key] = image
        return image
    }
}
