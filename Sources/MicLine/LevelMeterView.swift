import SwiftUI
import MicLineCore

struct LevelMeterView: View {
    let title: String
    let reading: MeterReading
    var compact = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let ticks: [(Double, String)] = [
        (-90, "−90"), (-60, "−60"), (-36, "−36"), (-18, "−18"), (-9, "−9"), (0, "0 dBFS"),
    ]
    private let helpText = "RMS shows average level calibrated to a full-scale sine wave. Peak measures samples, not true peak; hold keeps brief peaks visible. dBFS means decibels full scale. CLIP means a sample reached or exceeded 0 dBFS."

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Text(title.uppercased()).fontWeight(.semibold)
                Spacer()
                Text(compact ? "PEAK \(formatted(reading.samplePeakDBFS)) dBFS" : "RMS \(formatted(reading.rmsDBFS)) dBFS")
                    .foregroundStyle(.secondary)
                if !compact { Text("SAMPLE PEAK \(formatted(reading.samplePeakDBFS)) · HOLD \(formatted(reading.heldSamplePeakDBFS)) dBFS")
                    .foregroundStyle(.primary) }
                Text("CLIP")
                    .fontWeight(.bold)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(reading.clipped ? Color.red : Color.secondary.opacity(0.35), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.white)
                    .opacity(reading.clipped ? 1 : 0)
            }
            .font(.caption)
            .monospacedDigit()

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    LinearGradient(stops: [
                        .init(color: .green, location: 0),
                        .init(color: .green, location: 0.8),
                        .init(color: .orange, location: 0.8),
                        .init(color: .orange, location: 0.9),
                        .init(color: .red, location: 0.9),
                        .init(color: .red, location: 1)
                    ], startPoint: .leading, endPoint: .trailing)
                    .overlay(alignment: .top) {
                        if !reduceTransparency {
                            Capsule().fill(.white.opacity(0.16)).frame(height: 4).padding(2)
                        }
                    }
                    .mask(alignment: .leading) {
                        Capsule().frame(width: proxy.size.width * position(reading.rmsDBFS))
                    }
                    marker(at: reading.samplePeakDBFS, width: 2, color: .white, proxy: proxy)
                    marker(at: reading.heldSamplePeakDBFS, width: 2, color: meterColor, proxy: proxy)
                }
                .clipShape(Capsule())
            }
            .frame(height: 18)

            GeometryReader { proxy in
                ForEach(Array((compact ? ticks.filter { [-90.0, -36.0, 0.0].contains($0.0) } : ticks).enumerated()), id: \.offset) { _, tick in
                    Text(tick.1)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(tick.0 >= -9 ? Color.red : tick.0 >= -18 ? Color.orange : Color.secondary)
                        .position(x: tickX(tick.0, width: proxy.size.width), y: 7)
                }
            }
            .frame(height: 14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) level")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(helpText)
        .help(helpText)
    }

    private var meterColor: Color {
        switch reading.band {
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        }
    }

    private var accessibilityValue: String {
        let clip = reading.clipped ? ", clipping detected" : ""
        return "RMS \(spoken(reading.rmsDBFS)), sample peak \(spoken(reading.samplePeakDBFS)), held peak \(spoken(reading.heldSamplePeakDBFS)) decibels full scale\(clip)"
    }

    private func position(_ db: Double) -> Double {
        min(1, max(0, (db + 90) / 90))
    }

    private func tickX(_ db: Double, width: Double) -> Double {
        let raw = width * position(db)
        if db == -90 { return 10 }
        if db == 0 { return width - 20 }
        return raw
    }

    @ViewBuilder
    private func marker(at db: Double, width: Double, color: Color, proxy: GeometryProxy) -> some View {
        if db > -90 {
            Rectangle()
                .fill(color)
                .frame(width: width, height: 18)
                .offset(x: max(0, min(proxy.size.width - width, proxy.size.width * position(db))))
        }
    }

    private func formatted(_ db: Double) -> String {
        db <= -90 ? "−∞" : String(format: "%.1f", db)
    }

    private func spoken(_ db: Double) -> String {
        db <= -90 ? "silent" : String(format: "%.1f", db)
    }
}

struct MeterPanel: View {
    let input: MeterReading
    let output: MeterReading
    var compact = false

    var body: some View {
        VStack(spacing: 18) {
            LevelMeterView(title: "Input", reading: input, compact: compact)
            LevelMeterView(title: "Output", reading: output, compact: compact)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .environment(\.colorScheme, .dark)
    }
}

struct LiveMeterPanel: View {
    @ObservedObject var display: MeterDisplay
    var compact = false

    var body: some View {
        MeterPanel(input: display.readings.input, output: display.readings.output, compact: compact)
    }
}

struct MeterSignalWarning: View {
    @ObservedObject var display: MeterDisplay
    let running: Bool

    var body: some View {
        if running && display.readings.inputSignalMissing {
            Label("No input signal. Check the microphone's mute switch and selected channel. If using a MacBook microphone, open the lid.", systemImage: "mic.slash")
                .font(.callout).foregroundStyle(.orange)
        }
    }
}

struct MenuOutputMeter: View {
    @ObservedObject var display: MeterDisplay
    var body: some View {
        LevelMeterView(title: "Output", reading: display.readings.output, compact: true)
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
    }
}
