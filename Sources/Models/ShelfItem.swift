import AppKit

/// One thing parked on the shelf: a file reference, a saved image, a piece of text or a web link.
struct ShelfItem: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case file, image, text, link }

    var id = UUID()
    var kind: Kind
    var name: String
    /// Current on-disk location for file and image items.
    var path: String?
    /// Where the file originally came from (used for duplicate detection).
    var originalPath: String?
    /// Bookmark so references survive moves and relaunches.
    var bookmark: Data?
    /// Text content or link string.
    var text: String?
    /// True when the file lives in the app's private folder and is owned by the shelf.
    var isPrivateCopy = false

    var fileURL: URL? { path.map { URL(fileURLWithPath: $0) } }

    var isMissing: Bool {
        guard let path else { return false }
        return !FileManager.default.fileExists(atPath: path)
    }

    var dedupKey: String { originalPath ?? path ?? text ?? id.uuidString }

    var subtitle: String {
        switch kind {
        case .file: return isPrivateCopy ? "Copied file" : (fileURL?.deletingLastPathComponent().path ?? "File")
        case .image: return "Image"
        case .text: return text ?? ""
        case .link: return text ?? ""
        }
    }

    /// Object written to the pasteboard when the item is dragged out.
    var pasteboardWriter: NSPasteboardWriting? {
        switch kind {
        case .file, .image: return fileURL.map { $0 as NSURL }
        case .link: return text.flatMap { URL(string: $0) }.map { $0 as NSURL }
        case .text: return text.map { $0 as NSString }
        }
    }
}
