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

    /// Preset models offered in Settings for this provider. Defined on the
    /// provider so both the settings UI and any future call site share one
    /// source of truth instead of duplicating the list.
    var models: [(id: String, label: String)] {
        switch self {
        case .anthropic: return LLMProviderPresets.anthropic
        case .openai: return LLMProviderPresets.openai
        }
    }

    /// Placeholder for the API-key text field in Settings.
    var keyFieldPlaceholder: String {
        switch self {
        case .anthropic: return "Anthropic API key (sk-ant-…)"
        case .openai: return "OpenAI API key (sk-…)"
        }
    }
}

/// Compile-time model presets per provider. These go stale as providers rename
/// or retire models; a bad/retired id makes formatting fail and fall back to
/// the on-device formatter, so they degrade safely.
enum LLMProviderPresets {
    static let anthropic: [(id: String, label: String)] = [
        ("claude-haiku-4-5", "Claude Haiku 4.5 — fastest, cheapest"),
        ("claude-sonnet-5", "Claude Sonnet 5 — balanced"),
        ("claude-opus-4-8", "Claude Opus 4.8 — most capable"),
    ]
    static let openai: [(id: String, label: String)] = [
        ("gpt-4o-mini", "GPT-4o mini — fastest, cheapest"),
        ("gpt-4o", "GPT-4o — balanced"),
        ("gpt-4.1", "GPT-4.1 — most capable"),
    ]
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
        didSet { reportKeychain(Keychain.set(openaiKey ?? "", for: "openaiApiKey")) }
    }
    @Published var useLLM: Bool {
        didSet { defaults.set(useLLM, forKey: "useLLM") }
    }
    @Published var anthropicModel: String {
        didSet { defaults.set(anthropicModel, forKey: "llmModel") }
    }
    @Published var commandHotkey: HotkeyChoice {
        didSet { defaults.set(commandHotkey.rawValue, forKey: "commandHotkey") }
    }
    /// Anthropic API key, stored in the Keychain (never in UserDefaults).
    @Published var anthropicKey: String? {
        didSet { reportKeychain(Keychain.set(anthropicKey ?? "", for: "anthropicApiKey")) }
    }
    /// Set when a Keychain save fails, so Settings can warn the user instead
    /// of the key silently vanishing on next launch.
    @Published var keychainSaveFailed = false
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

    private func reportKeychain(_ success: Bool) {
        keychainSaveFailed = !success
        if !success { NSLog("FlowVoice: Keychain save failed") }
    }

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
        anthropicModel = defaults.string(forKey: "llmModel") ?? "claude-haiku-4-5"
        commandHotkey = HotkeyChoice(rawValue: defaults.string(forKey: "commandHotkey") ?? "") ?? .rightCommand
        anthropicKey = Keychain.get("anthropicApiKey")
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
        case .anthropic: return anthropicKey
        case .openai: return openaiKey
        }
    }

    /// The model id for the currently selected provider.
    var activeLLMModel: String {
        switch llmProvider {
        case .anthropic: return anthropicModel
        case .openai: return openaiModel
        }
    }

    func addHistory(raw: String, formatted: String, appName: String) {
        history.insert(HistoryEntry(date: Date(), raw: raw, formatted: formatted, appName: appName), at: 0)
        if history.count > 500 { history.removeLast(history.count - 500) }
    }
}
