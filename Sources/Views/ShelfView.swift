import SwiftUI
import UniformTypeIdentifiers

/// The shelf's content: header with group drag and clear actions, the item list, and the drop target.
struct ShelfView: View {
    @EnvironmentObject private var store: ShelfStore
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 8) {
            header
            if store.items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(store.items) { ShelfRow(item: $0) }
                    }
                }
            }
            if store.isImporting {
                ProgressView(value: store.progress)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isTargeted && !store.items.isEmpty ? Color.accentColor : Color.primary.opacity(0.1),
                              lineWidth: isTargeted ? 2 : 1)
        )
        .onDrop(of: ShelfStore.acceptedTypes, isTargeted: $isTargeted) { providers in
            store.importProviders(providers)
            return true
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down.fill").foregroundStyle(Color.accentColor)
            Text("Shelf").font(.headline)
            if !store.items.isEmpty {
                Text("\(store.items.count)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if store.items.count > 1 {
                Image(systemName: "square.stack.3d.up.fill")
                    .frame(width: 22, height: 22)
                    .overlay(DragOutSource { store.items })
                    .help("Drag all items at once")
            }
            Button { store.clearAll() } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .disabled(store.items.isEmpty)
                .help("Clear shelf")
            Button { ShelfPanelController.shared.hide() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Hide shelf")
        }
    }

    private var emptyState: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.5),
                          style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc").font(.title)
                    Text("Drop files here").font(.callout)
                }
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
            )
            .animation(.easeOut(duration: 0.15), value: isTargeted)
    }
}

/// A single shelf entry with thumbnail, name, two-line preview and remove button.
struct ShelfRow: View {
    let item: ShelfItem
    @EnvironmentObject private var store: ShelfStore
    @State private var thumbnail: NSImage?
    @State private var hovering = false

    var body: some View {
        let missing = item.isMissing
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(nsImage: thumbnail ?? Thumbnailer.icon(for: item))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name).font(.callout).lineLimit(1).truncationMode(.middle)
                    if missing {
                        Text("Missing").font(.caption2).foregroundStyle(.red)
                    } else {
                        Text(item.subtitle).font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(item.kind == .text || item.kind == .link ? 2 : 1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 0)
            }
            .opacity(missing ? 0.4 : 1)
            .contentShape(Rectangle())
            .overlay { if !missing { DragOutSource { [item] } } }

            Button { store.remove([item.id]) } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .opacity(hovering || missing ? 1 : 0.35)
                .help("Remove from shelf")
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(hovering ? 0.08 : 0.03)))
        .onHover { hovering = $0 }
        .task(id: item.path) { thumbnail = await Thumbnailer.thumbnail(for: item) }
    }
}
