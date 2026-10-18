import AppKit
import UniformTypeIdentifiers

/// Owns the shelf contents: importing drops, removing items, persisting metadata as JSON
/// and managing the private folder used for copied files and saved images.
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()
    static let acceptedTypes: [UTType] = [.fileURL, .image, .url, .plainText]

    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var isImporting = false
    @Published private(set) var progress: Double = 0

    private let baseDir: URL
    private let filesDir: URL
    private var metadataURL: URL { baseDir.appendingPathComponent("items.json") }

    /// Raw content extracted from a dropped NSItemProvider.
    enum Payload { case file(URL), link(URL), text(String), image(Data) }

    enum ImportError: LocalizedError {
        case diskFull(String), copyFailed(String, String)
        var errorDescription: String? {
            switch self {
            case .diskFull(let name): return "There is not enough disk space to copy “\(name)”."
            case .copyFailed(let name, let reason): return "“\(name)” could not be copied: \(reason)"
            }
        }
    }

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        baseDir = support.appendingPathComponent("EdgeDropShelf", isDirectory: true)
        filesDir = baseDir.appendingPathComponent("Files", isDirectory: true)
        try? FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL),
              var decoded = try? JSONDecoder().decode([ShelfItem].self, from: data) else { return }
        for i in decoded.indices {
            guard let bookmark = decoded[i].bookmark else { continue }
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI],
                                  relativeTo: nil, bookmarkDataIsStale: &stale) {
                decoded[i].path = url.path
                if stale { decoded[i].bookmark = try? url.bookmarkData() }
            }
        }
        items = decoded
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            NSLog("EdgeDropShelf: failed to save shelf: \(error.localizedDescription)")
        }
    }

    /// Re-publishes so rows re-check whether referenced files still exist.
    func refresh() { objectWillChange.send() }

    // MARK: Removing

    func remove(_ ids: [UUID]) {
        let removing = items.filter { ids.contains($0.id) }
        removing.forEach(deletePrivateCopy)
        items.removeAll { ids.contains($0.id) }
        save()
    }

    func didDragOut(_ ids: [UUID]) {
        if Prefs.autoRemove { remove(ids) }
    }

    /// Clears everything, asking first when private copies would be deleted.
    func clearAll() {
        guard !items.isEmpty else { return }
        if items.contains(where: \.isPrivateCopy) {
            let alert = NSAlert()
            alert.messageText = "Clear the shelf?"
            alert.informativeText = "Copied files and saved images stored by EdgeDropShelf will be permanently deleted."
            alert.addButton(withTitle: "Clear")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        remove(items.map(\.id))
    }

    private func deletePrivateCopy(_ item: ShelfItem) {
        guard item.isPrivateCopy, let folder = item.fileURL?.deletingLastPathComponent(),
              folder.path.hasPrefix(filesDir.path) else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: Importing

    /// Loads dropped providers, then converts them into items on a background queue.
    func importProviders(_ providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        let copy = Prefs.copyFiles
        let limit = Prefs.maxItems
        let filesDir = self.filesDir
        Task { @MainActor in
            isImporting = true
            progress = 0
            var errors: [String] = []
            var hitLimit = false
            let total = Double(providers.count)
            for (index, provider) in providers.enumerated() {
                defer { progress = Double(index + 1) / total }
                guard let payload = await Self.loadPayload(provider) else { continue }
                guard items.count < limit else { hitLimit = true; break }
                if case .file(let url) = payload, items.contains(where: { $0.dedupKey == url.path }) { continue }
                if case .text(let s) = payload, items.contains(where: { $0.kind == .text && $0.text == s }) { continue }
                if case .link(let u) = payload, items.contains(where: { $0.kind == .link && $0.text == u.absoluteString }) { continue }
                do {
                    let item = try await Task.detached(priority: .userInitiated) {
                        try Self.makeItem(payload, copy: copy, filesDir: filesDir)
                    }.value
                    items.append(item)
                } catch {
                    errors.append(error.localizedDescription)
                }
            }
            isImporting = false
            save()
            if hitLimit { errors.append("The shelf is full (maximum \(limit) items). Remove items or raise the limit in Settings.") }
            if !errors.isEmpty { Self.showAlert("Some items were not added", errors.joined(separator: "\n")) }
        }
    }

    private static func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    private static func loadPayload(_ provider: NSItemProvider) async -> Payload? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = await loadURL(provider), url.isFileURL {
            return .file(url)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
           let data = await loadData(provider, type: .image),
           let image = NSImage(data: data), let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            return .image(png)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = await loadURL(provider) {
            return url.isFileURL ? .file(url) : .link(url)
        }
        if provider.canLoadObject(ofClass: String.self), let text = await loadString(provider),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
               let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
                return .link(url)
            }
            return .text(text)
        }
        return nil
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { cont in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in cont.resume(returning: url) }
        }
    }

    private static func loadString(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { cont in
            _ = provider.loadObject(ofClass: String.self) { text, _ in cont.resume(returning: text) }
        }
    }

    private static func loadData(_ provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { cont in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                cont.resume(returning: data)
            }
        }
    }

    /// Builds a shelf item, copying files into the private folder when requested. Runs off the main thread.
    private static func makeItem(_ payload: Payload, copy: Bool, filesDir: URL) throws -> ShelfItem {
        let fm = FileManager.default
        switch payload {
        case .file(let url):
            let name = url.lastPathComponent
            guard copy else {
                return ShelfItem(kind: .file, name: name, path: url.path, originalPath: url.path,
                                 bookmark: try? url.bookmarkData())
            }
            let dest = filesDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent(name)
            do {
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: url, to: dest)
            } catch {
                try? fm.removeItem(at: dest.deletingLastPathComponent())
                let ns = error as NSError
                if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError { throw ImportError.diskFull(name) }
                throw ImportError.copyFailed(name, error.localizedDescription)
            }
            return ShelfItem(kind: .file, name: name, path: dest.path, originalPath: url.path,
                             bookmark: try? dest.bookmarkData(), isPrivateCopy: true)
        case .image(let data):
            let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                .replacingOccurrences(of: ":", with: ".")
            let name = "Image \(stamp).png"
            let dest = filesDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent(name)
            do {
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: dest, options: .atomic)
            } catch {
                try? fm.removeItem(at: dest.deletingLastPathComponent())
                let ns = error as NSError
                if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError { throw ImportError.diskFull(name) }
                throw ImportError.copyFailed(name, error.localizedDescription)
            }
            return ShelfItem(kind: .image, name: name, path: dest.path, isPrivateCopy: true)
        case .link(let url):
            return ShelfItem(kind: .link, name: url.host ?? url.absoluteString, text: url.absoluteString)
        case .text(let text):
            let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
            return ShelfItem(kind: .text, name: String(firstLine.prefix(60)), text: text)
        }
    }
}
