import AppKit
import SwiftUI

struct ClipboardView: View {
    let app: AppModel
    @State private var query = ""
    @State private var selection: UUID?
    @FocusState private var searchFocused: Bool

    var body: some View {
        let clip = app.clipboard!
        let items = clip.search(query)
        @Bindable var c = clip
        let mode = clip.mode
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text3)
                    TextField("", text: $query, prompt: Text(mode == 0 ? tr("Search clipboard") : tr("Search snippets")).foregroundStyle(Theme.text3))
                        .textFieldStyle(.plain).font(Theme.font(12)).foregroundStyle(Theme.text)
                        .focused($searchFocused)
                        .onKeyPress(.downArrow) { move(1, items); return .handled }
                        .onKeyPress(.upArrow) { move(-1, items); return .handled }
                        .onSubmit { if let id = selection ?? items.first?.id, let it = items.first(where: { $0.id == id }) { use(it) } }
                }
                .padding(.horizontal, 10).frame(height: 28)
                .background(Theme.cardHi, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .frame(maxWidth: 230)
                Segments(items: [(0, tr("History")), (1, tr("Snippets"))], selection: $c.mode, tint: Theme.sky)
                Spacer(minLength: 0)
                if mode == 0 {
                    IconButton(symbol: app.prefs.v.clipboardPaused ? "play.fill" : "pause.fill", size: 11,
                               tint: app.prefs.v.clipboardPaused ? Theme.butter : Theme.text3, hit: 26,
                               help: app.prefs.v.clipboardPaused ? tr("Resume recording") : tr("Pause recording")) {
                        app.prefs.v.clipboardPaused.toggle()
                    }
                    PillButton(title: tr("Clear"), icon: "trash", compact: true) { clip.clearHistory() }
                }
            }
            if mode == 0 {
                if !app.prefs.v.clipboardEnabled {
                    EmptyState(icon: "list.clipboard", title: tr("Clipboard history is off"), subtitle: tr("Turn it on in Settings > Clipboard."), tint: Theme.sky)
                } else if items.isEmpty {
                    EmptyState(icon: "doc.on.clipboard", title: query.isEmpty ? tr("Nothing copied yet") : tr("No matches"),
                               subtitle: query.isEmpty ? tr("Copy anything and it shows up here.") : "", tint: Theme.sky)
                } else {
                    HStack(spacing: 10) {
                        ClipList(app: app, items: items, selection: $selection, use: use)
                            .frame(maxWidth: app.prefs.v.clipboardPreview ? 290 : .infinity)
                        if app.prefs.v.clipboardPreview, let sel = items.first(where: { $0.id == (selection ?? items.first?.id) }) {
                            ClipPreview(app: app, item: sel, use: use)
                        }
                    }
                }
            } else {
                SnippetsView(app: app, query: query)
            }
        }
        .onAppear {
            selection = nil
            if app.notch.focusSearch {
                searchFocused = true
                app.notch.focusSearch = false
            }
        }
    }

    private func move(_ d: Int, _ items: [ClipItem]) {
        guard !items.isEmpty else { return }
        let i = items.firstIndex { $0.id == selection } ?? (d > 0 ? -1 : items.count)
        selection = items[max(0, min(items.count - 1, i + d))].id
    }

    /// Copies, then pastes into the front app when that is turned on and allowed.
    private func use(_ item: ClipItem) {
        app.clipboard.copy(item)
        if app.prefs.v.clipboardPasteDirect && Paster.trusted {
            app.commands.closeNotch()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { MainActor.assumeIsolated { Paster.pasteToFrontApp() } }
        } else {
            app.flash("checkmark.circle.fill", tr("Copied"), tint: Theme.mint)
        }
    }
}

struct ClipList: View {
    let app: AppModel
    let items: [ClipItem]
    @Binding var selection: UUID?
    let use: (ClipItem) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 1) {
                    ForEach(items) { item in
                        ClipRow(app: app, item: item, selected: item.id == (selection ?? items.first?.id))
                            .id(item.id)
                            .onTapGesture(count: 2) { use(item) }
                            .onTapGesture { if app.prefs.v.clipboardPreview { selection = item.id } else { use(item) } }
                            .contextMenu { ClipActions(app: app, item: item, use: use) }
                    }
                }
            }
            .onChange(of: selection) { _, id in if let id { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) } } }
        }
    }
}

struct ClipRow: View {
    let app: AppModel
    let item: ClipItem
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if item.kind == .image, let img = app.clipboard.image(of: item) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: item.icon).font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(item.kind == .link ? Theme.sky : Theme.text2)
                }
            }
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.06)))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(item.title).font(Theme.font(12, .medium)).foregroundStyle(Theme.text).lineLimit(1)
            Spacer(minLength: 4)
            if item.pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Theme.blossom) }
            Text(RelativeTime.short(item.date, now: app.clock)).font(Theme.mono(10, .medium)).foregroundStyle(Theme.text3)
        }
        .padding(.horizontal, 7)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(selected ? Theme.cardHi : Color.white.opacity(hovering ? 0.04 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

struct ClipPreview: View {
    let app: AppModel
    let item: ClipItem
    let use: (ClipItem) -> Void

    var body: some View {
        let clip = app.clipboard!
        Card(padding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    switch item.kind {
                    case .text, .link:
                        ScrollView(.vertical, showsIndicators: false) {
                            Text(item.text).font(Theme.font(12)).foregroundStyle(Theme.text)
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    case .image:
                        if let img = clip.image(of: item) {
                            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    case .files:
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(item.paths, id: \.self) { p in
                                    HStack(spacing: 6) {
                                        Image(nsImage: NSWorkspace.shared.icon(forFile: p)).resizable().frame(width: 16, height: 16)
                                        Text((p as NSString).lastPathComponent).font(Theme.font(11.5)).foregroundStyle(Theme.text).lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                HStack(spacing: 6) {
                    Text(meta).font(Theme.font(10)).foregroundStyle(Theme.text3).lineLimit(1)
                    Spacer(minLength: 4)
                    IconButton(symbol: item.pinned ? "pin.fill" : "pin", size: 10.5, tint: item.pinned ? Theme.blossom : Theme.text3, hit: 24, help: tr("Pin")) { clip.togglePin(item) }
                    IconButton(symbol: "trash", size: 10.5, tint: Theme.text3, hit: 24, help: tr("Delete")) { clip.delete(item) }
                    if item.kind == .image {
                        IconButton(symbol: "text.viewfinder", size: 11, tint: Theme.lavender, hit: 24, help: tr("Copy text from image")) {
                            OCR.copyText(from: clip.image(of: item), app: app)
                        }
                    }
                    PillButton(title: tr("Copy"), icon: "doc.on.doc", primary: true, tint: Theme.sky, compact: true) { use(item) }
                }
            }
        }
    }

    private var meta: String {
        var parts: [String] = []
        if !item.app.isEmpty { parts.append(item.app) }
        if item.kind == .text || item.kind == .link { parts.append(tr("%d characters", item.text.count)) }
        if item.rtfFile != nil { parts.append(tr("rich text")) }
        return parts.joined(separator: " · ")
    }
}

/// Context menu for a history row.
struct ClipActions: View {
    let app: AppModel
    let item: ClipItem
    let use: (ClipItem) -> Void

    var body: some View {
        let clip = app.clipboard!
        Button(tr("Copy")) { use(item) }
        if item.rtfFile != nil { Button(tr("Copy as plain text")) { clip.copy(item, plain: true) } }
        if item.kind == .link, let u = URL(string: item.text) { Button(tr("Open link")) { NSWorkspace.shared.open(u) } }
        if item.kind == .text || item.kind == .link {
            Button(tr("Save as snippet")) { _ = clip.saveAsSnippet(item); app.flash("text.badge.plus", tr("Saved as snippet")) }
        }
        ClipMenuExtras.view(app: app, item: item)
        Button(item.pinned ? tr("Unpin") : tr("Pin")) { clip.togglePin(item) }
        Divider()
        Button(tr("Delete"), role: .destructive) { clip.delete(item) }
    }
}

/// Menu items other features add (text from image).
@MainActor
enum ClipMenuExtras {
    @ViewBuilder static func view(app: AppModel, item: ClipItem) -> some View {
        if item.kind == .image {
            Button(tr("Copy text from image")) { OCR.copyText(from: app.clipboard.image(of: item), app: app) }
        }
    }
}

/// "now", "5m", "3h", "Yesterday", "Mon", "12 Oct".
enum RelativeTime {
    static func short(_ d: Date, now: Date = Date()) -> String {
        let s = now.timeIntervalSince(d)
        if s < 60 { return tr("now") }
        if s < 3600 { return "\(Int(s / 60))m" }
        let cal = Calendar.current
        if cal.isDateInToday(d) || s < 6 * 3600 { return "\(Int(s / 3600))h" }
        if cal.isDateInYesterday(d) { return tr("Yesterday") }
        let f = DateFormatter()
        f.locale = Lang.shared.isIndonesian ? Locale(identifier: "id_ID") : Locale(identifier: "en_US")
        f.setLocalizedDateFormatFromTemplate(s < 6 * 86400 ? "EEE" : "d MMM")
        return f.string(from: d)
    }
}
