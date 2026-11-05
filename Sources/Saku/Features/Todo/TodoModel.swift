import AppKit
import Observation
import SwiftUI

/// A to-do list. Local only, or a Google Tasks list mirrored here (`remoteID`).
struct TodoList: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var remoteID: String?
    var dirty = false               // made here and not on Google yet
}

/// One task. Subtasks point at their parent (one level deep, like Google Tasks).
struct TodoItem: Codable, Identifiable, Equatable {
    var id: String
    var listID: String
    var title: String
    var notes = ""
    var due: Date?                  // a day; Google Tasks keeps no time
    var done = false
    var completed: Date?
    var parentID: String?
    var remoteID: String?
    var position = ""
    var created = Date()
    var updated = Date()
    var dirty = false               // changed here since the last sync
    var deleted = false             // removed here, waiting to be removed on Google
}

struct TodoData: Codable {
    var lists: [TodoList] = []
    var items: [TodoItem] = []
    var lastSync: Date?
}

/// The To-do tab: a local list that works on its own, and two-way sync with Google Tasks once Angel adds her own
/// OAuth client and signs in. Everything is cached in todo.json, so it opens offline too.
@MainActor @Observable
final class TodoModel {
    enum SyncState: Equatable { case local, idle, syncing, synced, offline, failed(String) }

    private(set) var data = TodoData()
    var selectedListID = ""
    var editingID: String?
    private(set) var syncState = SyncState.local

    @ObservationIgnored let auth: GoogleAuth
    @ObservationIgnored var api: TasksAPI
    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let store = JSONStore<TodoData>("todo.json")
    @ObservationIgnored private let saver = Debouncer(0.6)
    @ObservationIgnored private let pusher = Debouncer(2.0)
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored var now: () -> Date = Date.init

    nonisolated static let defaultListID = "local-default"

    init(app: AppModel, auth: GoogleAuth, api: TasksAPI) {
        self.app = app
        self.auth = auth
        self.api = api
        data = store.load() ?? TodoData()
        ensureDefaultList()
        selectedListID = data.lists.first?.id ?? Self.defaultListID
        syncState = auth.state == .signedIn ? .idle : .local
        if !app.options.qa {
            let t = Timer(timeInterval: 300, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.syncSoon(now: true) } }
            t.tolerance = 30
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    var googleOn: Bool { auth.state == .signedIn }

    /// Empty local list again (self tests and pictures).
    func reset() {
        data = TodoData()
        ensureDefaultList()
        selectedListID = Self.defaultListID
        editingID = nil
        syncState = googleOn ? .idle : .local
    }

    private func ensureDefaultList() {
        if data.lists.isEmpty { data.lists = [TodoList(id: Self.defaultListID, title: tr("My tasks"))] }
    }

    var lists: [TodoList] { data.lists }
    var selectedList: TodoList? { data.lists.first { $0.id == selectedListID } ?? data.lists.first }

    /// Open tasks first (in Google's order, or oldest first), each followed by its subtasks.
    func rows(in listID: String, done: Bool) -> [TodoItem] {
        let live = data.items.filter { $0.listID == listID && !$0.deleted }
        func order(_ a: TodoItem, _ b: TodoItem) -> Bool {
            if a.position != b.position, !a.position.isEmpty, !b.position.isEmpty { return a.position < b.position }
            return a.created < b.created
        }
        let parents = live.filter { $0.parentID == nil && $0.done == done }.sorted(by: order)
        var out: [TodoItem] = []
        for p in parents {
            out.append(p)
            out += live.filter { $0.parentID == p.id && (done || !$0.done) }.sorted(by: order)
        }
        if !done {
            // Open subtasks whose parent is already done still show, under nothing.
            let shown = Set(out.map(\.id))
            out += live.filter { $0.parentID != nil && !$0.done && !shown.contains($0.id) }.sorted(by: order)
        }
        return out
    }

    func openCount(_ listID: String) -> Int { data.items.filter { $0.listID == listID && !$0.deleted && !$0.done }.count }

    /// Open tasks due today or earlier, across every list (for the notch).
    var dueToday: [TodoItem] {
        let end = Calendar.current.startOfDay(for: now()).addingTimeInterval(86400)
        return data.items.filter { !$0.deleted && !$0.done && ($0.due.map { $0 < end } ?? false) }
    }

    // MARK: Editing

    @discardableResult
    func addList(_ title: String) -> TodoList? {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let l = TodoList(id: UUID().uuidString, title: t, dirty: true)
        data.lists.append(l)
        selectedListID = l.id
        changed()
        return l
    }

    /// Adds a task; a day in the title ("Pay rent Friday") becomes its due date.
    @discardableResult
    func add(_ text: String, listID: String? = nil, parentID: String? = nil, due: Date? = nil) -> TodoItem? {
        let parsed = QuickEvent.parse(text)
        let title = (parsed.date != nil ? parsed.title : text).trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        let day = due ?? parsed.date.map { Calendar.current.startOfDay(for: $0) }
        let item = TodoItem(id: UUID().uuidString, listID: listID ?? selectedList?.id ?? Self.defaultListID, title: title,
                            due: day, parentID: parentID, created: now(), updated: now(), dirty: true)
        data.items.append(item)
        changed()
        return item
    }

    func toggle(_ id: String) {
        edit(id) { t in
            t.done.toggle()
            t.completed = t.done ? self.now() : nil
        }
        // Finishing a task finishes its subtasks, like Google Tasks.
        if let t = item(id), t.done {
            for sub in data.items where sub.parentID == id && !sub.done { edit(sub.id) { $0.done = true; $0.completed = self.now() } }
        }
    }

    func rename(_ id: String, _ title: String) {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        edit(id) { $0.title = t }
    }

    func setNotes(_ id: String, _ notes: String) { edit(id) { $0.notes = notes } }
    func setDue(_ id: String, _ due: Date?) { edit(id) { $0.due = due.map { Calendar.current.startOfDay(for: $0) } } }

    func delete(_ id: String) {
        for k in data.items.indices where data.items[k].id == id || data.items[k].parentID == id {
            data.items[k].deleted = true
            data.items[k].dirty = true
            data.items[k].updated = now()
        }
        if editingID == id { editingID = nil }
        // Never on Google: just forget it.
        data.items.removeAll { $0.deleted && $0.remoteID == nil }
        changed()
    }

    func item(_ id: String) -> TodoItem? { data.items.first { $0.id == id } }

    private func edit(_ id: String, _ change: (inout TodoItem) -> Void) {
        guard let i = data.items.firstIndex(where: { $0.id == id }) else { return }
        change(&data.items[i])
        data.items[i].updated = now()
        data.items[i].dirty = true
        changed()
    }

    private func changed() {
        saver.run { [weak self] in self?.saveNow() }
        syncSoon()
    }

    func saveNow() { store.save(data) }

    // MARK: Sync with Google Tasks

    /// Debounced, so a burst of edits becomes one sync.
    func syncSoon(now immediately: Bool = false) {
        guard googleOn, !app.options.qa else { return }
        if immediately { Task { await sync() } } else { pusher.run { [weak self] in Task { await self?.sync() } } }
    }

    /// Push local changes, then pull everything. Offline keeps every change for the next try.
    func sync() async {
        guard googleOn else { syncState = .local; return }
        if syncState == .syncing { return }
        syncState = .syncing
        do {
            try await pushLists()
            try await pushItems()
            try await pull()
            data.lastSync = now()
            syncState = .synced
        } catch let e as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost].contains(e.code) {
            syncState = .offline
        } catch GoogleAuth.AuthError.signedOut {
            syncState = .failed(tr("Sign in to Google again in Settings › To-do."))
        } catch {
            syncState = .failed(GoogleAuth.describe(error))
        }
        saveNow()
    }

    private func pushLists() async throws {
        let remote = try await api.lists()
        for i in data.lists.indices where data.lists[i].remoteID == nil {
            // The first local list joins Google's default list; others become new Google lists.
            if data.lists[i].id == Self.defaultListID, let first = remote.first, !data.lists.contains(where: { $0.remoteID == first.id }) {
                data.lists[i].remoteID = first.id
                data.lists[i].title = first.title
            } else {
                let r = try await api.insertList(title: data.lists[i].title)
                data.lists[i].remoteID = r.id
            }
            data.lists[i].dirty = false
        }
    }

    private func pushItems() async throws {
        // Parents before subtasks, so a subtask can name its parent's Google id.
        let order = data.items.indices.filter { data.items[$0].dirty }.sorted { (data.items[$0].parentID == nil ? 0 : 1) < (data.items[$1].parentID == nil ? 0 : 1) }
        for i in order {
            let t = data.items[i]
            guard let list = data.lists.first(where: { $0.id == t.listID })?.remoteID else { continue }
            if t.deleted {
                if let rid = t.remoteID { try await api.delete(list: list, task: rid) }
                continue
            }
            var r = RemoteTask(id: t.remoteID ?? "", title: t.title, notes: t.notes, done: t.done, due: t.due, completed: t.completed)
            if t.remoteID == nil {
                let parent = t.parentID.flatMap { pid in data.items.first { $0.id == pid }?.remoteID }
                r = try await api.insert(list: list, task: r, parent: parent)
                data.items[i].remoteID = r.id
            } else {
                r = try await api.patch(list: list, task: r)
            }
            data.items[i].position = r.position
            data.items[i].dirty = false
        }
        data.items.removeAll { $0.deleted }
    }

    private func pull() async throws {
        let remoteLists = try await api.lists()
        var keep: [TodoList] = []
        for r in remoteLists {
            if var l = data.lists.first(where: { $0.remoteID == r.id }) {
                l.title = r.title
                keep.append(l)
            } else {
                keep.append(TodoList(id: UUID().uuidString, title: r.title, remoteID: r.id))
            }
        }
        // Lists deleted on Google go, with their tasks.
        let keptIDs = Set(keep.map(\.id))
        data.items.removeAll { !keptIDs.contains($0.listID) }
        data.lists = keep
        ensureDefaultList()
        if !data.lists.contains(where: { $0.id == selectedListID }) { selectedListID = data.lists.first?.id ?? Self.defaultListID }

        for list in data.lists {
            guard let rid = list.remoteID else { continue }
            let remote = try await api.tasks(list: rid).filter { !$0.deleted }
            merge(remote, into: list.id)
        }
    }

    /// Google wins unless the copy here changed more recently and hasn't been pushed yet.
    func merge(_ remote: [RemoteTask], into listID: String) {
        var seen = Set<String>()
        for r in remote {
            seen.insert(r.id)
            if let i = data.items.firstIndex(where: { $0.remoteID == r.id }) {
                if data.items[i].dirty && data.items[i].updated > r.updated { continue }
                data.items[i].title = r.title
                data.items[i].notes = r.notes
                data.items[i].done = r.done
                data.items[i].due = r.due
                data.items[i].completed = r.completed
                data.items[i].position = r.position
                data.items[i].listID = listID
                data.items[i].dirty = false
            } else {
                data.items.append(TodoItem(id: UUID().uuidString, listID: listID, title: r.title, notes: r.notes, due: r.due,
                                           done: r.done, completed: r.completed, remoteID: r.id, position: r.position,
                                           created: r.updated, updated: r.updated))
            }
        }
        // Parents by Google id, now that every task in the list has a local copy.
        let local = Dictionary(data.items.compactMap { t in t.remoteID.map { ($0, t.id) } }, uniquingKeysWith: { a, _ in a })
        for r in remote {
            guard let i = data.items.firstIndex(where: { $0.remoteID == r.id }) else { continue }
            data.items[i].parentID = r.parent.flatMap { local[$0] }
        }
        // Gone on Google, unchanged here: gone here too.
        data.items.removeAll { $0.listID == listID && $0.remoteID != nil && !seen.contains($0.remoteID!) && !$0.dirty }
    }

    /// After signing in, sync right away; after signing out, keep only the lists that were never on Google.
    func googleChanged() {
        if googleOn {
            syncState = .idle
            Task { await sync() }
        } else {
            let googleLists = Set(data.lists.filter { $0.remoteID != nil }.map(\.id))
            data.items.removeAll { googleLists.contains($0.listID) }
            data.lists.removeAll { $0.remoteID != nil }
            ensureDefaultList()
            selectedListID = data.lists.first?.id ?? Self.defaultListID
            syncState = .local
            saveNow()
        }
    }

    func liveActivity() -> LiveActivity? {
        guard app.prefs.v.todoInNotch else { return nil }
        let n = dueToday.count
        return n > 0 ? .todo(count: n) : nil
    }

    /// Demo content for pictures, in English.
    func loadDemo(google: Bool) {
        let day = Calendar.current.startOfDay(for: now())
        func d(_ n: Int) -> Date { day.addingTimeInterval(Double(n) * 86400) }
        data = TodoData(lists: [TodoList(id: Self.defaultListID, title: google ? "My Tasks" : tr("My tasks"), remoteID: google ? "gl-default" : nil),
                                TodoList(id: "l-uni", title: "Uni", remoteID: google ? "gl-uni" : nil),
                                TodoList(id: "l-home", title: "Home", remoteID: google ? "gl-home" : nil)])
        var n = 0
        func add(_ title: String, _ list: String = Self.defaultListID, due: Date? = nil, done: Bool = false, parent: String? = nil) -> String {
            n += 1
            let id = "t\(n)"
            data.items.append(TodoItem(id: id, listID: list, title: title, due: due, done: done, parentID: parent,
                                       remoteID: google ? "g\(n)" : nil, position: String(format: "%04d", n),
                                       created: day.addingTimeInterval(Double(n)), updated: day))
            return id
        }
        _ = add("Submit the thesis chapter", due: d(0))
        let trip = add("Pack for the Bali trip", due: d(2))
        _ = add("Swimsuit", parent: trip)
        _ = add("Phone charger", done: true, parent: trip)
        _ = add("Reply to itch.io comments", due: d(-1))
        _ = add("Buy matcha")
        _ = add("Book the dentist", done: true)
        _ = add("Read chapter 4", "l-uni", due: d(1))
        selectedListID = Self.defaultListID
        data.lastSync = google ? now().addingTimeInterval(-120) : nil
        syncState = google ? .synced : .local
    }
}
