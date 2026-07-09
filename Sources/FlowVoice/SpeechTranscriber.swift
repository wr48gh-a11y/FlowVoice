import Foundation
import AVFoundation
import Speech

/// Streams microphone audio into Apple's on-device speech recognizer and
/// reports partial transcripts + per-band input levels for the waveform.
///
/// Long sessions: when the recognizer emits a final result mid-recording
/// (Apple caps individual recognition tasks), the finalized text is banked
/// and a fresh request is started on the same audio tap, so hands-free
/// dictation can run indefinitely.
final class SpeechTranscriber: NSObject {
    static let bandCount = 14

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Text finalized by earlier recognition segments in this session.
    private var bankedText = ""
    /// Latest (partial or final) text of the current segment.
    private var segmentText = ""
    private var contextualStrings: [String] = []
    private var isRunning = false
    /// Whether a tap is currently installed on the input node. Tracked
    /// separately from audioEngine.isRunning: if the engine is stopped
    /// externally (e.g. the mic is unplugged mid-dictation), the tap stays
    /// installed, and installing a second one on the next session crashes.
    private var tapInstalled = false
    private var finishCompletion: ((String) -> Void)?
    private var finishTimeout: DispatchWorkItem?

    var onPartial: ((String) -> Void)?
    var onLevels: (([Float]) -> Void)?

    private var fullTranscript: String {
        [bankedText, segmentText]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func requestPermissions(_ completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            AVCaptureDevice.requestAccess(for: .audio) { micGranted in
                DispatchQueue.main.async {
                    completion(speechStatus == .authorized && micGranted)
                }
            }
        }
    }

    func start(contextualStrings: [String], localeId: String?) throws {
        stop()
        bankedText = ""
        segmentText = ""
        self.contextualStrings = contextualStrings

        let locale = localeId.flatMap { Locale(identifier: $0) } ?? Locale.current
        let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "FlowVoice", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Speech recognizer unavailable"])
        }
        self.recognizer = recognizer

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            self?.reportLevels(buffer)
        }
        tapInstalled = true
        audioEngine.prepare()
        try audioEngine.start()
        isRunning = true

        startSegment()
    }

    private func startSegment() {
        guard let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.contextualStrings = contextualStrings
        self.request = request
        segmentText = ""

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let result {
                    self.segmentText = result.bestTranscription.formattedString
                    self.onPartial?(self.fullTranscript)
                    if result.isFinal {
                        self.segmentDidFinalize()
                    }
                } else if error != nil {
                    self.segmentDidFinalize()
                }
            }
        }
    }

    /// Called on the main queue when the current segment finalizes or errors.
    private func segmentDidFinalize() {
        if !segmentText.isEmpty {
            bankedText = fullTranscript
            segmentText = ""
        }
        if let completion = finishCompletion {
            // We were waiting for the final result — deliver it now.
            finishTimeout?.cancel()
            finishCompletion = nil
            let text = fullTranscript
            teardown()
            completion(text)
        } else if isRunning {
            // Mid-session finalization (long dictation) — roll into a new segment.
            startSegment()
        }
    }

    /// Stops capture and waits for the recognizer's final result (bounded).
    func finish(completion: @escaping (String) -> Void) {
        isRunning = false
        removeTap()
        audioEngine.stop()
        request?.endAudio()

        finishCompletion = completion
        // Safety net: if no final result arrives, deliver what we have.
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, let completion = self.finishCompletion else { return }
            self.finishCompletion = nil
            let text = self.fullTranscript
            self.teardown()
            completion(text)
        }
        finishTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: timeout)
    }

    func stop() {
        isRunning = false
        finishTimeout?.cancel()
        finishCompletion = nil
        removeTap()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        teardown()
    }

    /// Removes the input tap if one is installed. Guarded by `tapInstalled`
    /// (not audioEngine.isRunning) so a tap left behind by an externally
    /// stopped engine is still cleaned up before the next session.
    private func removeTap() {
        guard tapInstalled else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    private func teardown() {
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
    }

    /// Splits the buffer into bands and reports per-band RMS (0...1 each),
    /// so the waveform reflects the actual shape of the incoming audio.
    private func reportLevels(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        guard n >= Self.bandCount else { return }
        let chunk = n / Self.bandCount
        var levels = [Float](repeating: 0, count: Self.bandCount)
        for band in 0..<Self.bandCount {
            var sum: Float = 0
            let start = band * chunk
            for i in start..<(start + chunk) { sum += data[i] * data[i] }
            let rms = sqrt(sum / Float(chunk))
            levels[band] = min(1, max(0, (20 * log10(max(rms, 1e-7)) + 50) / 50))
        }
        DispatchQueue.main.async { self.onLevels?(levels) }
    }
}
