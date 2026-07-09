import AppKit
import SwiftUI

/// Floating pill at the bottom-center of the screen showing recording state,
/// live waveform bars, and the partial transcript — like Wispr Flow's bar.
final class OverlayController {
    private var panel: NSPanel?

    func show(command: Bool = false) {
        DispatchQueue.main.async { [self] in
            OverlayModel.shared.mode = command ? .command : .recording
            if panel == nil { panel = makePanel() }
            position()
            panel?.orderFrontRegardless()
        }
    }

    func setHandsFree(_ on: Bool) {
        DispatchQueue.main.async {
            if on { OverlayModel.shared.mode = .handsFree }
        }
    }

    func setProcessing() {
        DispatchQueue.main.async { OverlayModel.shared.mode = .processing }
    }

    func hide() {
        DispatchQueue.main.async { [self] in
            panel?.orderOut(nil)
        }
    }

    /// Briefly show an error message in place of the usual recording pill,
    /// then auto-hide. Used when AI formatting or Command Mode fails so the
    /// failure isn't silent.
    func showError(_ message: String) {
        DispatchQueue.main.async { [self] in
            OverlayModel.shared.mode = .error(message)
            if panel == nil { panel = makePanel() }
            position()
            panel?.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self, OverlayModel.shared.mode == .error(message) else { return }
                self.panel?.orderOut(nil)
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: OverlayView())
        return panel
    }

    private func position() {
        guard let panel, let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.minY + 24))
    }
}

enum OverlayMode: Equatable { case recording, handsFree, processing, command, error(String) }

final class OverlayModel: ObservableObject {
    static let shared = OverlayModel()
    @Published var mode: OverlayMode = .recording
}

struct OverlayView: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject var model = OverlayModel.shared

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                switch model.mode {
                case .processing:
                    ProgressView().controlSize(.small)
                    Text("Formatting…").font(.callout).foregroundStyle(.white)
                case .error(let message):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(message).font(.callout).foregroundStyle(.white)
                case .recording, .handsFree, .command:
                    Image(systemName: model.mode == .command ? "wand.and.stars" : "mic.fill")
                        .foregroundStyle(model.mode == .command ? .purple
                                         : model.mode == .handsFree ? .orange : .red)
                    WaveformView(bands: state.audioBands)
                    if model.mode == .handsFree {
                        Text("hands-free").font(.caption2).foregroundStyle(.white.opacity(0.7))
                    } else if model.mode == .command {
                        Text("command").font(.caption2).foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.black.opacity(0.85)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.15)))
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }
}

/// White bars, one per frequency-domain-ish band of the live mic buffer.
struct WaveformView: View {
    var bands: [Float]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(bands.indices, id: \.self) { i in
                Capsule()
                    .fill(Color.white)
                    .frame(width: 3, height: max(3, CGFloat(bands[i]) * 21 + 3))
            }
        }
        .frame(height: 24)
        .animation(.linear(duration: 0.08), value: bands)
    }
}
