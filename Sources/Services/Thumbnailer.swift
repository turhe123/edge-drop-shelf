import AppKit
import QuickLookThumbnailing

/// Produces item previews with QuickLookThumbnailing, falling back to Finder icons and SF Symbols.
enum Thumbnailer {
    static func icon(for item: ShelfItem) -> NSImage {
        switch item.kind {
        case .text: return symbol("text.alignleft")
        case .link: return symbol("link")
        case .file, .image:
            guard let path = item.path, !item.isMissing else { return symbol("questionmark.folder") }
            return NSWorkspace.shared.icon(forFile: path)
        }
    }

    static func thumbnail(for item: ShelfItem, size: CGFloat = 40) async -> NSImage {
        guard let url = item.fileURL, !item.isMissing else { return icon(for: item) }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2,
                                                   representationTypes: .all)
        if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            return rep.nsImage
        }
        return icon(for: item)
    }

    private static func symbol(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage(size: NSSize(width: 32, height: 32))
    }
}
