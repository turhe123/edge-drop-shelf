import AppKit
import SwiftUI

/// Entry point: a menu bar-only app with a MenuBarExtra menu and a Settings window.
@main
struct EdgeDropShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ShelfStore.shared
    @StateObject private var panel = ShelfPanelController.shared

    init() {
        UserDefaults.standard.register(defaults: Prefs.defaults)
    }

    var body: some Scene {
        MenuBarExtra("EdgeDropShelf", systemImage: "tray.and.arrow.down.fill") {
            MenuContent()
                .environmentObject(store)
                .environmentObject(panel)
        }
        Settings {
            SettingsView()
        }
    }
}

/// Items of the menu bar menu.
struct MenuContent: View {
    @EnvironmentObject private var store: ShelfStore
    @EnvironmentObject private var panel: ShelfPanelController

    var body: some View {
        Button(panel.isVisible ? "Hide Shelf" : "Show Shelf") { panel.toggle() }
        Button("Clear Shelf") { store.clearAll() }
            .disabled(store.items.isEmpty)
        Divider()
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Button("Support / Donate ❤️") {
            NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
        }
        Divider()
        Button("Quit EdgeDropShelf") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Wires up the shelf panel, global hotkey and edge-drag monitor, and reacts to settings changes.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var defaultsObserver: NSObjectProtocol?
    private var lastEdge = Prefs.edge

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: Prefs.defaults)
        let store = ShelfStore.shared
        let panel = ShelfPanelController.shared
        panel.setup(store: store)
        HotKeyService.shared.onPress = { panel.toggle() }
        applyPreferences()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.applyPreferences() }
        if !store.items.isEmpty { panel.show() }
    }

    private func applyPreferences() {
        if HotKeyService.shared.current != Prefs.hotkey { HotKeyService.shared.register(Prefs.hotkey) }
        if Prefs.showOnEdgeDrag { EdgeDragMonitor.shared.start() } else { EdgeDragMonitor.shared.stop() }
        if lastEdge != Prefs.edge {
            lastEdge = Prefs.edge
            ShelfPanelController.shared.reposition()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        ShelfStore.shared.save()
        HotKeyService.shared.unregister()
        EdgeDragMonitor.shared.stop()
        ShelfPanelController.shared.tearDown()
    }
}
