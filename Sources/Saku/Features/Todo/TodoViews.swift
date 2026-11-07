import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TodoView: View {
    let app: AppModel
    @State private var draft = ""
    @State private var newList = ""
    @State private var addingList = false

    var body: some View {
        let m = app.todo!
        let list = m.selectedList
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(m.lists) { l in TodoListRow(app: app, list: l) }
                if addingList {
                    NotchField(placeholder: tr("New list"), text: $newList, icon: "list.bullet") {
                        m.addList(newList)
                        newList = ""
                        addingList = false
                    }
                } else {
                    Button { addingList = true } label: {
                        Label(tr("List"), systemImage: "plus").font(Theme.font(11, .semibold)).foregroundStyle(Theme.text3)
                            .padding(.horizontal, 8).frame(height: 24).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                TodoSyncBadge(app: app)
            }
            .frame(width: 150)
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(list?.title ?? tr("My tasks")).font(Theme.font(13, .bold)).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer()
                    IconButton(symbol: app.prefs.v.todoShowCompleted ? "eye.fill" : "eye.slash", size: 10.5, tint: Theme.text3, hit: 22,
                               help: app.prefs.v.todoShowCompleted ? tr("Hide completed") : tr("Show completed")) {
                        app.prefs.v.todoShowCompleted.toggle()
                    }
                }
                NotchField(placeholder: tr("Add a task, e.g. Pay rent Friday"), text: $draft, icon: "plus.circle.fill") {
                    m.add(draft)
                    draft = ""
                }
                let open = list.map { m.rows(in: $0.id, done: false) } ?? []
                let done = app.prefs.v.todoShowCompleted ? (list.map { m.rows(in: $0.id, done: true) } ?? []) : []
                if open.isEmpty && done.isEmpty {
                    EmptyState(icon: "checkmark.seal", title: tr("All clear"), subtitle: tr("Type above and press Return to add a task."), tint: Theme.mint)
                } else {
                    FadingList(spacing: 1) {
                        ForEach(open) { t in TodoRow(app: app, item: t) }
                        if !done.isEmpty {
                            Caption(text: tr("Completed (%d)", done.count)).padding(.top, 6)
                            ForEach(done) { t in TodoRow(app: app, item: t) }
                        }
                    }
                }
            }
        }
        .onAppear { m.syncSoon(now: true) }
    }
}

struct TodoListRow: View {
    let app: AppModel
    let list: TodoList
    @State private var hovering = false

    var body: some View {
        let m = app.todo!
        let on = m.selectedList?.id == list.id
        Button { m.selectedListID = list.id; m.editingID = nil } label: {
            HStack(spacing: 6) {
                Image(systemName: list.remoteID != nil ? "checklist" : "list.bullet").font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(on ? Theme.mint : Theme.text3)
                Text(list.title).font(Theme.font(11.5, on ? .bold : .medium)).foregroundStyle(on ? Theme.text : Theme.text2).lineLimit(1)
                Spacer(minLength: 2)
                let n = m.openCount(list.id)
                if n > 0 { Text("\(n)").font(Theme.mono(10, .bold)).foregroundStyle(Theme.text3) }
            }
            .padding(.horizontal, 8).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(on ? 0.09 : hovering ? 0.05 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Where the tasks live and how the sync is doing. A click syncs, or opens Settings when Google isn't set up.
struct TodoSyncBadge: View {
    let app: AppModel

    var body: some View {
        let m = app.todo!
        let (icon, text, tint): (String, String, Color) = {
            switch m.auth.state {
            case .notConfigured: return ("internaldrive", tr("On this Mac"), Theme.text3)
            case .signedOut: return ("person.crop.circle.badge.plus", tr("Sign in to Google Tasks"), Theme.sky)
            case .signingIn: return ("hourglass", tr("Signing in…"), Theme.text3)
            case .failed: return ("exclamationmark.triangle.fill", tr("Google needs you"), Theme.coral)
            case .signedIn: break
            }
            switch m.syncState {
            case .syncing: return ("arrow.triangle.2.circlepath", tr("Syncing…"), Theme.sky)
            case .offline: return ("wifi.slash", tr("Offline, saved here"), Theme.butter)
            case .failed: return ("exclamationmark.triangle.fill", tr("Sync problem"), Theme.coral)
            default: return ("checkmark.icloud.fill", m.data.lastSync.map { tr("Synced %@", Self.ago($0, now: m.now())) } ?? tr("Google Tasks"), Theme.mint)
            }
        }()
        Button {
            if m.auth.state == .signedIn { Task { await m.sync() } } else { app.commands.openSettings("todo") }
        } label: {
            Label(text, systemImage: icon).font(Theme.font(10.5, .semibold)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 8).frame(height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(m.auth.state == .signedIn ? tr("Sync now") : tr("Settings › To-do"))
    }

    static func ago(_ d: Date, now: Date) -> String {
        let m = Int(now.timeIntervalSince(d) / 60)
        if m < 1 { return tr("just now") }
        if m < 60 { return tr("%dm ago", m) }
        return tr("%dh ago", m / 60)
    }
}

struct TodoRow: View {
    let app: AppModel
    let item: TodoItem
    @State private var hovering = false
    @State private var title = ""
    @State private var notes = ""
    @State private var sub = ""

    var body: some View {
        let m = app.todo!
        let editing = m.editingID == item.id
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Button { withAnimation(Theme.fade) { m.toggle(item.id) } } label: {
                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: item.parentID == nil ? 14 : 12.5)).foregroundStyle(item.done ? Theme.mint : Theme.text3)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 0) {
                    if editing {
                        TextField("", text: $title).textFieldStyle(.plain).font(Theme.font(12, .semibold)).foregroundStyle(Theme.text)
                            .onSubmit { m.rename(item.id, title) }
                    } else {
                        Text(item.title).font(Theme.font(12, .medium)).foregroundStyle(item.done ? Theme.text3 : Theme.text)
                            .strikethrough(item.done, color: Theme.text3).lineLimit(1)
                    }
                    if !item.notes.isEmpty && !editing {
                        Text(item.notes).font(Theme.font(10)).foregroundStyle(Theme.text3).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if let due = item.due { DueChip(due: due, done: item.done, now: m.now()) }
                if hovering || editing {
                    IconButton(symbol: editing ? "checkmark" : "pencil", size: 10, tint: Theme.text2, hit: 22, help: editing ? tr("Done") : tr("Edit")) {
                        if editing { m.rename(item.id, title); m.setNotes(item.id, notes); m.editingID = nil } else { title = item.title; notes = item.notes; m.editingID = item.id }
                    }
                    IconButton(symbol: "trash", size: 10, tint: Theme.text3, hit: 22, help: tr("Delete")) { withAnimation(Theme.fade) { m.delete(item.id) } }
                }
            }
            if editing {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.text3)
                        let day = Calendar.current.startOfDay(for: m.now())
                        ForEach([(tr("None"), Date?.none), (tr("Today"), Optional(day)), (tr("Tomorrow"), Optional(day.addingTimeInterval(86400))),
                                 (tr("Next week"), Optional(day.addingTimeInterval(7 * 86400)))], id: \.0) { label, d in
                            ChoiceChip(title: label, on: Self.same(item.due, d), tint: Theme.mint) { m.setDue(item.id, d) }
                        }
                        if let d = item.due {
                            IconButton(symbol: "chevron.left", size: 8.5, tint: Theme.text2, hit: 18) { m.setDue(item.id, d.addingTimeInterval(-86400)) }
                            IconButton(symbol: "chevron.right", size: 8.5, tint: Theme.text2, hit: 18) { m.setDue(item.id, d.addingTimeInterval(86400)) }
                        }
                    }
                    NotchField(placeholder: tr("Notes"), text: $notes, icon: "text.alignleft") { m.setNotes(item.id, notes) }
                    if item.parentID == nil {
                        NotchField(placeholder: tr("Add a subtask"), text: $sub, icon: "arrow.turn.down.right") {
                            m.add(sub, listID: item.listID, parentID: item.id)
                            sub = ""
                        }
                    }
                }
                .padding(.leading, 22)
                .padding(.bottom, 4)
            }
        }
        .padding(.vertical, 3).padding(.horizontal, 4)
        .padding(.leading, item.parentID == nil ? 0 : 22)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(editing ? 0.06 : hovering ? 0.03 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { title = item.title; notes = item.notes; m.editingID = item.id }
        .onAppear { if editing { title = item.title; notes = item.notes } }
        .onChange(of: m.editingID) { if m.editingID == item.id { title = item.title; notes = item.notes } }
    }

    static func same(_ a: Date?, _ b: Date?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (x?, y?): Calendar.current.isDate(x, inSameDayAs: y)
        default: false
        }
    }
}

/// "Today", "Tomorrow", "Fri 6 Nov"; red once it's late.
struct DueChip: View {
    let due: Date
    let done: Bool
    let now: Date

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let late = !done && due < today
        let isToday = cal.isDate(due, inSameDayAs: now)
        Text(label(cal, today: today, isToday: isToday))
            .font(Theme.font(10, .bold))
            .foregroundStyle(done ? Theme.text3 : late ? Theme.coral : isToday ? Theme.butter : Theme.text2)
            .padding(.horizontal, 7).frame(height: 18)
            .background(Capsule().fill((late ? Theme.coral : isToday ? Theme.butter : Color.white).opacity(done ? 0.04 : 0.12)))
    }

    private func label(_ cal: Calendar, today: Date, isToday: Bool) -> String {
        if isToday { return tr("Today") }
        if cal.isDate(due, inSameDayAs: today.addingTimeInterval(86400)) { return tr("Tomorrow") }
        if cal.isDate(due, inSameDayAs: today.addingTimeInterval(-86400)) { return tr("Yesterday") }
        let f = DateFormatter()
        f.locale = Lang.shared.isIndonesian ? Locale(identifier: "id_ID") : Locale(identifier: "en_US")
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return f.string(from: due)
    }
}

struct TodoPane: View {
    let app: AppModel
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var note = ""

    var body: some View {
        @Bindable var prefs = app.prefs
        let m = app.todo!
        let a = m.auth
        Form {
            Section {
                LabeledContent(tr("Status")) {
                    HStack(spacing: 8) {
                        StatusDot(color: a.state == .signedIn ? .green : a.state == .notConfigured ? .secondary : .orange)
                        Text(statusText(a.state)).foregroundStyle(.secondary)
                    }
                }
                switch a.state {
                case .notConfigured:
                    Text(tr("To sync with Google Tasks, Saku needs your own free Google Cloud OAuth client (about 10 minutes, once). Until then, To-do keeps your tasks on this Mac."))
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button(tr("Open the setup guide")) {
                            let guide = Lang.shared.isIndonesian ? "google-tasks-setup.md" : "google-tasks-setup.en.md"
                            if let u = AppResources.url(guide) { NSWorkspace.shared.open(u) }
                        }
                        Spacer()
                        Button(tr("Import client JSON…")) { importJSON() }.buttonStyle(.borderedProminent)
                    }
                    DisclosureGroup(tr("Or paste the client ID and secret")) {
                        TextField(tr("Client ID"), text: $clientID)
                        SecureField(tr("Client secret"), text: $clientSecret)
                        HStack {
                            Spacer()
                            Button(tr("Save")) {
                                Secrets.set("google-oauth-client-id", clientID)
                                Secrets.set("google-oauth-client-secret", clientSecret)
                                clientID = ""; clientSecret = ""
                                a.refreshState()
                                note = a.state == .notConfigured ? tr("That doesn't look like a Google client ID (…apps.googleusercontent.com).") : ""
                            }
                        }
                    }
                case .signedOut, .failed:
                    if case .failed(let msg) = a.state { Text(msg).foregroundStyle(.orange) }
                    HStack {
                        Text(OAuthClient.fromFile != nil ? tr("Client from google-oauth.json in Saku's folder") : tr("Client from Settings"))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(tr("Remove client")) { removeClient() }
                        Button(tr("Sign in with Google")) { Task { await a.signIn(); m.googleChanged() } }.buttonStyle(.borderedProminent)
                    }
                case .signingIn:
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(tr("Finish signing in in your browser…")).foregroundStyle(.secondary)
                        Spacer()
                        Button(tr("Cancel")) { a.cancelSignIn() }
                    }
                case .signedIn:
                    LabeledContent(tr("Lists"), value: "\(m.lists.count)")
                    LabeledContent(tr("Last sync"), value: m.data.lastSync.map { TodoSyncBadge.ago($0, now: m.now()) } ?? tr("Not yet"))
                    HStack {
                        Spacer()
                        Button(tr("Sign out")) { Task { await a.signOut(); m.googleChanged() } }
                        Button(tr("Sync now")) { Task { await m.sync() } }.buttonStyle(.borderedProminent)
                    }
                }
                if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.orange) }
            } header: {
                Text("Google Tasks")
            } footer: {
                Text(tr("Saku only asks Google for your tasks. The sign-in token stays in the macOS Keychain, and your client file stays in Saku's folder: never in the app or the repo."))
            }
            Section(tr("To-do")) {
                Toggle(tr("Show tasks due today beside the camera"), isOn: $prefs.v.todoInNotch)
                Picker(tr("Beside the camera"), selection: $prefs.v.todoInNotchOnHover) {
                    Text(tr("Only on hover")).tag(true)
                    Text(tr("Always")).tag(false)
                }
                .disabled(!prefs.v.todoInNotch)
                Toggle(tr("Show completed tasks"), isOn: $prefs.v.todoShowCompleted)
            }
        }
        .formStyle(.grouped)
        .onAppear { a.refreshState() }
    }

    private func statusText(_ s: GoogleAuth.State) -> String {
        switch s {
        case .notConfigured: tr("Local only (no Google client yet)")
        case .signedOut: tr("Ready to sign in")
        case .signingIn: tr("Signing in…")
        case .signedIn: tr("Connected to Google Tasks")
        case .failed: tr("Needs attention")
        }
    }

    private func importJSON() {
        app.keepOpenReasons.insert("picker")
        let p = NSOpenPanel()
        p.allowedContentTypes = [.json]
        p.prompt = tr("Import")
        NSApp.activate()
        if p.runModal() == .OK, let u = p.url {
            note = OAuthClient.importFile(u) ? "" : tr("That file isn't a Google OAuth client. Download the JSON of a Desktop app client.")
            app.todo.auth.refreshState()
        }
        app.keepOpenReasons.remove("picker")
    }

    private func removeClient() {
        try? FileManager.default.removeItem(at: Paths.file(OAuthClient.fileName))
        Secrets.set("google-oauth-client-id", "")
        Secrets.set("google-oauth-client-secret", "")
        app.todo.auth.refreshState()
    }
}
