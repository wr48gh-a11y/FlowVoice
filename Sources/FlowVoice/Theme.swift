import SwiftUI

/// FlowVoice visual identity: "Sonar" — a single deep-teal accent drawn from
/// the waveform motif, quiet neutrals everywhere else, and transcripts set in
/// a serif face so dictated words read as writing, not log output.
enum Theme {
    static let accent = Color(red: 0.05, green: 0.49, blue: 0.53)        // #0D7D87
    static let accentSoft = accent.opacity(0.12)

    /// Serif face for dictated text.
    static func transcript(_ size: CGFloat = 13) -> Font {
        .system(size: size, design: .serif)
    }

    /// Rounded numerals for stats.
    static func stat(_ size: CGFloat = 26) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
}

/// Derived usage statistics, Wispr-style.
enum Stats {
    static let typingWPM = 45.0

    /// Effective speaking rate, in words per minute, used to estimate time
    /// saved vs. typing. 220 WPM is a raw speech rate, but real dictation
    /// also spends time on recognizer latency, the final-result wait, and
    /// (when AI formatting is on) a network round-trip. Using the raw rate
    /// overstated "time saved", so we credit a realistic effective rate that
    /// accounts for that overhead.
    static let speakingWPM = 150.0

    static func words(in history: [HistoryEntry]) -> Int {
        history.reduce(0) { $0 + $1.formatted.split(whereSeparator: \.isWhitespace).count }
    }

    /// Minutes saved vs. typing the same words. Floors at zero: if the
    /// effective speaking rate were ever at or below typing speed, dictation
    /// wouldn't be saving time and we shouldn't report a negative.
    static func minutesSaved(words: Int) -> Double {
        max(0, Double(words) * (1.0 / typingWPM - 1.0 / speakingWPM))
    }

    static func formattedTimeSaved(words: Int) -> String {
        let minutes = minutesSaved(words: words)
        if minutes < 1 { return "<1 min" }
        if minutes < 60 { return "\(Int(minutes.rounded())) min" }
        return String(format: "%.1f hrs", minutes / 60)
    }
}
