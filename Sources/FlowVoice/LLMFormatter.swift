import Foundation

/// Calls the Anthropic Messages API to turn raw transcripts into polished text
/// (Wispr Flow's "AI auto-edits"), and to power Command Mode voice editing.
enum LLMFormatter {

    enum LLMError: Error {
        case noKey
        case badResponse(String)

        /// Short, non-technical message safe to surface in the overlay.
        var userMessage: String {
            switch self {
            case .noKey: return "No API key set — add one in Settings"
            case .badResponse: return "AI formatting failed — check your API key or connection"
            }
        }
    }

    /// Rewrite a raw spoken transcript into clean written text for the target app.
    static func format(transcript: String, appName: String, state: AppState) async throws -> String {
        let system = """
        You clean up voice dictation transcripts. Rewrite the user's raw spoken transcript \
        into polished written text, preserving their meaning, voice, and language.
        Rules:
        - Remove filler words (um, uh, you know, like) and false starts.
        - Apply self-corrections: "Tuesday, wait no, Friday" becomes "Friday".
        - Fix punctuation, capitalization, and obvious mis-transcriptions.
        - Interpret spoken formatting: "new line", "new paragraph", "bullet point".
        - Match tone to the destination app: the text will be pasted into "\(appName)". \
        Be casual for chat apps (Slack, Messages, Discord), professional for email, \
        and literal/precise for code editors and terminals.
        - Output ONLY the cleaned text. No preamble, no quotes, no commentary.
        """
        return try await complete(system: system, user: transcript, state: state)
    }

    /// Command Mode: apply a spoken instruction to the user's selected text.
    static func command(instruction: String, selectedText: String, state: AppState) async throws -> String {
        let system = """
        You are a voice-controlled text editor. The user selected some text and spoke an \
        editing command. Apply the command to the text and output ONLY the resulting text — \
        no preamble, no quotes, no commentary. Preserve the original language unless asked \
        to translate.
        """
        let user = selectedText.isEmpty
            ? "Command: \(instruction)\n\n(No text selected — generate the text the command asks for.)"
            : "Command: \(instruction)\n\nSelected text:\n\(selectedText)"
        return try await complete(system: system, user: user, state: state)
    }

    private static func complete(system: String, user: String, state: AppState) async throws -> String {
        guard let key = state.activeLLMKey, !key.isEmpty else { throw LLMError.noKey }
        switch state.llmProvider {
        case .anthropic:
            return try await completeAnthropic(system: system, user: user, key: key, model: state.activeLLMModel)
        case .openai:
            return try await completeOpenAI(system: system, user: user, key: key, model: state.activeLLMModel)
        }
    }

    // MARK: - Anthropic Messages API

    private static func completeAnthropic(system: String, user: String, key: String, model: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "system": system,
            "messages": [["role": "user", "content": user]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await send(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw LLMError.badResponse("unparseable response")
        }
        // stop_reason "refusal" or empty content → treat as failure, caller falls back.
        let text = content
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LLMError.badResponse("empty completion") }
        return text
    }

    // MARK: - OpenAI Chat Completions API

    private static func completeOpenAI(system: String, user: String, key: String, model: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "max_completion_tokens": 2048,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await send(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = (message["content"] as? String)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw LLMError.badResponse("unparseable response")
        }
        return text
    }

    private static func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "unknown error"
            throw LLMError.badResponse(message)
        }
        return data
    }
}
