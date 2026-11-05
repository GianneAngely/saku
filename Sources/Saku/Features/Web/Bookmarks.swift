import AppKit
import Observation
import SwiftUI

struct Bookmark: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var url: String

    var host: String { URL(string: url)?.host()?.replacingOccurrences(of: "www.", with: "") ?? url }
    var initial: String { String((title.isEmpty ? host : title).prefix(1)).uppercased() }

    /// A stable colour per site.
    var tint: Color {
        let palette = [Theme.blossom, Theme.sky, Theme.butter, Theme.lavender, Theme.mint, Theme.coral]
        let hash = host.unicodeScalars.reduce(UInt64(5381)) { ($0 << 5) &+ $0 &+ UInt64($1.value) }
        return palette[Int(hash % UInt64(palette.count))]
    }
}

@MainActor @Observable
final class BookmarksModel {
    private(set) var items: [Bookmark] = []
    @ObservationIgnored private let store = JSONStore<[Bookmark]>("bookmarks.json")

    init() { items = store.load() ?? [] }

    func contains(_ url: String) -> Bool { items.contains { $0.url == url } }

    func toggle(title: String, url: String) {
        guard !url.isEmpty, URL(string: url)?.scheme?.hasPrefix("http") == true else { return }
        if let i = items.firstIndex(where: { $0.url == url }) { items.remove(at: i) } else {
            items.append(Bookmark(title: title.isEmpty ? (URL(string: url)?.host() ?? url) : title, url: url))
        }
        store.save(items)
    }

    func update(_ b: Bookmark) {
        guard let i = items.firstIndex(where: { $0.id == b.id }) else { return }
        items[i] = b
        store.save(items)
    }

    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        store.save(items)
    }

    func move(from: IndexSet, to: Int) {
        items.move(fromOffsets: from, toOffset: to)
        store.save(items)
    }
}

struct BookmarkStar: View {
    let app: AppModel
    var body: some View {
        let w = app.web!
        let url = w.url?.absoluteString ?? ""
        let on = app.bookmarks.contains(url)
        IconButton(symbol: on ? "star.fill" : "star", size: 11, tint: on ? Theme.butter : Theme.text2, hit: 24,
                   help: on ? tr("Remove bookmark") : tr("Bookmark this page")) {
            app.bookmarks.toggle(title: w.title, url: url)
        }
        .disabled(w.blank)
    }
}

struct BookmarkGrid: View {
    let app: AppModel
    var body: some View {
        let b = app.bookmarks!
        if b.items.isEmpty {
            Text(tr("Star a page to keep it here.")).font(Theme.font(11)).foregroundStyle(Theme.text3)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(84), spacing: 10), count: 6), spacing: 10) {
                    ForEach(b.items) { item in
                        Button { app.web.load(URL(string: item.url)!) } label: {
                            VStack(spacing: 5) {
                                Text(item.initial).font(Theme.font(18, .heavy)).foregroundStyle(Color.black.opacity(0.8))
                                    .frame(width: 40, height: 40)
                                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(item.tint))
                                Text(item.title).font(Theme.font(10.5, .medium)).foregroundStyle(Theme.text2).lineLimit(1)
                            }
                            .frame(width: 84)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(item.url)
                        .contextMenu {
                            Button(tr("Open in your browser")) { if let u = URL(string: item.url) { NSWorkspace.shared.open(u) } }
                            Button(tr("Copy link")) { app.clipboard?.copy(text: item.url) }
                            Divider()
                            Button(tr("Delete"), role: .destructive) { b.delete(item.id) }
                        }
                    }
                }
            }
        }
    }
}

struct BookmarksSection: View {
    let app: AppModel
    var body: some View {
        let b = app.bookmarks!
        Section(tr("Bookmarks")) {
            if b.items.isEmpty { Text(tr("Star pages in the Web tab to add them.")).foregroundStyle(.secondary) }
            List {
                ForEach(b.items) { item in
                    HStack {
                        TextField("", text: Binding(get: { item.title }, set: { t in var n = item; n.title = t; b.update(n) })).frame(width: 160)
                        TextField("", text: Binding(get: { item.url }, set: { t in var n = item; n.url = t; b.update(n) }))
                        Button(role: .destructive) { b.delete(item.id) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                }
                .onMove { b.move(from: $0, to: $1) }
            }
            .frame(minHeight: CGFloat(max(1, b.items.count)) * 30)
        }
    }
}
