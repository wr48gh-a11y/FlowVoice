import Testing
@testable import FlowVoice

private func fmt(_ raw: String, snippets: [Snippet] = []) -> String {
    TextFormatter.format(raw, options: FormatterOptions(snippets: snippets))
}

@Suite struct TextFormatterTests {

    @Test func fillerRemoval() {
        #expect(fmt("um so I was thinking, uh, we should ship it")
                == "So I was thinking, we should ship it.")
        #expect(fmt("you know it works") == "It works.")
    }

    @Test func selfCorrection() {
        #expect(fmt("let's meet Tuesday, wait no, Friday") == "Let's meet Friday.")
        #expect(fmt("send it to Bob, I mean, Alice") == "Send it to Alice.")
    }

    @Test func spokenCommands() {
        #expect(fmt("first line new line second line") == "First line\nSecond line.")
        #expect(fmt("intro new paragraph body").contains("\n\n"))
    }

    @Test func capitalizationAndTerminalPunctuation() {
        #expect(fmt("hello world") == "Hello world.")
        #expect(fmt("done!") == "Done!")
        #expect(fmt("first. second") == "First. Second.")
    }

    @Test func wholeUtteranceSnippet() {
        let snippets = [Snippet(trigger: "calendar link", expansion: "https://cal.com/hugh")]
        #expect(fmt("calendar link", snippets: snippets) == "https://cal.com/hugh")
        #expect(fmt("Calendar Link.", snippets: snippets) == "https://cal.com/hugh")
    }

    @Test func embeddedSnippet() {
        let snippets = [Snippet(trigger: "calendar link", expansion: "https://cal.com/hugh")]
        let result = fmt("here is my calendar link thanks", snippets: snippets)
        #expect(result.contains("https://cal.com/hugh"))
        #expect(result.hasPrefix("Here is my"))
    }

    @Test func emptyAndWhitespace() {
        #expect(fmt("   ") == "")
    }

    @Test func fillersDisabled() {
        let result = TextFormatter.format(
            "um hello", options: FormatterOptions(removeFillers: false))
        #expect(result.lowercased().contains("um"))
    }
}
