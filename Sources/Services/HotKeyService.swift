import Carbon.HIToolbox
import Foundation

/// Registers a single system-wide hotkey through Carbon's RegisterEventHotKey (no permissions required).
final class HotKeyService {
    static let shared = HotKeyService()

    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private(set) var current: HotkeyPreset = .none

    func register(_ preset: HotkeyPreset) {
        unregister()
        current = preset
        guard let combo = preset.combo else { return }
        if handlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKeyService.shared.onPress?() }
                return noErr
            }, 1, &spec, nil, &handlerRef)
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x4544_5348), id: 1) // "EDSH"
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            NSLog("EdgeDropShelf: could not register hotkey \(preset.title) (status \(status)); it may be used by another app.")
        }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        current = .none
    }
}
