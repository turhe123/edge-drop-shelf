import ServiceManagement
import SwiftUI

/// Settings window: shelf edge, file handling, limits, launch at login and the global shortcut.
struct SettingsView: View {
    @AppStorage(Prefs.edgeKey) private var edge = ShelfEdge.right.rawValue
    @AppStorage(Prefs.copyFilesKey) private var copyFiles = false
    @AppStorage(Prefs.autoRemoveKey) private var autoRemove = false
    @AppStorage(Prefs.hideWhenEmptyKey) private var hideWhenEmpty = true
    @AppStorage(Prefs.maxItemsKey) private var maxItems = 30
    @AppStorage(Prefs.hotkeyKey) private var hotkey = HotkeyPreset.optionShiftY.rawValue
    @AppStorage(Prefs.edgeTriggerKey) private var showOnEdgeDrag = true

    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Shelf") {
                Picker("Screen edge", selection: $edge) {
                    ForEach(ShelfEdge.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                Toggle("Show shelf when dragging to the screen edge", isOn: $showOnEdgeDrag)
                Toggle("Hide shelf when empty", isOn: $hideWhenEmpty)
                Stepper("Maximum items: \(maxItems)", value: $maxItems, in: 5...200, step: 5)
            }
            Section("Items") {
                Toggle("Copy files on drop", isOn: $copyFiles)
                Text("Copies are kept in a private folder so they survive moves; otherwise files are referenced in place.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Remove items after dragging them out", isOn: $autoRemove)
            }
            Section("General") {
                Picker("Global shortcut", selection: $hotkey) {
                    ForEach(HotkeyPreset.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("Launch at login", isOn: Binding(get: { loginStatus == .enabled }, set: setLaunchAtLogin))
                Text(loginStatusText).font(.caption).foregroundStyle(.secondary)
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                HStack {
                    Text("EdgeDropShelf is free and open source.")
                    Spacer()
                    Button("Support / Donate ❤️") {
                        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            loginStatus = SMAppService.mainApp.status
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var loginStatusText: String {
        switch loginStatus {
        case .enabled: return "EdgeDropShelf opens automatically when you log in."
        case .requiresApproval: return "Approval needed in System Settings › General › Login Items."
        case .notFound: return "Login item unavailable. Move EdgeDropShelf to the Applications folder and try again."
        default: return "EdgeDropShelf does not open at login."
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            loginError = error.localizedDescription
        }
        loginStatus = SMAppService.mainApp.status
        if loginStatus == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }
}
