import AppKit

/// Watches global mouse drags and reveals the shelf when a real drag-and-drop reaches the chosen screen edge.
final class EdgeDragMonitor {
    static let shared = EdgeDragMonitor()

    private var monitors: [Any] = []
    private var dragChangeCount = 0
    private var triggered = false

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }
        if let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            self?.dragChangeCount = NSPasteboard(name: .drag).changeCount
            self?.triggered = false
        }) { monitors.append(down) }
        if let drag = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] _ in
            self?.handleDrag()
        }) { monitors.append(drag) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func handleDrag() {
        // Only react when the drag pasteboard changed, i.e. a drag session started (not window moves).
        guard !triggered, NSPasteboard(name: .drag).changeCount != dragChangeCount else { return }
        let loc = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(loc, $0.frame, false) }) else { return }
        let nearEdge = Prefs.edge == .left ? loc.x <= screen.frame.minX + 4 : loc.x >= screen.frame.maxX - 5
        if nearEdge {
            triggered = true
            ShelfPanelController.shared.show()
        }
    }
}
