import Foundation
import Combine

/// Which key activates dictation.
enum HotkeyChoice: String, CaseIterable, Identifiable, Codable {
    case fn = "fn"
    case rightCommand = "rightCommand"
    case rightOption = "rightOption"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fn: return "fn (Globe)"
        case .rightCommand: return "Right ⌘"
        case .rightOption: return "Right ⌥"
        }
    }
}

enum LLMProvider: String, CaseIterable, Identifiable, Codable {
    case anthropic, openai
    var id: String { rawValue }
    var label: String {
        switch self {
        case .anthropic: return "Claude (Anthropic)"
        case .openai: return "ChatGPT (OpenAI)"
        }
    }
}

struct Snippet: Identifiable, Codable, Equatable {
    var id = UUID()
    var trigger: String   // spoken phrase, e.g. "calendar link"
    var expansion: String // inserted text
}

struct HistoryEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var date: Date
    var raw: String
    var formatted: String
    var appName: String
}

/// Global app settings + user data, persisted to UserDefaults / Application Support.
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var hotkey: HotkeyChoice {
        didSet { defaults.set(hotkey.rawValue, forKey: "hotkey") }
    }
    @Published var removeFillers: Bool {
        didSet { defaults.set(removeFillers, forKey: "removeFillers") }
    }
    @Published var applySelfCorrections: Bool {
        didSet { defaults.set(applySelfCorrections, forKey: "applySelfCorrections") }
    }
    @Published var playSounds: Bool {
        didSet { defaults.set(playSounds, forKey: "playSounds") }
    }
    @Published var llmProvider: LLMProvider {
        didSet { defaults.set(llmProvider.rawValue, forKey: "llmProvider") }
    }
    @Published var openaiModel: String {
        didSet { defaults.set(openaiModel, forKey: "openaiModel") }
    }
    /// OpenAI API key, stored in the Keychain.
    @Published var openaiKey: String? {
        didSet { Keychain.set(openaiKey ?? "", for: "openaiApiKey") }
    }
    @Published var useLLM: Bool {
        didSet { defaults.set(useLLM, forKey: "useLLM") }
    }
    @Published var llmModel: String {
        didSet { defaults.set(llmModel, forKey: "llmModel") }
    }
    @Published var commandHotkey: HotkeyChoice {
        didSet { defaults.set(commandHotkey.rawValue, forKey: "commandHotkey") }
    }
    /// Anthropic API key, stored in the Keychain (never in UserDefaults).
    @Published var apiKey: String? {
        didSet { Keychain.set(apiKey ?? "", for: "anthropicApiKey") }
    }
    @Published var dictionaryWords: [String] {
        didSet { defaults.set(dictionaryWords, forKey: "dictionaryWords") }
    }
    @Published var snippets: [Snippet] {
        didSet { save(snippets, to: "snippets.json") }
    }
    @Published var history: [HistoryEntry] {
        didSet { save(history, to: "history.json") }
    }

    /// Speech recognition locale ("" = system default).
    @Published var localeId: String {
        didSet { defaults.set(localeId, forKey: "localeId") }
    }

    // Live UI state
    @Published var isRecording = false
    @Published var isHandsFree = false
    @Published var liveTranscript = ""
    @Published var audioBands: [Float] = Array(repeating: 0, count: SpeechTranscriber.bandCount)

    private let defaults = UserDefaults.standard

    private var supportDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FlowVoice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {
        hotkey = HotkeyChoice(rawValue: defaults.string(forKey: "hotkey") ?? "") ?? .fn
        removeFillers = defaults.object(forKey: "removeFillers") as? Bool ?? true
        applySelfCorrections = defaults.object(forKey: "applySelfCorrections") as? Bool ?? true
        playSounds = defaults.object(forKey: "playSounds") as? Bool ?? true
        useLLM = defaults.object(forKey: "useLLM") as? Bool ?? false
        llmProvider = LLMProvider(rawValue: defaults.string(forKey: "llmProvider") ?? "") ?? .anthropic
        openaiModel = defaults.string(forKey: "openaiModel") ?? "gpt-4o-mini"
        openaiKey = Keychain.get("openaiApiKey")
        llmModel = defaults.string(forKey: "llmModel") ?? "claude-haiku-4-5"
        commandHotkey = HotkeyChoice(rawValue: defaults.string(forKey: "commandHotkey") ?? "") ?? .rightCommand
        apiKey = Keychain.get("anthropicApiKey")
        localeId = defaults.string(forKey: "localeId") ?? ""
        dictionaryWords = defaults.stringArray(forKey: "dictionaryWords") ?? []
        snippets = []
        history = []
        snippets = load("snippets.json") ?? []
        history = load("history.json") ?? []
    }

    private func save<T: Encodable>(_ value: T, to file: String) {
        let url = supportDir.appendingPathComponent(file)
        if let data = try? JSONEncoder().encode(value) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func load<T: Decodable>(_ file: String) -> T? {
        let url = supportDir.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// The API key for the currently selected provider.
    var activeLLMKey: String? {
        switch llmProvider {
        case .anthropic: return apiKey
        case .openai: return openaiKey
        }
    }

    func addHistory(raw: String, formatted: String, appName: String) {
        history.insert(HistoryEntry(date: Date(), raw: raw, formatted: formatted, appName: appName), at: 0)
        if history.count > 500 { history.removeLast(history.count - 500) }
    }
}
