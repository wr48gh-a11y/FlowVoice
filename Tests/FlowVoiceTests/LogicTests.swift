import Foundation
import Testing
@testable import FlowVoice

/// Tests for pure, non-GUI logic: usage stats, provider config, and the
/// hotkey/provider enums. The clipboard, hotkey-event, and transcription paths
/// need a live AppKit/keychain environment and aren't unit-testable, so this
/// file covers what is.
@Suite struct LogicTests {

    // MARK: - Stats (time-saved estimate)

    @Test func timeSavedIsNonNegative() {
        // Dictation should never report *negative* time saved, even for tiny
        // word counts or if the effective speaking rate were miscalibrated.
        #expect(Stats.minutesSaved(words: 0) >= 0)
        #expect(Stats.minutesSaved(words: 1) >= 0)
        #expect(Stats.minutesSaved(words: 1000) >= 0)
    }

    @Test func timeSavedIsPositiveForRealisticInput() {
        // 100 words at 150 effective speaking WPM vs 45 typing WPM should save
        // a few minutes — and never round to "<1 min".
        let mins = Stats.minutesSaved(words: 100)
        #expect(mins > 1)
    }

    @Test func formattedTimeSavedThresholds() {
        #expect(Stats.formattedTimeSaved(words: 0) == "<1 min")
        #expect(Stats.formattedTimeSaved(words: 5).hasSuffix("min"))
        // Large counts format as hours.
        #expect(Stats.formattedTimeSaved(words: 5000).hasSuffix("hrs"))
    }

    @Test func wordsCountsWhitespaceSeparatedTokens() {
        let entries = [
            HistoryEntry(date: Date(), raw: "a b c", formatted: "one two three", appName: "Test"),
            HistoryEntry(date: Date(), raw: "x", formatted: "four", appName: "Test"),
        ]
        #expect(Stats.words(in: entries) == 4)
    }

    // MARK: - LLMProvider config

    @Test func eachProviderHasModels() {
        // A provider with an empty model list would render a broken picker —
        // guard against that regressing.
        for provider in LLMProvider.allCases {
            #expect(!provider.models.isEmpty)
            // Every preset must have a non-empty id and label.
            for model in provider.models {
                #expect(!model.id.isEmpty)
                #expect(!model.label.isEmpty)
            }
        }
    }

    @Test func providerModelIdsAreUnique() {
        // Duplicate ids would make the Picker ambiguous.
        for provider in LLMProvider.allCases {
            let ids = provider.models.map(\.id)
            #expect(Set(ids).count == ids.count)
        }
    }

    @Test func providerKeyPlaceholdersAreNonEmpty() {
        for provider in LLMProvider.allCases {
            #expect(!provider.keyFieldPlaceholder.isEmpty)
        }
    }

    // MARK: - Hotkey / provider enums

    @Test func hotkeyChoicesAllHaveLabels() {
        for choice in HotkeyChoice.allCases {
            #expect(!choice.label.isEmpty)
        }
    }

    @Test func providersRoundTripThroughCodable() {
        // Persisted as the raw value; ensure decoding the raw value works.
        for provider in LLMProvider.allCases {
            #expect(LLMProvider(rawValue: provider.rawValue) == provider)
        }
    }
}
