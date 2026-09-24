import AppKit
import SwiftUI
import MicLineCore

struct ControlHelp: View {
    let title: String
    let explanation: String
    @State private var presented = false

    var body: some View {
        Button { presented.toggle() } label: { Image(systemName: "info.circle") }
            .buttonStyle(.borderless)
            .accessibilityLabel("About \(title)")
            .help(explanation)
            .popover(isPresented: $presented) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title).font(.headline)
                    Text(explanation).font(.callout).fixedSize(horizontal: false, vertical: true)
                }.padding(16).frame(width: 328)
            }
    }
}

struct GainDial: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    @State private var dragOrigin: Double?

    private var fraction: Double { (value - range.lowerBound) / max(0.5, range.upperBound - range.lowerBound) }
    private func adjust(_ next: Double) { value = min(range.upperBound, max(range.lowerBound, (next * 2).rounded() / 2)) }

    var body: some View {
        ZStack {
            Circle().fill(.quaternary)
                .overlay(Circle().stroke(.secondary.opacity(0.6), lineWidth: 1))
                .overlay(Circle().inset(by: 3).stroke(.primary.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.16), radius: 1, y: 1)
            Capsule().fill(Color.accentColor).frame(width: 2, height: 19)
                .offset(y: -13).rotationEffect(.degrees(-135 + fraction * 270))
        }
        .frame(width: 56, height: 56).contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { event in
            if dragOrigin == nil { dragOrigin = value }
            adjust((dragOrigin ?? value) - Double(event.translation.height) / 4)
        }.onEnded { _ in dragOrigin = nil })
        .focusable().onKeyPress(.upArrow) { adjust(value + 0.5); return .handled }
        .onKeyPress(.downArrow) { adjust(value - 0.5); return .handled }
        .onKeyPress(.rightArrow) { adjust(value + 0.5); return .handled }
        .onKeyPress(.leftArrow) { adjust(value - 0.5); return .handled }
        .accessibilityElement().accessibilityLabel("Gain")
        .accessibilityValue("\(value.formatted()) decibels")
        .accessibilityAdjustableAction { direction in adjust(value + (direction == .increment ? 0.5 : -0.5)) }
        .help("Drag up or down to change gain. Use arrow keys for half-decibel changes, or enter an exact value above.")
    }
}

struct LowCutHelp: View {
    @ObservedObject var graph: AudioGraph
    var allowsMonitoring = true
    @State private var presented = false

    var body: some View {
        Button { presented.toggle() } label: { Image(systemName: "info.circle") }
            .buttonStyle(.borderless).accessibilityLabel("About Low cut")
            .help("Learn about low cut and compare it with your voice.")
            .popover(isPresented: $presented) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Reduce low rumble").font(.headline)
                    Text("Reduces low-frequency sound such as desk vibration. If your voice sounds thin, lower the cutoff or turn it off.")
                        .font(.callout)
                    Divider()
                    Text("Compare this filter").font(.callout)
                    HStack {
                        Picker("Low cut", selection: $graph.settings.highPassEnabled) {
                            Text("Off").tag(false); Text("On").tag(true)
                        }.pickerStyle(.segmented).labelsHidden()
                        MonitorButton(graph: graph, allowsMonitoring: allowsMonitoring)
                    }
                    Text(graph.bypass ? "Effects are bypassed. Turn Bypass off to hear the filter." : "Listening requires your confirmed headphone output. Changes also affect the processed output.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(16).frame(width: 328)
            }
    }
}

struct ControlPreferences: View {
    @ObservedObject var graph: AudioGraph
    @AppStorage("gainControlStyle") private var style = "dial"
    @AppStorage("compactMode") private var compact = false
    @AppStorage("colourMenuMeter") private var colour = true
    @State private var error: String?

    var body: some View {
        Section("Controls") {
            Picker("Gain control", selection: $style) { Text("Dial").tag("dial"); Text("Slider").tag("slider") }
            TextField("Minimum gain (dB)", value: bound(lower: true), format: .number)
            TextField("Maximum gain (dB)", value: bound(lower: false), format: .number)
            Text("Choose limits within −24…+12 dB that include zero and the current gain.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            Toggle("Compact window", isOn: $compact)
            Toggle("Coloured menu-bar meter", isOn: $colour)
        }
    }

    private func bound(lower: Bool) -> Binding<Double> {
        Binding(get: { lower ? graph.settings.gainRange.lowerBound : graph.settings.gainRange.upperBound }, set: { value in
            let minimum = lower ? value : graph.settings.gainRange.lowerBound
            let maximum = lower ? graph.settings.gainRange.upperBound : value
            guard value.isFinite, minimum >= -24, minimum <= 0, maximum >= 0, maximum <= 12,
                  minimum < maximum, (minimum...maximum).contains(graph.settings.gainDB) else {
                error = "Keep the range within −24…+12 dB and include zero and your current gain. The sound has not changed."
                return
            }
            error = nil
            graph.settings.minimumGainDB = minimum
            graph.settings.maximumGainDB = maximum
        })
    }
}

// SwiftUI's content-size constraint snaps the window before its contents animate.
// Resize the native frame from its top edge while SwiftUI lays out the controls.
struct MainWindowSize: NSViewRepresentable {
    let height: CGFloat
    let reduceMotion: Bool

    func makeNSView(context: Context) -> WindowSizeView { WindowSizeView() }
    func updateNSView(_ view: WindowSizeView, context: Context) {
        view.targetHeight = height
        view.reduceMotion = reduceMotion
        view.resizeWindow()
    }

    final class WindowSizeView: NSView {
        var targetHeight: CGFloat = 680
        var reduceMotion = false
        private var appliedHeight: CGFloat?

        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); resizeWindow() }

        func resizeWindow() {
            guard let window, appliedHeight != targetHeight else { return }
            let initial = appliedHeight == nil
            appliedHeight = targetHeight
            window.styleMask.remove(.resizable)
            let content = NSRect(x: 0, y: 0, width: 720, height: targetHeight)
            let size = window.frameRect(forContentRect: content).size
            let frame = NSRect(x: window.frame.minX, y: window.frame.maxY - size.height,
                               width: size.width, height: size.height)
            if initial || reduceMotion {
                window.setFrame(frame, display: true)
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.35
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().setFrame(frame, display: true)
                }
            }
        }
    }
}
