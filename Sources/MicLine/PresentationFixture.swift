import AppKit
import AudioToolbox
import Foundation
import SwiftUI
import MicLineCore

/// Explicitly gated, non-audio states for visual and accessibility verification.
/// They never read live graph state and use a separate UserDefaults suite at launch.
enum PresentationFixture: String {
    case active
    case clipped
    case held
    case delayed
    case stopped
    case effects
    case recovery
    case onboarding
    case measurement
    case genericControls = "generic-controls"
    case largeText = "large-text"

    static var current: PresentationFixture? {
        guard ProcessInfo.processInfo.environment["MICLINE_PRESENTATION_FIXTURES"] == "1",
              let index = CommandLine.arguments.firstIndex(of: "--presentation-fixture"),
              CommandLine.arguments.indices.contains(index + 1) else { return nil }
        return PresentationFixture(rawValue: CommandLine.arguments[index + 1])
    }
}

/// These wrappers exercise the production views while preventing every control
/// from handling input. The app also supplies the presentation-only defaults
/// suite, so merely rendering them cannot change normal preferences.
struct ProductionOnboardingFixtureView: View {
    @ObservedObject var graph: AudioGraph
    @State private var presented = true
    @State private var completed = false

    var body: some View {
        fixtureSurface {
            OnboardingView(graph: graph, isPresented: $presented, completedSetup: $completed, height: 840)
        }
    }
}

struct ProductionMeasurementFixtureView: View {
    @ObservedObject var graph: AudioGraph

    var body: some View {
        fixtureSurface {
            MeasurementView(graph: graph, openAudioSetup: {})
        }
    }
}

struct ProductionGenericControlsFixtureView: View {
    @ObservedObject var graph: AudioGraph

    private let parameters: [AUParameter] = {
        let threshold = AUParameterTree.createParameter(
            withIdentifier: "threshold",
            name: "Threshold",
            address: 1,
            min: -60,
            max: 0,
            unit: .customUnit,
            unitName: "dB",
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil,
            dependentParameters: nil
        )
        threshold.value = -12.5
        let response = AUParameterTree.createParameter(
            withIdentifier: "response",
            name: "Response",
            address: 2,
            min: -20,
            max: -1,
            unit: .customUnit,
            unitName: "units",
            flags: [.flag_IsReadable, .flag_IsWritable, .flag_DisplayExponential],
            valueStrings: nil,
            dependentParameters: nil
        )
        response.value = -8
        return [threshold, response]
    }()

    var body: some View {
        fixtureSurface {
            GenericAUControlsView(graph: graph, presentedParameters: parameters)
                .padding(.top, 40)
        }
    }
}

private func fixtureSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    ZStack(alignment: .top) {
        content().disabled(true).allowsHitTesting(false)
        Label("PRODUCTION LAYOUT FIXTURE · AUDIO DISABLED", systemImage: "paintbrush.pointed")
            .font(.caption.bold()).foregroundStyle(.purple)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, 8)
    }
}

struct PresentationFixtureView: View {
    let fixture: PresentationFixture

    private var input: MeterReading {
        switch fixture {
        case .clipped: return MeterReading(rmsDBFS: -4.5, samplePeakDBFS: 0, heldSamplePeakDBFS: 0, clipped: true)
        case .held: return MeterReading(rmsDBFS: -32, samplePeakDBFS: -28, heldSamplePeakDBFS: -7.5, clipped: false)
        case .delayed: return MeterReading(rmsDBFS: -34, samplePeakDBFS: -13, heldSamplePeakDBFS: -7.5, clipped: false)
        case .stopped, .recovery: return .silence
        default: return MeterReading(rmsDBFS: -20.6, samplePeakDBFS: -8.2, heldSamplePeakDBFS: -7.9, clipped: false)
        }
    }

    private var output: MeterReading {
        switch fixture {
        case .clipped: return MeterReading(rmsDBFS: -2.8, samplePeakDBFS: 0.2, heldSamplePeakDBFS: 0.2, clipped: true)
        case .held: return MeterReading(rmsDBFS: -40, samplePeakDBFS: -33, heldSamplePeakDBFS: -6.4, clipped: false)
        case .delayed: return MeterReading(rmsDBFS: -26, samplePeakDBFS: -11, heldSamplePeakDBFS: -6.4, clipped: false)
        case .stopped, .recovery: return .silence
        default: return MeterReading(rmsDBFS: -17.4, samplePeakDBFS: -6.7, heldSamplePeakDBFS: -6.4, clipped: false)
        }
    }

    private var isRunning: Bool { fixture != .stopped && fixture != .recovery }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("PRESENTATION FIXTURE · NO AUDIO", systemImage: "paintbrush.pointed")
                    .font(.caption.bold()).foregroundStyle(.purple)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.purple.opacity(0.10), in: Capsule())
                HStack {
                    Text("ROUTE").font(.headline).foregroundStyle(.secondary)
                    Spacer()
                    Label(isRunning ? "Processing" : "Stopped", systemImage: isRunning ? "circle.fill" : "circle")
                        .foregroundStyle(isRunning ? .green : .secondary)
                    Button(isRunning ? "Stop" : "Start") {}
                        .buttonStyle(.borderedProminent).tint(isRunning ? .red : .accentColor)
                }
                HStack(spacing: 12) {
                    fixtureRoute(title: "MICROPHONE", icon: "mic", value: "Studio Microphone")
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    fixtureRoute(title: "PROCESSED OUTPUT", icon: "waveform", value: fixture == .recovery ? "Output unavailable" : "BlackHole 2ch")
                    Button {} label: { Image(systemName: "ear").frame(width: 28, height: 28) }
                        .buttonStyle(.bordered).controlSize(.large).disabled(fixture == .recovery)
                }
                .padding(12).background(.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
                MeterPanel(input: input, output: output)
                fixtureControls
                if fixture == .recovery {
                    Label("Audio configuration changed. Check devices in Audio Setup, then start again.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else if fixture == .delayed {
                    Label("Delayed/coalesced UI update: current peaks and the previous brief held peak remain distinguishable.", systemImage: "clock")
                        .font(.callout).foregroundStyle(.secondary)
                } else if fixture == .stopped {
                    Text("Processing stopped. Meter state is reset before the next start.").foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 700, minHeight: 580)
        .environment(\.dynamicTypeSize, fixture == .largeText ? .accessibility2 : .large)
    }

    private func fixtureRoute(title: String, icon: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.green).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption2).fontWeight(.semibold).foregroundStyle(.secondary)
                Text(value).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.down").foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }

    private var fixtureControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Gain")
                Slider(value: .constant(-12), in: -24...12).disabled(true)
                Text("−12.0 dB").monospacedDigit()
                Button("Reset") {}
            }
            HStack {
                Toggle("Low cut", isOn: .constant(true)).toggleStyle(.switch)
                Spacer()
                Text("80 Hz").monospacedDigit()
                Button("Reset") {}
            }
            Divider()
            HStack {
                Text("EFFECTS · TOP TO BOTTOM").font(.headline).foregroundStyle(.secondary)
                Spacer()
                Toggle("Bypass", isOn: .constant(false)).toggleStyle(.switch)
            }
            HStack {
                Text("01").foregroundStyle(.secondary)
                VStack(alignment: .leading) {
                    Text("Dynamics Compressor")
                    Text("Audio Unit · Enabled").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Enabled", isOn: .constant(true)).labelsHidden().toggleStyle(.switch)
                Button("Controls") {}
            }
        }
        .padding(16).background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
    }
}

/// The stopped fixture renders the production MainView itself. Audio actions are
/// disabled and its graph uses the isolated presentation preferences suite.
struct ProductionStoppedFixtureView: View {
    @ObservedObject var graph: AudioGraph

    var body: some View {
        MainView(graph: graph, allowsAudioActions: false, showsOnboarding: false)
            .safeAreaInset(edge: .top) {
                Label("PRODUCTION LAYOUT FIXTURE · NO AUDIO", systemImage: "paintbrush.pointed")
                    .font(.caption.bold()).foregroundStyle(.purple)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
            }
    }
}

/// A configured production MainView for pointer, keyboard, VoiceOver, and drag
/// verification. It writes only to the presentation UserDefaults suite and
/// leaves every audio-starting action disabled.
struct ProductionEffectsFixtureView: View {
    @ObservedObject var graph: AudioGraph
    @State private var seeded = false

    var body: some View {
        MainView(graph: graph, allowsAudioActions: false, showsOnboarding: false)
            .safeAreaInset(edge: .top) {
                Label("PRODUCTION EFFECTS FIXTURE · AUDIO DISABLED", systemImage: "paintbrush.pointed")
                    .font(.caption.bold()).foregroundStyle(.purple)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
            }
            .task {
                guard !seeded else { return }
                seeded = true
                graph.settings.effects = graph.plugins.filter(\.hostable)
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    .prefix(3)
                    .map { EffectSelection(pluginID: $0.id) }
            }
    }
}

struct FixtureSettingsUnavailableView: View {
    var body: some View {
        ContentUnavailableView("Settings unavailable in presentation fixtures",
            systemImage: "paintbrush.pointed",
            description: Text("This non-audio launch cannot change normal MicLine preferences or start audio."))
            .frame(width: 480, height: 320)
    }
}

struct FixtureMenuView: View {
    var body: some View {
        Text("Presentation fixture · no audio")
        Text("Processing controls and Settings are unavailable")
            .foregroundStyle(.secondary)
        Divider()
        Button("Quit MicLine") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
