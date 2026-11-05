import SwiftUI

/// Reusable text, grouped into collections. Click to copy, edit on the right.
struct SnippetsView: View {
    let app: AppModel
    let query: String
    @State private var collection: String?
    @State private var editing: Snippet?
    @State private var newCollection = ""

    var body: some View {
        let clip = app.clipboard!
        let list = clip.snippets(in: collection, matching: query)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                CollectionChip(title: tr("All"), count: clip.snippets.count, on: collection == nil) { collection = nil }
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(clip.collections, id: \.self) { c in
                            CollectionChip(title: c, count: clip.snippets(in: c).count, on: collection == c) { collection = c }
                                .contextMenu { Button(tr("Delete collection"), role: .destructive) { clip.deleteCollection(c); if collection == c { collection = nil } } }
                        }
                    }
                }
                NotchField(placeholder: tr("New collection"), text: $newCollection, icon: "plus") {
                    clip.addCollection(newCollection)
                    collection = newCollection.trimmingCharacters(in: .whitespaces)
                    newCollection = ""
                }
            }
            .frame(width: 128)

            VStack(spacing: 6) {
                if list.isEmpty {
                    EmptyState(icon: "text.badge.plus", title: tr("No snippets"), subtitle: tr("Save text you type often."), tint: Theme.sky)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 2) {
                            ForEach(list) { s in
                                SnippetRow(snippet: s, on: editing?.id == s.id)
                                    .onTapGesture(count: 2) { copy(s) }
                                    .onTapGesture { editing = s }
                                    .contextMenu {
                                        Button(tr("Copy")) { copy(s) }
                                        Button(tr("Delete"), role: .destructive) { clip.deleteSnippet(s); if editing?.id == s.id { editing = nil } }
                                    }
                            }
                        }
                    }
                }
                PillButton(title: tr("New snippet"), icon: "plus", compact: true) {
                    editing = clip.addSnippet(title: tr("New snippet"), text: "", collection: collection ?? "")
                }
            }
            .frame(width: 190)

            if let s = editing, clip.snippets.contains(where: { $0.id == s.id }) {
                SnippetEditor(app: app, snippet: s) { copy($0) } onDelete: {
                    clip.deleteSnippet(s)
                    editing = nil
                }
                .id(s.id)
            } else {
                Card(padding: 10) {
                    EmptyState(icon: "text.cursor", title: tr("Pick a snippet"), subtitle: tr("Double-click any snippet to copy it."), tint: Theme.sky)
                }
            }
        }
    }

    private func copy(_ s: Snippet) {
        app.clipboard.copy(text: s.text)
        app.flash("checkmark.circle.fill", tr("Copied"), tint: Theme.mint)
    }
}

struct CollectionChip: View {
    var title: String
    var count: Int
    var on: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: on ? "folder.fill" : "folder").font(.system(size: 10.5)).foregroundStyle(on ? Theme.sky : Theme.text3)
                Text(title).font(Theme.font(11.5, on ? .semibold : .medium)).foregroundStyle(on ? Theme.text : Theme.text2).lineLimit(1)
                Spacer(minLength: 2)
                Text("\(count)").font(Theme.mono(10)).foregroundStyle(Theme.text3)
            }
            .padding(.horizontal, 8).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? Theme.cardHi : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SnippetRow: View {
    let snippet: Snippet
    let on: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(snippet.title).font(Theme.font(11.5, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
            Text(snippet.text.isEmpty ? " " : snippet.text.replacingOccurrences(of: "\n", with: " "))
                .font(Theme.font(10.5)).foregroundStyle(Theme.text3).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? Theme.cardHi : Color.white.opacity(0.03)))
        .contentShape(Rectangle())
    }
}

struct SnippetEditor: View {
    let app: AppModel
    @State var snippet: Snippet
    let onCopy: (Snippet) -> Void
    let onDelete: () -> Void

    var body: some View {
        let clip = app.clipboard!
        Card(padding: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    TextField("", text: $snippet.title, prompt: Text(tr("Title")).foregroundStyle(Theme.text3))
                        .textFieldStyle(.plain).font(Theme.font(12.5, .semibold)).foregroundStyle(Theme.text)
                    Menu {
                        Button(tr("No collection")) { snippet.collection = "" }
                        ForEach(clip.collections, id: \.self) { c in Button(c) { snippet.collection = c } }
                    } label: {
                        Text(snippet.collection.isEmpty ? tr("No collection") : snippet.collection).font(Theme.font(10.5, .semibold))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                TextEditor(text: $snippet.text)
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.text)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(Theme.cardHi, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                HStack(spacing: 6) {
                    IconButton(symbol: "trash", size: 10.5, tint: Theme.text3, hit: 24, help: tr("Delete"), action: onDelete)
                    Spacer()
                    PillButton(title: tr("Copy"), icon: "doc.on.doc", primary: true, tint: Theme.sky, compact: true) { onCopy(snippet) }
                }
            }
        }
        .onChange(of: snippet) { _, s in clip.updateSnippet(s) }
    }
}
