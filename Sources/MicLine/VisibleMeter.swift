import AppKit
import Combine
import SwiftUI
import MicLineCore

/// Closed SwiftUI windows can retain their views. Subscribe only while this
/// meter's window is visible, and read the latest levels when it returns.
struct VisibleMeter<Content: View>: View {
    let display: MeterDisplay
    @ViewBuilder var content: (MeterReadings) -> Content
    @State private var readings = MeterReadings.silence

    var body: some View {
        content(readings)
            .background(MeterVisibility(display: display, readings: $readings))
    }
}

private struct MeterVisibility: NSViewRepresentable {
    let display: MeterDisplay
    @Binding var readings: MeterReadings

    func makeNSView(context: Context) -> MeterVisibilityView { MeterVisibilityView() }

    func updateNSView(_ view: MeterVisibilityView, context: Context) {
        view.receive = { readings = $0 }
        if view.display !== display {
            view.display = display
        }
    }

    static func dismantleNSView(_ view: MeterVisibilityView, coordinator: ()) {
        view.display = nil
        view.receive = nil
        view.disconnect()
    }
}

final class MeterVisibilityView: NSView {
    var display: MeterDisplay? {
        didSet {
            if oldValue !== display {
                levels = nil
                updateAfterLayout()
            }
        }
    }
    var receive: ((MeterReadings) -> Void)?
    private var levels: AnyCancellable?
    private var visibility: AnyCancellable?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        disconnect()
        if let window {
            visibility = NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification, object: window)
                .sink { [weak self] _ in self?.updateAfterLayout() }
        }
        updateAfterLayout()
    }

    override func viewDidHide() { super.viewDidHide(); updateAfterLayout() }
    override func viewDidUnhide() { super.viewDidUnhide(); updateAfterLayout() }

    func updateAfterLayout() {
        // Attaching an NSView happens during SwiftUI layout; publishing the
        // initial reading synchronously would mutate state during that update.
        DispatchQueue.main.async { [weak self] in self?.updateSubscription() }
    }

    func disconnect() {
        levels = nil
        visibility = nil
    }

    private func updateSubscription() {
        guard let window, window.isVisible, window.occlusionState.contains(.visible),
              !isHiddenOrHasHiddenAncestor else {
            levels = nil
            return
        }
        guard levels == nil else { return }
        levels = display?.$readings.sink { [weak self] in self?.receive?($0) }
    }
}
