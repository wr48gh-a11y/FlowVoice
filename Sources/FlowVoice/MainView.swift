import SwiftUI
import Speech

// MARK: - Main window: sidebar navigation

enum SidebarItem: String, CaseIterable, Identifiable {
    case history, dictionary, snippets, settings
    var id: String { rawValue }

    var label: String {
        switch self {
        case .history: return "History"
        case .dictionary: return "Dictionary"
        case .snippets: return "Snippets"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .history: return "waveform"
        case .dictionary: return "character.book.closed"
        case .snippets: return "text.badge.plus"
        case .settings: return "gearshape"
        }
    }
}

struct MainView: View {
    @State private var selection: SidebarItem = .history

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.label, systemImage: item.icon)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 185)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                    Text("FlowVoice")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        } detail: {
            switch selection {
            case .history: HistoryView()
            case .dictionary: DictionaryView()
            case .snippets: SnippetsView()
            case .settings: SettingsView()
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .tint(Theme.accent)
    }
}

// MARK: - History

struct HistoryView: View {
    @ObservedObject var state = AppState.shared
    @State private var showClearConfirm = false

    private var dayGroups: [(day: Date, entries: [HistoryEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: state.history) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!) }
    }

    var body: some View {
        Group {
            if state.history.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.accent)
                    Text("Nothing dictated yet")
                        .font(.title3.weight(.semibold))
                    Text("Click into any text field, hold **\(state.hotkey.label)**, and speak.\nYour words land here as they land in the app.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        StatsHeader(history: state.history)
                        ForEach(dayGroups, id: \.day) { group in
                            DayGroupView(day: group.day, entries: group.entries)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("History")
        .toolbar {
            if !state.history.isEmpty {
                Button("Clear All", role: .destructive) { showClearConfirm = true }
            }
        }
        .confirmationDialog("Clear all history?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear All", role: .destructive) { state.history.removeAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes all \(state.history.count) dictations. This can't be undone.")
        }
    }
}

/// Wispr-style headline stats: words dictated, time saved vs typing, sessions.
struct StatsHeader: View {
    let history: [HistoryEntry]

    var body: some View {
        let words = Stats.words(in: history)
        HStack(spacing: 12) {
            StatTile(value: "\(words)", label: "words dictated")
            StatTile(value: Stats.formattedTimeSaved(words: words), label: "saved vs. typing")
            StatTile(value: "\(history.count)", label: "dictations")
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.stat())
                .foregroundStyle(Theme.accent)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct DayGroupView: View {
    let day: Date
    let entries: [HistoryEntry]
    @ObservedObject var state = AppState.shared

    private var dayLabel: String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dayLabel)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            ForEach(entries) { entry in
                HistoryCard(entry: entry) {
                    if let index = state.history.firstIndex(of: entry) {
                        state.history.remove(at: index)
                    }
                }
            }
        }
    }
}

struct HistoryCard: View {
    let entry: HistoryEntry
    let onDelete: () -> Void
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.formatted)
                .font(Theme.transcript(14))
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Text(entry.appName)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Theme.accentSoft, in: Capsule())
                    .foregroundStyle(Theme.accent)
                Text(entry.date, style: .time)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                if hovering {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.formatted, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                    } label: {
                        Label(copied ? "Copied" : "Copy",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash").font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .onHover { hovering = $0 }
    }
}

// MARK: - Dictionary

struct DictionaryView: View {
    @ObservedObject var state = AppState.shared
    @State private var newWord = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Teach FlowVoice the names, jargon, and terms it should recognize. They're fed to the recognizer as hints on every dictation.")
                .foregroundStyle(.secondary)
            HStack {
                TextField("Add a word or phrase", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if state.dictionaryWords.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "character.book.closed")
                        .font(.system(size: 32))
                        .foregroundStyle(Theme.accent)
                    Text("Add your first word — a name the recognizer keeps getting wrong is a good start.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    FlowLayoutish(words: state.dictionaryWords) { word in
                        if let index = state.dictionaryWords.firstIndex(of: word) {
                            state.dictionaryWords.remove(at: index)
                        }
                    }
                }
            }
        }
        .padding(20)
        .navigationTitle("Dictionary")
    }

    private func add() {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, !state.dictionaryWords.contains(word) else { return }
        state.dictionaryWords.append(word)
        newWord = ""
    }
}

/// Simple wrapping chip list for dictionary words.
struct FlowLayoutish: View {
    let words: [String]
    let onDelete: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)],
                  alignment: .leading, spacing: 8) {
            ForEach(words, id: \.self) { word in
                HStack(spacing: 6) {
                    Text(word).lineLimit(1)
                    Button {
                        onDelete(word)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.accentSoft, in: Capsule())
            }
        }
    }
}

// MARK: - Snippets

struct SnippetsView: View {
    @ObservedObject var state = AppState.shared
    @State private var trigger = ""
    @State private var expansion = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Say a trigger phrase — alone or mid-sentence — and FlowVoice inserts the full snippet instead.")
                .foregroundStyle(.secondary)
            HStack(alignment: .top) {
                TextField("Spoken trigger, e.g. “calendar link”", text: $trigger)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                TextField("Text to insert", text: $expansion, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                Button("Add", action: add)
                    .disabled(trigger.trimmingCharacters(in: .whitespaces).isEmpty || expansion.isEmpty)
            }
            if state.snippets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 32))
                        .foregroundStyle(Theme.accent)
                    Text("Try one: trigger “calendar link”, expansion your booking URL.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(state.snippets) { snippet in
                            HStack(alignment: .top) {
                                Text("“\(snippet.trigger)”")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 200, alignment: .leading)
                                Text(snippet.expansion)
                                    .font(Theme.transcript())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                Spacer()
                                Button(role: .destructive) {
                                    if let index = state.snippets.firstIndex(of: snippet) {
                                        state.snippets.remove(at: index)
                                    }
                                } label: {
                                    Image(systemName: "trash").font(.caption)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(10)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
        .padding(20)
        .navigationTitle("Snippets")
    }

    private func add() {
        state.snippets.append(Snippet(trigger: trigger.trimmingCharacters(in: .whitespaces),
                                      expansion: expansion))
        trigger = ""
        expansion = ""
    }
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var state = AppState.shared

    /// Computed once and cached — supportedLocales() returns 60+ entries and
    /// sorting them on every Settings re-render was needless work.
    private static let supportedLocales: [Locale] =
        SFSpeechRecognizer.supportedLocales().sorted { Self.localeLabel($0) < Self.localeLabel($1) }

    private static func localeLabel(_ locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    @State private var anthropicKeyField = AppState.shared.anthropicKey ?? ""
    @State private var openaiKeyField = AppState.shared.openaiKey ?? ""

    var body: some View {
        Form {
            Section {
                Picker("Dictation hotkey", selection: $state.hotkey) {
                    ForEach(HotkeyChoice.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                LabeledContent("Push-to-talk", value: "Hold the hotkey, speak, release")
                LabeledContent("Hands-free", value: "Double-tap to start, tap once to stop")
                if state.hotkey == .fn || state.commandHotkey == .fn {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Using fn: set “Press 🌐 key to” to “Do Nothing” in Keyboard settings, or fn will also trigger macOS features.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Button("Open Keyboard Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                        }
                    }
                }
            } header: {
                Label("Activation", systemImage: "keyboard")
            }

            Section {
                Picker("Speech recognition language", selection: $state.localeId) {
                    Text("System default").tag("")
                    ForEach(Self.supportedLocales, id: \.identifier) { locale in
                        Text(Self.localeLabel(locale)).tag(locale.identifier)
                    }
                }
            } header: {
                Label("Language", systemImage: "globe")
            }

            Section {
                Toggle("Use AI to polish dictation & enable Command Mode", isOn: $state.useLLM)
                if state.useLLM {
                    Picker("Provider", selection: $state.llmProvider) {
                        ForEach(LLMProvider.allCases) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    // One shared key + model editor per provider; the active
                    // provider's stored key/model back it (see ProviderKeySection).
                    switch state.llmProvider {
                    case .anthropic: ProviderKeySection(state: state, keyField: $anthropicKeyField)
                    case .openai: ProviderKeySection(state: state, keyField: $openaiKeyField)
                    }
                    Picker("Command Mode hotkey", selection: $state.commandHotkey) {
                        ForEach(HotkeyChoice.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                    if state.commandHotkey == state.hotkey {
                        Label("Command Mode needs a different key from the dictation hotkey — it's disabled while they match.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    LabeledContent("Command Mode",
                                   value: "Select text, hold the hotkey, say e.g. “make this more formal”")
                    Label("Transcripts are sent to \(state.llmProvider.label) when AI formatting is on. Without it, everything stays on-device.",
                          systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if (state.activeLLMKey ?? "").isEmpty {
                        Label("Enter an API key — falling back to on-device formatting until then.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    if state.keychainSaveFailed {
                        Label("Couldn't save the key to your Keychain. Try again, or check Keychain Access.",
                              systemImage: "xmark.octagon")
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Label("AI formatting", systemImage: "sparkles")
            }

            Section {
                Toggle("Remove filler words (um, uh, you know…)", isOn: $state.removeFillers)
                Toggle("Apply self-corrections (“…wait, no, Friday”)", isOn: $state.applySelfCorrections)
                Toggle("Play sounds on start/finish", isOn: $state.playSounds)
            } header: {
                Label("On-device formatting", systemImage: "text.badge.checkmark")
            }

            Section {
                LabeledContent("Accessibility") {
                    if Paster.hasAccessibilityPermission {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Open System Settings") {
                            Paster.promptForAccessibility()
                        }
                    }
                }
                Button("Open Setup Guide") {
                    OnboardingWindow.show()
                }
            } header: {
                Label("Permissions", systemImage: "lock.shield")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}

/// Shared "API key + model picker" editor for the active provider. Replaces
/// the previously duplicated per-provider blocks: the SecureField, Save
/// button, and model Picker are identical across providers — only the stored
/// key/model binding differs, which we route through a couple of small getters.
private struct ProviderKeySection: View {
    @ObservedObject var state: AppState
    @Binding var keyField: String

    var body: some View {
        SecureField(state.llmProvider.keyFieldPlaceholder, text: $keyField)
            .onSubmit { commitKey() }
        Button("Save key") { commitKey() }
            .disabled(keyField == (storedKey ?? ""))
        Picker("Model", selection: modelBinding) {
            ForEach(state.llmProvider.models, id: \.id) { m in
                Text(m.label).tag(m.id)
            }
        }
    }

    private func commitKey() {
        switch state.llmProvider {
        case .anthropic: state.anthropicKey = keyField
        case .openai: state.openaiKey = keyField
        }
    }

    private var storedKey: String? {
        switch state.llmProvider {
        case .anthropic: return state.anthropicKey
        case .openai: return state.openaiKey
        }
    }

    private var modelBinding: Binding<String> {
        switch state.llmProvider {
        case .anthropic: return $state.anthropicModel
        case .openai: return $state.openaiModel
        }
    }
}
