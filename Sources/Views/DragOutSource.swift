import AppKit
import SwiftUI

/// AppKit dragging source that drags one or many shelf items out to other apps and
/// reports successful drops so items can be auto-removed.
final class DragSourceView: NSView, NSDraggingSource {
    var itemsProvider: () -> [ShelfItem] = { [] }
    private var mouseDownEvent: NSEvent?
    private var draggedIDs: [UUID] = []

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        if event.clickCount == 2 {
            mouseDownEvent = nil
            openItems()
        }
    }

    override func mouseUp(with event: NSEvent) { mouseDownEvent = nil }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent else { return }
        let dx = event.locationInWindow.x - down.locationInWindow.x
        let dy = event.locationInWindow.y - down.locationInWindow.y
        guard hypot(dx, dy) > 3 else { return }
        mouseDownEvent = nil

        let items = itemsProvider().filter { !$0.isMissing }
        let start = convert(down.locationInWindow, from: nil)
        var dragItems: [NSDraggingItem] = []
        for (index, item) in items.enumerated() {
            guard let writer = item.pasteboardWriter else { continue }
            let dragItem = NSDraggingItem(pasteboardWriter: writer)
            let offset = CGFloat(min(index, 6)) * 4
            dragItem.setDraggingFrame(NSRect(x: start.x - 16 + offset, y: start.y - 16 - offset, width: 32, height: 32),
                                      contents: Thumbnailer.icon(for: item))
            dragItems.append(dragItem)
        }
        guard !dragItems.isEmpty else { return }
        draggedIDs = items.map(\.id)
        beginDraggingSession(with: dragItems, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .generic, .link] : .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let ids = draggedIDs
        draggedIDs = []
        // Ignore cancelled drags and drops back onto the shelf itself.
        guard operation != [], !(window?.frame.contains(screenPoint) ?? false) else { return }
        DispatchQueue.main.async { ShelfStore.shared.didDragOut(ids) }
    }

    private func openItems() {
        for item in itemsProvider() where !item.isMissing {
            if let url = item.fileURL {
                NSWorkspace.shared.open(url)
            } else if item.kind == .link, let url = item.text.flatMap(URL.init(string:)) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

/// SwiftUI wrapper that overlays a transparent drag source on a row or on the group handle.
struct DragOutSource: NSViewRepresentable {
    let items: () -> [ShelfItem]

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        view.itemsProvider = items
        return view
    }

    func updateNSView(_ view: DragSourceView, context: Context) {
        view.itemsProvider = items
    }
}
