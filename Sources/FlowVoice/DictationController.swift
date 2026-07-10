import AppKit

/// Orchestrates the dictation lifecycle: hotkey press -> record -> release ->
/// transcribe -> format (LLM or rules) -> paste. Also implements hands-free
/// mode (double-tap) and Command Mode (voice-edit selected text).
final class DictationController {
    private let state = AppState.shared
    private let transcriber = SpeechTranscriber()
    private let monitor = HotkeyMonitor()
    private let overlay = OverlayController()

    private enum Mode { case dictation, command }
    private var activeMode: Mode = .dictation

    private var keyDownTime: Date?
    private var lastTapEndTime: Date?
    /// A release quicker than this is treated as a tap (double-tap → hands-free,
    /// single tap → cancel) rather than a real dictation. Kept short so a
    /// brief-but-intentional "hold to dictate a word" still pastes instead of
    /// being swallowed as a tap. A genuine double-tap is two presses well under
    /// this each, so the gesture still registers.
    private let tapMaxDuration: TimeInterval = 0.25
    private let doubleTapWindow: TimeInterval = 0.5

    func start() {
        transcriber.onPartial = { [weak self] text in
            self?.state.liveTranscript = text
        }
        transcriber.onLevels = { [weak self] levels in
            self?.state.audioBands = levels
        }
        monitor.onKeyDown = { [weak self] kind in self?.keyDown(kind) }
        monitor.onKeyUp = { [weak self] kind in self?.keyUp(kind) }
        monitor.start()
    }

    // MARK: - Hotkey handling

    private func keyDown(_ kind: HotkeyKind) {
        if kind == .command {
            guard !state.isRecording else { return }
            activeMode = .command
            beginRecording(command: true)
            return
        }
        keyDownTime = Date()
        if state.isHandsFree {
            stopAndFinish()
            state.isHandsFree = false
            return
        }
        if !state.isRecording {
            activeMode = .dictation
            beginRecording(command: false)
        }
    }

    private func keyUp(_ kind: HotkeyKind) {
        if kind == .command {
            guard state.isRecording, activeMode == .command else { return }
            stopAndFinish()
            return
        }
        guard let downTime = keyDownTime else { return }
        keyDownTime = nil
        let heldFor = Date().timeIntervalSince(downTime)
        guard state.isRecording, activeMode == .dictation, !state.isHandsFree else { return }

        if heldFor < tapMaxDuration {
            // Quick tap. Double-tap -> hands-free; single tap -> cancel.
            if let lastEnd = lastTapEndTime, Date().timeIntervalSince(lastEnd) < doubleTapWindow {
                state.isHandsFree = true
                lastTapEndTime = nil
                overlay.setHandsFree(true)
                return
            }
            lastTapEndTime = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapWindow) { [weak self] in
                guard let self else { return }
                if self.state.isRecording && !self.state.isHandsFree && self.keyDownTime == nil,
                   let lastEnd = self.lastTapEndTime,
                   Date().timeIntervalSince(lastEnd) >= self.doubleTapWindow - 0.05 {
                    self.cancelRecording()
                }
            }
        } else {
            stopAndFinish()
        }
    }

    // MARK: - Recording lifecycle

    private func beginRecording(command: Bool) {
        do {
            try transcriber.start(contextualStrings: state.dictionaryWords,
                                  localeId: state.localeId.isEmpty ? nil : state.localeId)
        } catch {
            // Don't fail silently: a beep alone tells the user nothing.
            // The most common cause is a missing/revoked permission, so point
            // them there. The recognizer itself distinguishes those cases too
            // little to branch on reliably, so a general message is safest.
            overlay.showError("Microphone unavailable — check Microphone and Speech Recognition permission in Setup Guide.")
            if state.playSounds { NSSound.beep() }
            return
        }
        state.isRecording = true
        state.liveTranscript = ""
        if state.playSounds { NSSound(named: "Pop")?.play() }
        overlay.show(command: command)
    }

    private func stopAndFinish() {
        guard state.isRecording else { return }
        state.isRecording = false
        overlay.setProcessing()
        let appName = Paster.frontmostAppName()
        let mode = activeMode

        transcriber.finish { [weak self] raw in
            guard let self else { return }
            self.state.isHandsFree = false
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                self.overlay.hide()
                if self.state.playSounds { NSSound(named: "Basso")?.play() }
                return
            }
            switch mode {
            case .dictation:
                self.finishDictation(raw: trimmed, appName: appName)
            case .command:
                self.finishCommand(instruction: trimmed, appName: appName)
            }
        }
    }

    private func finishDictation(raw: String, appName: String) {
        if state.useLLM, state.activeLLMKey?.isEmpty == false {
            Task { @MainActor in
                let formatted: String
                var errorMessage: String?
                do {
                    formatted = try await LLMFormatter.format(transcript: raw, appName: appName, state: self.state)
                } catch let error as LLMFormatter.LLMError {
                    formatted = TextFormatter.format(raw, state: self.state)
                    errorMessage = error.userMessage
                } catch {
                    formatted = TextFormatter.format(raw, state: self.state)
                }
                self.deliver(raw: raw, formatted: formatted, appName: appName, errorMessage: errorMessage)
            }
        } else {
            deliver(raw: raw, formatted: TextFormatter.format(raw, state: state), appName: appName)
        }
    }

    private func finishCommand(instruction: String, appName: String) {
        Paster.copySelection { [weak self] selection in
            guard let self else { return }
            Task { @MainActor in
                do {
                    let result = try await LLMFormatter.command(
                        instruction: instruction, selectedText: selection, state: self.state)
                    self.deliver(raw: instruction, formatted: result, appName: appName)
                } catch let error as LLMFormatter.LLMError {
                    // Degrade instead of discarding: with a selection, the
                    // best we can do without the LLM is leave the original
                    // text untouched and tell the user why. With no selection,
                    // the instruction itself is what they wanted typed, so
                    // deliver it (cleaned up) rather than nothing.
                    if selection.isEmpty {
                        self.deliver(raw: instruction,
                                     formatted: TextFormatter.format(instruction, state: self.state),
                                     appName: appName,
                                     errorMessage: error.userMessage)
                    } else {
                        self.overlay.showError(error.userMessage)
                        if self.state.playSounds { NSSound(named: "Basso")?.play() }
                    }
                } catch {
                    if selection.isEmpty {
                        self.deliver(raw: instruction,
                                     formatted: TextFormatter.format(instruction, state: self.state),
                                     appName: appName,
                                     errorMessage: "Command Mode failed — try again")
                    } else {
                        self.overlay.showError("Command Mode failed — try again")
                        if self.state.playSounds { NSSound(named: "Basso")?.play() }
                    }
                }
            }
        }
    }

    private func deliver(raw: String, formatted: String, appName: String, errorMessage: String? = nil) {
        state.addHistory(raw: raw, formatted: formatted, appName: appName)
        Paster.paste(formatted)
        if let errorMessage {
            overlay.showError(errorMessage)
        } else {
            overlay.hide()
        }
        if state.playSounds { NSSound(named: "Glass")?.play() }
    }

    private func cancelRecording() {
        transcriber.stop()
        state.isRecording = false
        state.isHandsFree = false
        overlay.hide()
    }
}
