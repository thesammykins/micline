import AppKit
import SwiftUI
import MicLineCore

struct DiagnosticsView: View {
    @ObservedObject var graph: AudioGraph
    @Environment(\.dismiss) private var dismiss
    @State private var json = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Review Diagnostic Report").font(.title2.bold())
                    Text("Scroll to review the exact JSON that Export writes.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Label("The allowlist excludes device names, UIDs, paths, secrets, microphone audio and effect state. Capability tuples and public Audio Unit codes may still fingerprint your setup; this report is not anonymous.", systemImage: "exclamationmark.triangle.fill")
                .font(.callout).foregroundStyle(.orange)
                .padding(12).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            ScrollView([.horizontal, .vertical]) {
                Text(json).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red).font(.callout)
            }
            HStack {
                Button("Clear Logs") {
                    graph.diagnostics.clear()
                    refresh()
                }
                Text("Clear refreshes this exact preview; other report fields remain.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Export Reviewed JSON…") { export() }.buttonStyle(.borderedProminent)
                Button("Open GitHub Website…") {
                    if let url = graph.diagnosticReport().issueURL { NSWorkspace.shared.open(url) }
                }
            }
            Text("Export is local. Attaching the reviewed file and submitting an issue are separate manual actions.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24).frame(width: 760, height: 620)
        .task { refresh() }
    }

    private func refresh() {
        do {
            json = try graph.diagnosticReport().json()
            error = nil
        } catch {
            json = ""
            self.error = "Could not create the diagnostic preview: \(error.localizedDescription)"
        }
    }

    private func export() {
        guard !json.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "micline-diagnostics.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(json.utf8).write(to: url, options: .atomic)
            error = nil
        } catch {
            self.error = "Could not export the reviewed report: \(error.localizedDescription)"
        }
    }
}
