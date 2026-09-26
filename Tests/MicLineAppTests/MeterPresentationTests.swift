import AppKit
import Combine
import Testing
@testable import MicLine
@testable import MicLineCore

@Suite(.serialized) @MainActor
struct MeterPresentationTests {
    @Test func menuMeterKeepsExactSegmentBoundariesAndIgnoresInvisibleChanges() {
        let thresholds = [-60.0, -48, -36, -24, -18, -12, -9, -3]
        for (index, threshold) in thresholds.enumerated() {
            #expect(MenuBarMeterReading(threshold - 0.01).segments == index)
            #expect(MenuBarMeterReading(threshold).segments == index + 1)
        }
        #expect(MenuBarMeterReading(-41.2) == MenuBarMeterReading(-41.8))
        #expect(MenuBarMeterReading(-41.2).rmsDBFS == -41)
        #expect(MenuBarMeterReading(-90).segments == 0)
        #expect(MenuBarMeterReading(3).segments == 8)
    }

    @Test func menuImagesAreReusedAndOldAppearanceIsReleased() {
        let cache = MenuBarMeterImages()
        weak var previousAppearance: NSImage?
        autoreleasepool {
            let image = cache.image(segments: 3, running: true, colour: true, dark: true)
            previousAppearance = image
            #expect(cache.image(segments: 3, running: true, colour: true, dark: true) === image)
            #expect(cache.image(segments: 4, running: true, colour: true, dark: true) !== image)
            #expect(!image.isTemplate)
            #expect(image.size == NSSize(width: 52, height: 18))
        }
        let mono = cache.image(segments: 3, running: true, colour: false, dark: false)
        #expect(mono.isTemplate)
        #expect(previousAppearance == nil)
        #expect(cache.image(segments: 0, running: false, colour: false, dark: false)
            !== cache.image(segments: 0, running: true, colour: false, dark: false))
    }

    @Test func hiddenMeterStopsUpdatesAndReopeningGetsLatestReading() async throws {
        _ = NSApplication.shared
        let window = MeterTestWindow(contentRect: NSRect(x: 100, y: 100, width: 160, height: 50),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let display = MeterDisplay()
        let view = MeterVisibilityView()
        view.display = display
        var received: [MeterReadings] = []
        view.receive = { received.append($0) }
        window.contentView = view
        defer { view.disconnect(); window.close() }

        window.setVisible(true)
        try await Task.sleep(for: .milliseconds(150))
        #expect(received.last == .silence)
        window.setVisible(false)
        try await Task.sleep(for: .milliseconds(150))
        let count = received.count
        let reading = MeterReading(rmsDBFS: -12, samplePeakDBFS: -6, heldSamplePeakDBFS: -3, clipped: false)
        let latest = MeterReadings(input: reading, output: reading, inputSignalMissing: false)
        display.update(latest)
        #expect(received.count == count)

        window.setVisible(true)
        try await Task.sleep(for: .milliseconds(150))
        #expect(received.last == latest)
        view.removeFromSuperview()
        try await Task.sleep(for: .milliseconds(50))
        let detachedCount = received.count
        display.update(.silence)
        #expect(received.count == detachedCount)
    }
}

/// Model AppKit's visibility notifications without depending on the user's
/// current Space or another application covering the test window.
@MainActor private final class MeterTestWindow: NSWindow {
    private var fixtureVisible = false
    override var isVisible: Bool { fixtureVisible }
    override var occlusionState: OcclusionState { fixtureVisible ? [.visible] : [] }

    func setVisible(_ visible: Bool) {
        self.fixtureVisible = visible
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: self)
    }
}
