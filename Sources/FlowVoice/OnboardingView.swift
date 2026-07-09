import SwiftUI
import AVFoundation
import Speech

/// First-run setup: walks the three required permissions with live status,
/// then a "try it" step. Shown automatically when anything is missing.
enum OnboardingWindow {
    private static var window: NSWindow?

    static var allPermissionsGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            && SFSpeechRecognizer.authorizationStatus() == .authorized
            && Paster.hasAccessibilityPermission
    }

    static func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            w.title = "Welcome to FlowVoice"
            w.isReleasedWhenClosed = false
            w.center()
            w.contentView = NSHostingView(rootView: OnboardingView())
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    static func close() {
        window?.close()
    }
}

struct OnboardingView: View {
    @State private var micGranted = false
    @State private var speechGranted = false
    @State private var axGranted = false
    @State private var didScheduleClose = false
    @ObservedObject var state = AppState.shared

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Theme.accent)
                Text("Speak. It types.")
                    .font(.system(.title, design: .rounded).weight(.bold))
                Text("Three permissions and you're dictating into any app on your Mac.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 28)
            .padding(.horizontal, 32)

            VStack(spacing: 12) {
                PermissionRow(
                    granted: micGranted,
                    icon: "mic.fill",
                    title: "Microphone",
                    detail: "Records your voice while you hold the hotkey.",
                    action: "Allow"
                ) {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in refresh() }
                }
                PermissionRow(
                    granted: speechGranted,
                    icon: "text.bubble.fill",
                    title: "Speech Recognition",
                    detail: "Turns your voice into text — on this Mac, not in the cloud.",
                    action: "Allow"
                ) {
                    SFSpeechRecognizer.requestAuthorization { _ in
                        DispatchQueue.main.async { refresh() }
                    }
                }
                PermissionRow(
                    granted: axGranted,
                    icon: "accessibility",
                    title: "Accessibility",
                    detail: "Lets the hotkey work everywhere and pastes text for you. macOS makes you flip this one on yourself.",
                    action: "Open Settings"
                ) {
                    Paster.promptForAccessibility()
                }
            }
            .padding(24)

            Divider()

            VStack(spacing: 8) {
                if OnboardingWindow.allPermissionsGranted {
                    Label("You're set", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.accent)
                    Text("Click into any text field, hold **\(state.hotkey.label)**, and say something. Release — your words appear.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Grant the items above — this list updates live.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .frame(width: 480)
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in refresh() }
    }

    private func refresh() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        axGranted = Paster.hasAccessibilityPermission
        // Once everything is granted, let the user read "You're set" briefly,
        // then close the window automatically instead of leaving it open.
        if OnboardingWindow.allPermissionsGranted, !didScheduleClose {
            didScheduleClose = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                OnboardingWindow.close()
            }
        }
    }
}

struct PermissionRow: View {
    let granted: Bool
    let icon: String
    let title: String
    let detail: String
    let action: String
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : icon)
                .font(.title3)
                .foregroundStyle(granted ? .green : Theme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button(action, action: onAction)
            }
        }
        .padding(12)
        .background(granted ? Color.green.opacity(0.08) : Theme.accentSoft,
                    in: RoundedRectangle(cornerRadius: 10))
    }
}
