import SwiftUI
import MicLineCore

struct LevelMeterView: View {
    let title: String
    let reading: MeterReading

    private let ticks: [(Double, String)] = [
        (-90, "−90"), (-60, "−60"), (-36, "−36"), (-18, "−18"), (-9, "−9"), (0, "0 dBFS"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Text(title.uppercased()).fontWeight(.semibold)
                Spacer()
                Text("RMS \(formatted(reading.rmsDBFS)) dBFS")
                    .foregroundStyle(.secondary)
                Text("SAMPLE PEAK \(formatted(reading.samplePeakDBFS)) · HOLD \(formatted(reading.heldSamplePeakDBFS)) dBFS")
                    .foregroundStyle(.primary)
                Text("CLIP")
                    .fontWeight(.bold)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(reading.clipped ? Color.red : Color.secondary.opacity(0.35), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.white)
            }
            .font(.caption)
            .monospacedDigit()

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        Color.green.opacity(0.36).frame(width: proxy.size.width * 0.8)
                        Color.orange.opacity(0.42).frame(width: proxy.size.width * 0.1)
                        Color.red.opacity(0.42)
                    }
                    Rectangle()
                        .fill(Color.cyan)
                        .frame(width: proxy.size.width * position(reading.rmsDBFS), height: 12)
                        .padding(.vertical, 4)
                    marker(at: reading.samplePeakDBFS, width: 2, color: .white, proxy: proxy)
                    marker(at: reading.heldSamplePeakDBFS, width: 2, color: meterColor, proxy: proxy)
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .frame(height: 20)

            GeometryReader { proxy in
                ForEach(Array(ticks.enumerated()), id: \.offset) { _, tick in
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
        .accessibilityHint("RMS shows average signal energy. Sample peak shows the current highest sample, hold keeps a brief peak visible, and clip means a sample reached or exceeded 0 decibels full scale.")
        .help("RMS is average signal energy. Sample peak is the current highest sample; hold keeps a brief peak visible. dBFS measures level below digital maximum, and CLIP means a sample reached or exceeded 0 dBFS.")
    }

    private var meterColor: Color {
        switch reading.band {
        case .green: return .cyan
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
                .frame(width: width, height: 20)
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

    var body: some View {
        VStack(spacing: 18) {
            LevelMeterView(title: "Input", reading: input)
            LevelMeterView(title: "Output", reading: output)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .environment(\.colorScheme, .dark)
    }
}
