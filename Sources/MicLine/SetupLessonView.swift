import AVKit
import SwiftUI

enum SetupLesson: String {
    case welcome, permission, microphone, gain, isolation, compression, output, handoff, verify, ready
    var title: String {
        switch self {
        case .welcome: "Set up your microphone"
        case .permission: "Allow microphone access"
        case .microphone: "Find your microphone"
        case .gain: "Read the peak marker"
        case .isolation: "Try Apple's Sound Isolation"
        case .compression: "Try gentle compression"
        case .output: "Choose where processed audio goes"
        case .handoff: "Select MicLine's output in your call app"
        case .verify: "Check audio reaches your call app"
        case .ready: "Use your microphone day to day"
        }
    }
    var instructions: [String] {
        switch self {
        case .welcome: ["Check the microphone first.", "Try effects only if they help.", "Confirm your voice reaches your call app."]
        case .permission: ["Choose Allow Microphone in MicLine.", "Allow access in the macOS prompt.", "Listening starts only when you choose Start Sound Check."]
        case .microphone: ["Choose the microphone you speak into.", "For an interface, select the input where the mic is plugged in.", "If it's missing, reconnect it and check devices again."]
        case .gain: ["Speak normally, then try a louder sentence.", "Watch the peak marker; −18 to −6 dBFS is a starting range.", "If it clips, lower the mic's own gain or move farther away."]
        case .isolation: ["Choose headphones before listening.", "Speak, pause, then compare Before and With Sound Isolation.", "Keep it only if your voice still sounds natural."]
        case .compression: ["Try a quiet sentence followed by a louder one.", "Compare Before and With Compression at a comfortable volume.", "Keep or Undo. Louder doesn't always mean better."]
        case .output: ["Choose an installed virtual device as Processed output.", "Use the same channel pair in the receiving app if it offers a channel choice."]
        case .handoff: ["Open your call app's audio settings.", "Choose the virtual device shown here as its microphone; keep its speaker output on your headphones."]
        case .verify: ["Start Output Check sends your processed microphone to the selected virtual device.", "Speak and watch the input meter in your call app.", "Confirm reception here only after that meter responds."]
        case .ready: ["MicLine keeps your saved virtual route processing in the background. Use Pause microphone in the menu bar when you want capture off.", "Use Bypass to compare your effects with the original sound at the same gain.", "Use an effect's sliders button to adjust it. Adding or moving effects briefly pauses audio, then resumes it."]
        }
    }
    var videoHeight: CGFloat { 280 }
    var cues: [String] {
        switch self {
        case .welcome: ["Choose your microphone", "Check your level before effects", "Shape your sound, then connect your app"]
        case .permission: ["Allow microphone access in macOS", "This example already has access", "Listening starts when you choose a check"]
        case .microphone: ["Choose the physical microphone", "Select the channel it is connected to", "Confirm with Use This Microphone"]
        case .gain: ["Speak at your normal call volume", "Watch the peak marker", "Adjust the microphone gain or distance"]
        case .isolation: ["Use headphones when you listen", "Compare your existing sound", "Try Sound Isolation, then Keep or Undo"]
        case .compression: ["Try quiet and loud phrases", "Compare without the new compressor", "Keep it if the level sounds more even"]
        case .output: ["Choose an installed virtual output", "Keep track of the selected channel pair", "BlackHole is one option"]
        case .handoff: ["Match this device in your call app", "Use it as the call app microphone", "Keep speaker output on your headphones"]
        case .verify: ["Check the input meter in your call app", "MicLine cannot confirm reception for you", "Confirm only when that meter responds"]
        case .ready: ["Bypass compares effects at the same gain", "The sliders button opens each effect editor", "Processing continues while MicLine is open"]
        }
    }
    var recordingNote: String {
        switch self {
        case .gain: "Recorded meter example, not a target voice level. Your live reading will differ."
        case .isolation, .compression: "Controls demonstration with audio stopped. Choose headphones and Listen to compare your own voice."
        case .output: "BlackHole is the example shown. Choose the virtual device installed on your Mac."
        case .handoff: "The device name must match in both apps. Your call app's settings may look different."
        case .verify: "MicLine's meter shows audio leaving the chain. Check the receiving app's meter too."
        case .welcome: "Follow your voice from the microphone, through effects, to the output used by your call app."
        case .permission: "This example already has access. On first use, choose Allow Microphone and accept the macOS prompt."
        case .microphone: "An audio interface may have several inputs. Select the channel where your microphone is connected."
        case .ready: "Use Bypass to compare effects and the sliders button to adjust an effect. Closing the window keeps processing active."
        }
    }
}

struct SetupLessonView: View {
    let lesson: SetupLesson
    @Environment(\.dismiss) private var dismiss
    @State private var showsSteps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(lesson.title).font(.headline)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("Close guide")
            }
            if lesson.recordingURL != nil {
                SetupLessonMovie(lesson: lesson)
                    .frame(width: 504, height: lesson.videoHeight + 80)
                Text(lesson.recordingNote).font(.callout).foregroundStyle(.secondary)
                DisclosureGroup("Read the steps", isExpanded: $showsSteps) { instructions }
            } else { instructions }
        }
        .padding(20).frame(width: 544)
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(lesson.instructions.enumerated()), id: \.offset) { index, instruction in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).").foregroundStyle(.secondary)
                    Text(instruction).fixedSize(horizontal: false, vertical: true)
                }.font(.callout)
            }
        }.padding(.top, 6)
    }
}

extension SetupLesson {
    var recordingURL: URL? {
        Bundle.main.url(forResource: rawValue, withExtension: "mp4", subdirectory: "SetupLessons")
    }
}

struct SetupLessonMovie: View {
    let lesson: SetupLesson
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var timeObserver: Any?
    @State private var cueIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let player { LessonPlayerView(player: player) }
            else { Color.clear }
            HStack(spacing: 8) {
                Text("\(cueIndex + 1)/\(lesson.cues.count)").monospacedDigit().foregroundStyle(.secondary)
                Text(lesson.cues[cueIndex]).fontWeight(.medium)
            }.font(.callout).frame(height: 32)
        }
        .accessibilityLabel("Silent looping guide: \(lesson.title)")
        .task(id: lesson) {
            stop()
            guard let url = lesson.recordingURL else { return }
            let queue = AVQueuePlayer()
            queue.isMuted = true
            looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
            player = queue
            cueIndex = 0
            timeObserver = queue.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak queue] time in
                MainActor.assumeIsolated {
                    guard let queue, player === queue,
                          let duration = queue.currentItem?.duration.seconds,
                          duration.isFinite, duration > 0, time.seconds.isFinite else { return }
                    cueIndex = min(lesson.cues.count - 1, max(0, Int(time.seconds / duration * Double(lesson.cues.count))))
                }
            }
            if !reduceMotion { queue.play() }
        }
        .onChange(of: reduceMotion) { _, reduced in if reduced { player?.pause() } }
        .onDisappear(perform: stop)
    }

    private func stop() {
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        looper?.disableLooping()
        player?.removeAllItems()
        looper = nil
        player = nil
    }
}

// macOS 27's _AVKit_SwiftUI wrapper aborts while resolving superclass metadata
// on the tested host. Keep the native playback view behind this small bridge.
private struct LessonPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.showsFullScreenToggleButton = true
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) { view.player = player }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}
