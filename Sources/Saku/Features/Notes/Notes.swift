import AppKit
import Observation
import SwiftUI

struct Note: Codable, Identifiable, Equatable {
    var id = UUID()
    var text = ""
    var updated = Date()
    var pinned = false

    var title: String {
        let first = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
        guard let line = first else { return tr("New note") }
        return line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
    }

    var preview: String {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.dropFirst().first ?? ""
    }

    var words: Int { text.split { $0.isWhitespace || $0.isNewline }.count }
}

@MainActor @Observable
final class NotesModel {
    private(set) var notes: [Note] = []
    var selected: UUID?

    @ObservationIgnored private let store = JSONStore<[Note]>("notes.json")
    @ObservationIgnored private let saver = Debouncer(0.5)

    init() {
        notes = store.load() ?? []
        if notes.isEmpty {
            notes = [Note(text: tr("Welcome to Notes\nEverything you type here saves by itself."))]
        }
        selected = sorted.first?.id
    }

    /// Pinned first, then most recently edited.
    var sorted: [Note] {
        notes.sorted { a, b in a.pinned != b.pinned ? a.pinned : a.updated > b.updated }
    }

    var current: Note? { notes.first { $0.id == selected } }

    @discardableResult
    func add(_ text: String = "") -> Note {
        let n = Note(text: text)
        notes.append(n)
        selected = n.id
        changed()
        return n
    }

    func update(_ id: UUID, text: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }), notes[i].text != text else { return }
        notes[i].text = text
        notes[i].updated = Date()
        changed()
    }

    func togglePin(_ id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].pinned.toggle()
        changed()
    }

    func delete(_ id: UUID) {
        notes.removeAll { $0.id == id }
        if selected == id { selected = sorted.first?.id }
        if notes.isEmpty { add() }
        changed()
    }

    /// Drops notes that were created and left empty.
    func removeEmpty(except keep: UUID? = nil) {
        let empties = notes.filter { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.id != keep }
        guard !empties.isEmpty, notes.count > empties.count else { return }
        notes.removeAll { e in empties.contains { $0.id == e.id } }
        changed()
    }

    private func changed() { saver.run { [weak self] in self?.saveNow() } }
    func saveNow() { store.save(notes) }
}

struct NotesView: View {
    let app: AppModel

    var body: some View {
        let m = app.notes!
        HStack(spacing: 10) {
            VStack(spacing: 6) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(m.sorted) { n in
                            NoteRow(note: n, on: n.id == m.selected, now: app.clock)
                                .onTapGesture {
                                    m.removeEmpty(except: n.id)
                                    m.selected = n.id
                                }
                                .contextMenu {
                                    Button(n.pinned ? tr("Unpin") : tr("Pin")) { m.togglePin(n.id) }
                                    Button(tr("Copy text")) { app.clipboard?.copy(text: n.text) }
                                    Divider()
                                    Button(tr("Delete"), role: .destructive) { m.delete(n.id) }
                                }
                        }
                    }
                }
                PillButton(title: tr("New note"), icon: "square.and.pencil", compact: true) {
                    m.removeEmpty()
                    m.add()
                }
            }
            .frame(width: 176)

            if let n = m.current {
                NoteEditor(app: app, note: n).id(n.id)
            }
        }
    }
}

struct NoteRow: View {
    let note: Note
    let on: Bool
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                if note.pinned { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(Theme.butter) }
                Text(note.title).font(Theme.font(11.5, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
            }
            HStack(spacing: 4) {
                Text(RelativeTime.short(note.updated, now: max(now, note.updated))).font(Theme.mono(10)).foregroundStyle(Theme.text3)
                Text(note.preview).font(Theme.font(10.5)).foregroundStyle(Theme.text3).lineLimit(1)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? Theme.cardHi : .clear))
        .contentShape(Rectangle())
    }
}

struct NoteEditor: View {
    let app: AppModel
    let note: Note
    @State private var text = ""

    var body: some View {
        let m = app.notes!
        Card(padding: 8) {
            VStack(spacing: 4) {
                TextEditor(text: $text)
                    .font(Theme.font(app.prefs.v.notesFontSize))
                    .foregroundStyle(Theme.text)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                HStack(spacing: 6) {
                    if app.prefs.v.notesWordCount {
                        Text(tr("%d words", Note(text: text).words)).font(Theme.mono(10)).foregroundStyle(Theme.text3)
                    }
                    Text(tr("Saved")).font(Theme.font(10)).foregroundStyle(Theme.text3)
                    Spacer()
                    IconButton(symbol: note.pinned ? "pin.fill" : "pin", size: 10.5, tint: note.pinned ? Theme.butter : Theme.text3, hit: 22, help: tr("Pin")) { m.togglePin(note.id) }
                    IconButton(symbol: "doc.on.doc", size: 10.5, tint: Theme.text3, hit: 22, help: tr("Copy text")) {
                        app.clipboard?.copy(text: text)
                        app.flash("checkmark.circle.fill", tr("Copied"), tint: Theme.mint)
                    }
                    IconButton(symbol: "trash", size: 10.5, tint: Theme.text3, hit: 22, help: tr("Delete")) { m.delete(note.id) }
                }
            }
        }
        .onAppear { text = note.text }
        .onChange(of: text) { _, t in m.update(note.id, text: t) }
    }
}

struct NotesPane: View {
    let app: AppModel
    var body: some View {
        @Bindable var prefs = app.prefs
        Form {
            Section {
                SliderRow(title: tr("Text size"), value: $prefs.v.notesFontSize, range: 11...18) { "\(Int($0)) pt" }
                Toggle(tr("Show word count"), isOn: $prefs.v.notesWordCount)
            } footer: {
                Text(tr("Notes save as you type, in Saku's data folder on this Mac."))
            }
        }
        .formStyle(.grouped)
    }
}
