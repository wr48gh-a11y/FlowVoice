# FlowVoice

Voice dictation for macOS that types into any app. Hold a hotkey, speak,
release — polished text appears wherever your cursor is. Inspired by
[Wispr Flow](https://wisprflow.ai), built native in Swift, with transcription
that runs entirely on your Mac.

## Features

- **Push-to-talk** — hold **fn** (or right ⌘ / right ⌥), speak, release to paste.
- **Hands-free mode** — double-tap the hotkey to start, tap once to stop.
- **On-device transcription** — Apple's Speech framework, 60+ languages, nothing leaves your Mac by default.
- **AI polish (optional)** — bring your own Anthropic or OpenAI API key and each
  dictation is rewritten by Claude or GPT: fillers stripped, self-corrections
  applied, tone matched to the app you're typing into.
- **Command Mode** — select text, hold the command hotkey, say
  "make this more formal" / "turn this into bullet points" — the selection is
  rewritten in place.
- **Personal dictionary** — teach it names and jargon; fed to the recognizer as hints.
- **Snippets** — say "calendar link" and your booking URL is inserted, even mid-sentence.
- **History & stats** — day-grouped transcript history with words dictated and time saved vs. typing.

## Install

1. Download `FlowVoice.zip` from the [latest release](../../releases/latest) and unzip.
2. Move `FlowVoice.app` to `/Applications`.
3. **First launch:** right-click the app → **Open** → **Open**. (The app is not
   yet notarized by Apple, so macOS warns on first run. If it still refuses:
   `xattr -dr com.apple.quarantine /Applications/FlowVoice.app`.)
4. Follow the in-app Setup Guide to grant **Microphone**, **Speech
   Recognition**, and **Accessibility** permissions.
5. Click into any text field, hold **fn**, speak, release.

Using **fn** as the hotkey? Set System Settings → Keyboard → "Press 🌐 key to"
→ **Do Nothing**, or fn will also trigger macOS features.

## AI formatting (optional)

Menu bar icon → Open FlowVoice → Settings → **AI formatting**: pick Claude or
ChatGPT, paste an API key ([console.anthropic.com](https://console.anthropic.com)
/ [platform.openai.com](https://platform.openai.com)), choose a model. Keys are
stored in the macOS Keychain. Without a key, a built-in rule-based formatter
handles cleanup and everything stays offline.

## Build from source

Requires macOS 14+ and the Swift toolchain (Command Line Tools are enough):

```bash
git clone <this repo>
cd FlowVoice
./make-app.sh     # builds, signs, installs to /Applications
swift test        # formatter test suite
```

If your Command Line Tools SDK is missing `HIServices/Icons.h` (a known broken
install), `make-app.sh` already works around it via the VFS overlay in `SDKShim/`.

## How pasting works

The transcript temporarily replaces your clipboard, ⌘V is synthesized into the
frontmost app, and your previous clipboard contents — including images and rich
text — are restored afterwards.

## License

MIT — see [LICENSE](LICENSE).
