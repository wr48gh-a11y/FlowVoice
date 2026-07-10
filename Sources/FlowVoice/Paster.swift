import AppKit
import Carbon.HIToolbox

/// Inserts text into the frontmost app by temporarily replacing the clipboard
/// and synthesizing ⌘V, then restoring the previous clipboard contents —
/// including images, rich text, and any other data types.
enum Paster {

    static func frontmostAppName() -> String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
    }

    /// Full snapshot of every item/type currently on the pasteboard.
    private static func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    entry[type] = data
                }
            }
            return entry
        }
    }

    private static func restore(_ pasteboard: NSPasteboard, from snapshot: [[NSPasteboard.PasteboardType: Data]]) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }
        let items = snapshot.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(items)
    }

    /// How long to wait after synthesizing ⌘V before restoring the previous
    /// clipboard. There is no reliable cross-app signal that a paste has
    /// landed — some apps paste near-instantly, heavy Electron apps or remote
    /// desktops can take noticeably longer — so this is a deliberately
    /// generous fixed delay. If you bump it, the user's old clipboard just
    /// stays replaced for longer; if you shrink it, you risk restoring the
    /// clipboard before a slow app reads it (the dictated text still pastes,
    /// but a subsequent ⌘V in that app would paste the stale old contents).
    private static let pasteRestoreDelay: TimeInterval = 0.7

    /// When waiting for a synthesized ⌘C to land, poll the clipboard at this
    /// interval until its change count bumps (the copy succeeded) or we time
    /// out. Unlike a paste, a copy landing *is* observable via changeCount.
    private static let copyPollInterval: TimeInterval = 0.02
    private static let copyPollTimeout: TimeInterval = 0.6

    static func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChangeCount = pasteboard.changeCount

        sendKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)

        // Restore the old clipboard after the paste lands — but only if the
        // user hasn't copied something else in the meantime. See the note on
        // pasteRestoreDelay: we can't confirm the paste landed, only that our
        // clipboard contents are still the most recent ones.
        DispatchQueue.main.asyncAfter(deadline: .now() + pasteRestoreDelay) {
            if pasteboard.changeCount == ourChangeCount {
                restore(pasteboard, from: saved)
            }
        }
    }

    /// Copies the current selection in the frontmost app (via synthesized ⌘C)
    /// and returns it, restoring the previous clipboard contents in full.
    /// Polls until the copy lands (clipboard change count bumps) instead of
    /// waiting a fixed delay, so it's reliable even in slower apps and minimal
    /// when the app responds quickly.
    static func copySelection(completion: @escaping (String) -> Void) {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        let baselineCount = pasteboard.changeCount

        sendKey(CGKeyCode(kVK_ANSI_C), flags: .maskCommand)

        pollCopy(pasteboard: pasteboard,
                 baselineCount: baselineCount,
                 deadline: Date().addingTimeInterval(copyPollTimeout)) { copied in
            let selection = copied ? (pasteboard.string(forType: .string) ?? "") : ""
            restore(pasteboard, from: saved)
            completion(selection)
        }
    }

    private static func pollCopy(pasteboard: NSPasteboard,
                                 baselineCount: Int,
                                 deadline: Date,
                                 completion: @escaping (Bool) -> Void) {
        if pasteboard.changeCount != baselineCount {
            completion(true)
        } else if Date() >= deadline {
            // Timed out without a clipboard change — the app likely had no
            // selection to copy (or ignored ⌘C). Treat as empty selection.
            completion(false)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + copyPollInterval) {
                pollCopy(pasteboard: pasteboard,
                         baselineCount: baselineCount,
                         deadline: deadline,
                         completion: completion)
            }
        }
    }

    private static func sendKey(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    static func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
