import AppKit
import Carbon.HIToolbox

private func hkLog(_ msg: String) {
    let path = NSHomeDirectory() + "/Library/Logs/Claudar-last-error.txt"
    let line = "[\(Date())] hotkey: \(msg)\n"
    let existing = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    try? (existing + line).write(toFile: path, atomically: true, encoding: .utf8)
}

/// A single global hotkey via Carbon's RegisterEventHotKey. Unlike an NSEvent
/// global monitor, this needs **no Accessibility permission** — the classic
/// approach used by hotkey libraries. Fixed combo: ⌘⇧U.
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?

    // ⌘⇧C
    private let keyCode = UInt32(kVK_ANSI_C)
    private let modifiers = UInt32(cmdKey | shiftKey)
    private let hotKeyID = EventHotKeyID(signature: OSType(0x43555347 /* "CUSG" */), id: 1)

    static let comboDescription = "⌘⇧C"

    var isEnabled: Bool { hotKeyRef != nil }

    /// Enables or disables the hotkey, invoking `action` on the main thread when
    /// pressed. Idempotent.
    func setEnabled(_ enabled: Bool, action: @escaping () -> Void) {
        if enabled {
            guard hotKeyRef == nil else { self.action = action; return }
            self.action = action
            installHandlerIfNeeded()
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref
            )
            if status == noErr {
                hotKeyRef = ref
            } else {
                // -9878 = eventHotKeyExistsErr (another app owns the combo).
                hkLog("RegisterEventHotKey failed, status=\(status)")
            }
        } else {
            if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        }
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData -> OSStatus in
                guard let userData, let event else { return noErr }
                var id = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &id
                )
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                if id.id == mgr.hotKeyID.id {
                    DispatchQueue.main.async { mgr.action?() }
                }
                return noErr
            },
            1, &spec, selfPtr, &handler
        )
    }
}
