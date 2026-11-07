import AppKit
import SwiftUI

/// To-do and Google Tasks checks. Everything runs against a fake Google: no browser, no account, no network.
/// The real loopback listener is tried only while the macOS firewall is off, so no "accept incoming connections?" prompt.
@MainActor
enum TodoChecks {
    static func spin(_ seconds: Double = 3, _ done: () -> Bool) {
        let until = Date().addingTimeInterval(seconds)
        while !done() && Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    static func run(_ app: AppModel) {
        func check(_ ok: Bool, _ name: String) { SelfTest.check(ok, name) }
        let m = app.todo!
        let auth = m.auth
        let realNow = m.now
        let day = Calendar.current.startOfDay(for: Date())
        m.now = { day.addingTimeInterval(10 * 3600) }
        defer { m.now = realNow }
        m.reset()

        // Local to-do.
        check(m.lists.map(\.id) == [TodoModel.defaultListID] && m.syncState == .local, "a local list to start with")
        let milk = m.add("Buy milk")
        check(milk?.due == nil && milk?.dirty == true && m.rows(in: TodoModel.defaultListID, done: false).count == 1, "add a task")
        let rent = m.add("Pay rent tomorrow")
        check(rent?.title == "Pay rent" && rent?.due == day.addingTimeInterval(86400), "a day in the title becomes the due date")
        let trip = m.add("Pack for the trip")!
        let sub = m.add("Charger", parentID: trip.id)!
        let rows = m.rows(in: TodoModel.defaultListID, done: false).map(\.id)
        check(rows.firstIndex(of: sub.id) == rows.firstIndex(of: trip.id).map { $0 + 1 }, "a subtask sits right under its parent")
        m.toggle(trip.id)
        check(m.item(trip.id)?.done == true && m.item(sub.id)?.done == true && m.item(trip.id)?.completed != nil, "ticking a task ticks its subtasks")
        m.toggle(trip.id)
        m.rename(milk!.id, "Buy oat milk")
        m.setNotes(milk!.id, "the barista one")
        m.setDue(milk!.id, day)
        check(m.item(milk!.id)?.title == "Buy oat milk" && m.item(milk!.id)?.notes == "the barista one", "rename and notes")
        m.setDue(rent!.id, day.addingTimeInterval(-86400))
        check(m.dueToday.count == 2, "due today counts today and late tasks")
        app.prefs.v.todoInNotch = true
        app.prefs.v.todoInNotchOnHover = false
        check(m.liveActivity() == .todo(count: 2), "tasks due today show beside the camera")
        app.prefs.v.todoInNotch = false
        check(m.liveActivity() == nil, "and can be turned off")
        app.prefs.v.todoInNotch = true
        app.prefs.v.todoInNotchOnHover = true
        app.notch.hovering = false
        check(PrefsData().todoInNotchOnHover && m.liveActivity() == nil, "by default the closed notch stays plain")
        app.notch.hovering = true
        let hovered = m.liveActivity()
        app.notch.hovering = false
        app.notch.mode = .open
        check(hovered == .todo(count: 2) && m.liveActivity() == .todo(count: 2), "the tasks show on hover and while the panel is open")
        app.notch.mode = .closed
        m.delete(trip.id)
        check(m.item(trip.id) == nil && m.item(sub.id) == nil, "deleting a task removes its subtasks")
        let list = m.addList("Uni")
        check(list != nil && m.selectedListID == list!.id && m.lists.count == 2, "add a list")
        m.add("Read chapter 4")
        m.saveNow()
        let saved = JSONStore<TodoData>("todo.json").load()
        check(saved?.items.count == m.data.items.count && saved?.lists.count == 2, "tasks are saved for offline use")

        // Your own OAuth client.
        let json = #"{"installed":{"client_id":"123-abc.apps.googleusercontent.com","project_id":"saku","client_secret":"GOCSPX-x","redirect_uris":["http://localhost"]}}"#
        check(OAuthClient.parse(Data(json.utf8)) == OAuthClient(id: "123-abc.apps.googleusercontent.com", secret: "GOCSPX-x"), "reads Google's client JSON")
        check(OAuthClient.parse(Data(#"{"installed":{"client_id":"nope"}}"#.utf8)) == nil && OAuthClient.parse(Data("hello".utf8)) == nil,
              "rejects files that aren't a Google client")
        check(auth.state == .notConfigured, "no client: To-do stays local")

        // PKCE and the sign-in URL.
        check(GoogleAuth.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
              "PKCE challenge matches RFC 7636")
        let v = GoogleAuth.makeVerifier()
        check(v.count == 64 && v.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }, "PKCE verifier is 64 URL-safe characters")
        let client = OAuthClient(id: "123-abc.apps.googleusercontent.com", secret: "GOCSPX-x")
        let url = GoogleAuth.authorizationURL(client: client, redirect: "http://127.0.0.1:5555", challenge: "abc", state: "xyz")
        let q = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        check(q["client_id"] == client.id && q["redirect_uri"] == "http://127.0.0.1:5555" && q["scope"] == GoogleAuth.scope
              && q["code_challenge_method"] == "S256" && q["access_type"] == "offline" && q["state"] == "xyz" && q["response_type"] == "code",
              "sign-in URL asks only for Tasks, with PKCE and offline access")
        check(LoopbackReceiver.query(fromRequest: "GET /?state=xyz&code=4/0Ab&scope=tasks HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n") ==
              ["state": "xyz", "code": "4/0Ab", "scope": "tasks"], "reads Google's redirect")
        check(LoopbackReceiver.query(fromRequest: "GET /?error=access_denied&state=xyz HTTP/1.1\r\n")["error"] == "access_denied", "reads a refusal")

        // Signing in, end to end, against a fake Google.
        auth.clientOverride = client
        auth.refreshState()
        check(auth.state == .signedOut, "with a client: ready to sign in")
        var posts: [[String: String]] = []
        auth.post = { url, form in
            posts.append(form)
            if url == GoogleAuth.revokeEndpoint { return [:] }
            if form["grant_type"] == "refresh_token" { return ["access_token": "access-2", "expires_in": 3600] }
            return ["access_token": "access-1", "expires_in": 3600, "refresh_token": "refresh-1"]
        }
        let firewallOff = Self.firewallOff()
        if firewallOff {
            auth.openBrowser = { url in
                // The "browser": follow Google's redirect back to Saku's listener with a code.
                let q = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
                let back = URL(string: "\(q["redirect_uri"] ?? "")/?state=\(q["state"] ?? "")&code=4/fake-code")!
                URLSession.shared.dataTask(with: back).resume()
            }
            var done = false
            Task { await auth.signIn(); done = true }
            spin(5) { done }
            check(auth.state == .signedIn && Secrets.get("google-tasks-refresh") == "refresh-1", "signs in through the loopback listener")
            check(posts.last?["grant_type"] == "authorization_code" && posts.last?["code"] == "4/fake-code"
                  && (posts.last?["code_verifier"]?.count ?? 0) == 64 && posts.last?["redirect_uri"]?.hasPrefix("http://127.0.0.1:") == true,
                  "trades the code with the PKCE verifier")
        } else {
            Secrets.set("google-tasks-refresh", "refresh-1")
            Secrets.set("google-tasks-access", "access-1")
            Secrets.set("google-tasks-expiry", String(Date().timeIntervalSince1970 + 3600))
            auth.refreshState()
            print("  (todo: firewall is on, loopback sign-in skipped so macOS doesn't ask about incoming connections)")
        }
        auth.openBrowser = { _ in }

        // Tokens refresh by themselves; a dead refresh token means signing in again.
        Secrets.set("google-tasks-expiry", "0")
        var token = ""
        Task { token = (try? await auth.accessToken()) ?? "" }
        spin { !token.isEmpty }
        check(token == "access-2" && posts.last?["grant_type"] == "refresh_token", "an expired token refreshes")

        // Two-way sync with the fake Google Tasks.
        guard let fake = m.api as? FakeTasksAPI else { return check(false, "fake Google Tasks in tests") }
        func sync() {
            var finished = false
            Task { await m.sync(); finished = true }
            spin { finished }
        }
        m.selectedListID = TodoModel.defaultListID
        m.googleChanged()
        spin { m.syncState != .idle && m.syncState != .syncing }
        check(m.syncState == .synced && m.lists.first { $0.id == TodoModel.defaultListID }?.remoteID == "gl-default",
              "your first list joins Google's default list")
        check(fake.store["gl-default"]?.contains { $0.title == "Buy oat milk" && $0.notes == "the barista one" } == true
              && fake.listTitles.contains { $0.title == "Uni" } && m.data.items.allSatisfy { !$0.dirty && $0.remoteID != nil },
              "local tasks and lists go up to Google")
        let parent = m.add("Pack for the trip", listID: TodoModel.defaultListID)!
        m.add("Swimsuit", listID: TodoModel.defaultListID, parentID: parent.id)
        sync()
        let gParent = fake.store["gl-default"]?.first { $0.title == "Pack for the trip" }
        let gChild = fake.store["gl-default"]?.first { $0.title == "Swimsuit" }
        check(gParent != nil && gChild?.parent == gParent?.id, "subtasks keep their parent on Google")

        // Changes on the phone come down.
        let gMilk = fake.store["gl-default"]!.first { $0.title == "Buy oat milk" }!
        fake.remoteEdit(list: "gl-default", id: gMilk.id) { $0.title = "Buy oat milk x2"; $0.done = true }
        fake.store["gl-default"]!.append(RemoteTask(id: "phone-1", title: "Call grandma", updated: fake.clock))
        fake.listTitles.append((id: "gl-phone", title: "Groceries"))
        fake.store["gl-phone"] = [RemoteTask(id: "phone-2", title: "Eggs")]
        sync()
        check(m.data.items.contains { $0.title == "Buy oat milk x2" && $0.done } && m.data.items.contains { $0.title == "Call grandma" },
              "edits and new tasks from the phone show up")
        check(m.lists.contains { $0.title == "Groceries" } && m.data.items.contains { $0.title == "Eggs" }, "new lists from the phone show up")
        fake.store["gl-default"]!.removeAll { $0.id == "phone-1" }
        sync()
        check(!m.data.items.contains { $0.title == "Call grandma" }, "tasks deleted on the phone go here too")

        // Deleting here deletes on Google.
        if let eggs = m.data.items.first(where: { $0.title == "Eggs" }) {
            m.delete(eggs.id)
            sync()
            check(fake.store["gl-phone"]?.isEmpty == true && m.item(eggs.id) == nil, "deleting here deletes on Google")
        }

        // Offline: keep everything, push later.
        fake.offline = true
        let offlineTask = m.add("Write while offline", listID: TodoModel.defaultListID)!
        sync()
        check(m.syncState == .offline && m.item(offlineTask.id)?.dirty == true, "offline: the change waits here")
        fake.offline = false
        sync()
        check(m.syncState == .synced && fake.store["gl-default"]?.contains { $0.title == "Write while offline" } == true, "back online: it goes up")

        // Both sides changed: the newer one wins.
        if let local = m.data.items.first(where: { $0.title == "Write while offline" }), let rid = local.remoteID {
            fake.remoteEdit(list: "gl-default", id: rid) { $0.title = "Phone title" }
            let later = fake.clock.addingTimeInterval(60)
            m.now = { later }
            m.rename(local.id, "Mac title")
            sync()
            check(fake.store["gl-default"]?.first { $0.id == rid }?.title == "Mac title" && m.item(local.id)?.title == "Mac title",
                  "a newer change here beats an older one on the phone")
            m.now = { day.addingTimeInterval(10 * 3600) }
        }

        // Signing out keeps Google's tasks on Google and leaves a clean local list.
        var out = false
        Task { await auth.signOut(); m.googleChanged(); out = true }
        spin { out }
        check(auth.state == .signedOut && m.lists.map(\.id) == [TodoModel.defaultListID] && m.data.items.isEmpty
              && posts.last?["token"] == "refresh-1", "sign out revokes the token and clears this Mac's copy")

        // Clean up for the next suite.
        auth.clientOverride = nil
        auth.post = GoogleAuth.livePost
        for k in ["google-tasks-access", "google-tasks-expiry", "google-tasks-refresh"] { Secrets.set(k, "") }
        auth.refreshState()
        m.reset()
        app.notch.hud = nil
    }

    /// True when the macOS application firewall is off (a loopback listener can't trigger its prompt then either).
    static func firewallOff() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/libexec/ApplicationFirewall/socketfilterfw")
        p.arguments = ["--getglobalstate"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return out.contains("disabled")
    }

    static let scenes: [Render.Scene] = [
        Render.Scene(name: "open-todo", settle: 0.5) { app in
            app.todo.loadDemo(google: false)
            app.notch.mode = .open
            app.notch.tab = .todo
        },
        Render.Scene(name: "open-todo-google", settle: 0.5) { app in
            app.todo.auth.clientOverride = OAuthClient(id: "demo.apps.googleusercontent.com", secret: "")
            Secrets.set("google-tasks-refresh", "demo")
            app.todo.auth.refreshState()
            app.todo.loadDemo(google: true)
            app.prefs.v.todoShowCompleted = true
            app.todo.editingID = "t2"
            app.notch.mode = .open
            app.notch.tab = .todo
        },
        Render.Scene(name: "closed-todo", settle: 0.4) { app in
            app.todo.loadDemo(google: false)
            app.prefs.v.todoInNotch = true
            app.notch.hovering = true
        },
        Render.Scene(name: "closed-todo-idle", settle: 0.4) { app in
            app.todo.loadDemo(google: false)
            app.prefs.v.todoInNotch = true
        },
    ]
}
