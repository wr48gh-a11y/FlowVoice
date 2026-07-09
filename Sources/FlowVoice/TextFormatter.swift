import Foundation

/// Post-processes raw transcripts the way Wispr Flow's "AI auto-edits" do:
/// strips filler words, applies spoken self-corrections, expands snippets,
/// and tidies capitalization/punctuation.
struct FormatterOptions {
    var removeFillers = true
    var applySelfCorrections = true
    var snippets: [Snippet] = []
}

enum TextFormatter {

    static func format(_ raw: String, state: AppState) -> String {
        format(raw, options: FormatterOptions(
            removeFillers: state.removeFillers,
            applySelfCorrections: state.applySelfCorrections,
            snippets: state.snippets))
    }

    static func format(_ raw: String, options: FormatterOptions) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        // Whole-utterance snippet trigger -> expansion verbatim.
        if let expansion = snippetExpansion(for: text, snippets: options.snippets) {
            return expansion
        }
        // Corrections must run before filler removal: "I mean" is both a
        // correction marker ("Bob, I mean, Alice") and a filler word.
        if options.applySelfCorrections {
            text = applySelfCorrections(text)
        }
        if options.removeFillers {
            text = removeFillerWords(text)
        }
        text = applySpokenCommands(text)
        text = expandEmbeddedSnippets(text, snippets: options.snippets)
        text = tidy(text)
        return text
    }

    /// Replaces snippet triggers spoken inside a longer sentence,
    /// e.g. "here's my calendar link thanks" -> "here's <expansion> thanks".
    private static func expandEmbeddedSnippets(_ text: String, snippets: [Snippet]) -> String {
        var result = text
        for snippet in snippets where !snippet.trigger.isEmpty {
            let escaped = snippet.trigger
                .split(separator: " ")
                .map { NSRegularExpression.escapedPattern(for: String($0)) }
                .joined(separator: "\\s+")
            let pattern = "(?i)\\b" + escaped + "\\b"
            result = result.replacingOccurrences(
                of: pattern,
                with: NSRegularExpression.escapedTemplate(for: snippet.expansion),
                options: .regularExpression)
        }
        return result
    }

    // MARK: - Snippets

    private static func snippetExpansion(for text: String, snippets: [Snippet]) -> String? {
        let spoken = normalize(text)
        for snippet in snippets where !snippet.trigger.isEmpty {
            if spoken == normalize(snippet.trigger) {
                return snippet.expansion
            }
        }
        return nil
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined()
            .split(separator: " ").joined(separator: " ")
    }

    // MARK: - Fillers

    private static let fillers = [
        "um", "uh", "uhm", "umm", "er", "erm", "ah", "hmm",
        "you know", "i mean", "sort of", "kind of like", "like i said",
    ]

    private static func removeFillerWords(_ text: String) -> String {
        var result = text
        for filler in fillers {
            let pattern = "(?i)(^|[\\s,])" + NSRegularExpression.escapedPattern(for: filler) + "([\\s,.!?]|$)"
            while let regex = try? NSRegularExpression(pattern: pattern),
                  regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)) != nil {
                let new = regex.stringByReplacingMatches(
                    in: result, range: NSRange(result.startIndex..., in: result),
                    withTemplate: "$1$2")
                if new == result { break }
                result = new
            }
        }
        // Collapse artifacts: double spaces, space-before-punctuation, orphaned commas.
        result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+([,.!?])"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"([,.!?]),"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"^[,.\s]+"#, with: "", options: .regularExpression)
        return result
    }

    // MARK: - Self-corrections ("let's meet Tuesday, wait no, Friday" -> "let's meet Friday")

    private static func applySelfCorrections(_ text: String) -> String {
        var result = text
        // "X, wait no, Y" / "X, no wait, Y" / "X, actually, Y" / "X, I mean, Y" — drop the word before the marker.
        let markers = ["wait,? no", "no,? wait", "actually,? no", "scratch that", "i mean"]
        for marker in markers {
            let pattern = "(?i)\\b[\\w'’-]+[,]?\\s+(?:" + marker + ")[,]?\\s+"
            result = result.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Spoken commands ("new line", "new paragraph")

    private static func applySpokenCommands(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(
            of: #"(?i)[,.]?\s*\bnew paragraph\b[,.]?\s*"#, with: "\n\n", options: .regularExpression)
        result = result.replacingOccurrences(
            of: #"(?i)[,.]?\s*\bnew line\b[,.]?\s*"#, with: "\n", options: .regularExpression)
        return result
    }

    // MARK: - Tidy

    private static func tidy(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return result }
        // Capitalize first letter.
        result = result.prefix(1).uppercased() + result.dropFirst()
        // Capitalize after sentence-ending punctuation.
        if let regex = try? NSRegularExpression(pattern: #"([.!?]\s+|\n)([a-z])"#) {
            let ns = NSMutableString(string: result)
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed()
            for m in matches {
                let r = m.range(at: 2)
                ns.replaceCharacters(in: r, with: ns.substring(with: r).uppercased())
            }
            result = ns as String
        }
        // Ensure terminal punctuation for sentence-like text — but not when the
        // text ends in a URL or bare domain, where a trailing "." breaks it.
        if let last = result.last, !"\n.!?:;,-)]}\"'".contains(last), result.count > 2,
           !endsWithURL(result) {
            result += "."
        }
        return result
    }

    /// True when the final token looks like a URL or bare domain
    /// (e.g. "github.com", "https://x.io/y") — appending "." would corrupt it.
    private static func endsWithURL(_ text: String) -> Bool {
        guard let token = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).last else { return false }
        let pattern = #"^(https?://\S+|[\w-]+(\.[\w-]+)*\.[a-z]{2,}(/\S*)?)$"#
        return token.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
