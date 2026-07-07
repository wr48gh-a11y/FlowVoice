import AppKit
import Carbon.HIToolbox

enum HotkeyKind { case dictation, command }

/// Watches modifier keys globally (fn / right ⌘ / right ⌥) and reports
/// press & release for the dictation and command hotkeys.
/// Requires Accessibility permission.
final class HotkeyMonitor {
    var onKeyDown: ((HotkeyKind) -> Void)?
    var onKeyUp: ((HotkeyKind) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var down: Set<HotkeyKind> = []

    func start() {
        stop()
        let handler: (NSEvent) -> Void = { [weak self] event in
            self?.handle(event)
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handler(event)
            return event
        }
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
        down = []
    }

    private func handle(_ event: NSEvent) {
        let state = AppState.shared
        check(event, choice: state.hotkey, kind: .dictation)
        if state.useLLM, state.commandHotkey != state.hotkey {
            check(event, choice: state.commandHotkey, kind: .command)
        }
    }

    private func check(_ event: NSEvent, choice: HotkeyChoice, kind: HotkeyKind) {
        let pressed: Bool
        switch choice {
        case .fn:
            // flagsChanged for the physical fn key always carries keyCode 63;
            // requiring it filters out .function flags from arrow/page keys.
            guard event.keyCode == UInt16(kVK_Function) else { return }
            pressed = event.modifierFlags.contains(.function)
        case .rightCommand:
            guard event.keyCode == UInt16(kVK_RightCommand) else { return }
            pressed = event.modifierFlags.contains(.command)
        case .rightOption:
            guard event.keyCode == UInt16(kVK_RightOption) else { return }
            pressed = event.modifierFlags.contains(.option)
        }

        if pressed && !down.contains(kind) {
            down.insert(kind)
            onKeyDown?(kind)
        } else if !pressed && down.contains(kind) {
            down.remove(kind)
            onKeyUp?(kind)
        }
    }
}
