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

    static func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChangeCount = pasteboard.changeCount

        sendKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)

        // Restore the old clipboard after the paste lands — but only if the
        // user hasn't copied something else in the meantime.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if pasteboard.changeCount == ourChangeCount {
                restore(pasteboard, from: saved)
            }
        }
    }

    /// Copies the current selection in the frontmost app (via synthesized ⌘C)
    /// and returns it, restoring the previous clipboard contents in full.
    static func copySelection(completion: @escaping (String) -> Void) {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        let changeCount = pasteboard.changeCount

        sendKey(CGKeyCode(kVK_ANSI_C), flags: .maskCommand)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let selection = pasteboard.changeCount != changeCount
                ? (pasteboard.string(forType: .string) ?? "")
                : ""
            restore(pasteboard, from: saved)
            completion(selection)
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
