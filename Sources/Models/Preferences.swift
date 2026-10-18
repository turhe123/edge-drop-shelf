import Foundation
import Carbon.HIToolbox

/// Which screen edge the shelf slides in from.
enum ShelfEdge: String, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
    var title: String { self == .left ? "Left" : "Right" }
}

/// The small set of global shortcut combinations the user can choose from.
enum HotkeyPreset: String, CaseIterable, Identifiable {
    case none, optionShiftY, controlOptionY, commandShiftY, controlOptionSpace
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .optionShiftY: return "⌥⇧Y"
        case .controlOptionY: return "⌃⌥Y"
        case .commandShiftY: return "⌘⇧Y"
        case .controlOptionSpace: return "⌃⌥Space"
        }
    }

    /// Carbon virtual key code and modifier mask, or nil when disabled.
    var combo: (keyCode: UInt32, modifiers: UInt32)? {
        switch self {
        case .none: return nil
        case .optionShiftY: return (UInt32(kVK_ANSI_Y), UInt32(optionKey | shiftKey))
        case .controlOptionY: return (UInt32(kVK_ANSI_Y), UInt32(controlKey | optionKey))
        case .commandShiftY: return (UInt32(kVK_ANSI_Y), UInt32(cmdKey | shiftKey))
        case .controlOptionSpace: return (UInt32(kVK_Space), UInt32(controlKey | optionKey))
        }
    }
}

/// Central list of UserDefaults keys and typed accessors shared by @AppStorage views and services.
enum Prefs {
    static let edgeKey = "shelfEdge"
    static let copyFilesKey = "copyFilesOnDrop"
    static let autoRemoveKey = "autoRemoveAfterDragOut"
    static let hideWhenEmptyKey = "hideWhenEmpty"
    static let maxItemsKey = "maxItems"
    static let hotkeyKey = "hotkeyPreset"
    static let edgeTriggerKey = "showOnEdgeDrag"

    static let defaults: [String: Any] = [
        edgeKey: ShelfEdge.right.rawValue,
        copyFilesKey: false,
        autoRemoveKey: false,
        hideWhenEmptyKey: true,
        maxItemsKey: 30,
        hotkeyKey: HotkeyPreset.optionShiftY.rawValue,
        edgeTriggerKey: true,
    ]

    private static var store: UserDefaults { .standard }
    static var edge: ShelfEdge { ShelfEdge(rawValue: store.string(forKey: edgeKey) ?? "") ?? .right }
    static var copyFiles: Bool { store.bool(forKey: copyFilesKey) }
    static var autoRemove: Bool { store.bool(forKey: autoRemoveKey) }
    static var hideWhenEmpty: Bool { store.bool(forKey: hideWhenEmptyKey) }
    static var maxItems: Int { max(1, store.integer(forKey: maxItemsKey)) }
    static var hotkey: HotkeyPreset { HotkeyPreset(rawValue: store.string(forKey: hotkeyKey) ?? "") ?? .none }
    static var showOnEdgeDrag: Bool { store.bool(forKey: edgeTriggerKey) }
}
