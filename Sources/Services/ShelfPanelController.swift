import AppKit
import Combine
import SwiftUI

/// Borderless, non-activating floating panel that hosts the shelf on every Space and over full-screen apps.
final class ShelfPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 260, height: 420),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Creates the shelf panel and slides it in and out from the configured edge of the screen under the cursor.
final class ShelfPanelController: ObservableObject {
    static let shared = ShelfPanelController()

    @Published private(set) var isVisible = false
    private var panel: ShelfPanel?
    private var cancellables = Set<AnyCancellable>()
    private let width: CGFloat = 260

    func setup(store: ShelfStore) {
        guard panel == nil else { return }
        let panel = ShelfPanel()
        let host = NSHostingView(rootView: ShelfView().environmentObject(store))
        panel.contentView = host
        self.panel = panel

        // Hide automatically when the shelf becomes empty, if enabled.
        store.$items
            .map(\.isEmpty)
            .removeDuplicates()
            .dropFirst()
            .filter { $0 }
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                if Prefs.hideWhenEmpty && store.items.isEmpty { self?.hide() }
            }
            .store(in: &cancellables)
    }

    func toggle() { isVisible ? hide() : show() }

    private func targetFrame(on screen: NSScreen) -> NSRect {
        let vf = screen.visibleFrame
        let height = min(520, vf.height * 0.8)
        let x = Prefs.edge == .left ? vf.minX + 8 : vf.maxX - width - 8
        return NSRect(x: x, y: vf.midY - height / 2, width: width, height: height)
    }

    private func offscreenFrame(from frame: NSRect, on screen: NSScreen) -> NSRect {
        var f = frame
        f.origin.x = Prefs.edge == .left ? screen.frame.minX - width : screen.frame.maxX
        return f
    }

    private func screenUnderCursor() -> NSScreen? {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    func show() {
        guard let panel, let screen = screenUnderCursor() else { return }
        ShelfStore.shared.refresh()
        let target = targetFrame(on: screen)
        if !isVisible {
            panel.setFrame(offscreenFrame(from: target, on: screen), display: false)
            panel.alphaValue = 0
        }
        isVisible = true
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, isVisible else { return }
        isVisible = false
        let screen = panel.screen ?? screenUnderCursor()
        let end = screen.map { offscreenFrame(from: panel.frame, on: $0) } ?? panel.frame
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(end, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                if self?.isVisible == false { panel.orderOut(nil) }
            }
        })
    }

    /// Re-positions the visible shelf after the edge setting changes.
    func reposition() { if isVisible, let panel, let screen = panel.screen ?? screenUnderCursor() {
        panel.setFrame(targetFrame(on: screen), display: true, animate: true)
    } }

    func tearDown() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        cancellables.removeAll()
    }
}
