import AppKit
import CryptoKit
import Foundation
import Network

// MARK: - Your own OAuth client

/// The OAuth client Angel creates in her own Google Cloud project. It never ships with Saku: it's read from
/// ~/Library/Application Support/Saku/google-oauth.json (the file Google Cloud downloads) or typed in Settings.
struct OAuthClient: Equatable {
    var id: String
    var secret: String

    static let fileName = "google-oauth.json"

    /// Google's download: {"installed": {"client_id": ..., "client_secret": ...}}.
    static func parse(_ data: Data) -> OAuthClient? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let inner = (o["installed"] as? [String: Any]) ?? (o["web"] as? [String: Any]) ?? o
        guard let id = inner["client_id"] as? String, id.hasSuffix(".apps.googleusercontent.com") else { return nil }
        return OAuthClient(id: id, secret: inner["client_secret"] as? String ?? "")
    }

    @MainActor static var fromFile: OAuthClient? {
        let u = Paths.file(fileName)
        return (try? Data(contentsOf: u)).flatMap(parse)
    }

    @MainActor static var fromSettings: OAuthClient? {
        let id = Secrets.get("google-oauth-client-id")
        guard id.hasSuffix(".apps.googleusercontent.com") else { return nil }
        return OAuthClient(id: id, secret: Secrets.get("google-oauth-client-secret"))
    }

    @MainActor static var current: OAuthClient? { fromFile ?? fromSettings }

    /// Token request fields. Desktop clients are public, so the secret is only sent when there is one.
    func form(_ fields: [String: String]) -> [String: String] {
        var f = fields
        f["client_id"] = id
        if !secret.isEmpty { f["client_secret"] = secret }
        return f
    }

    /// Copies a downloaded client JSON into the data folder. Returns false when it isn't a Google client file.
    @MainActor static func importFile(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), parse(data) != nil else { return false }
        return (try? data.write(to: Paths.file(fileName), options: .atomic)) != nil
    }
}

// MARK: - OAuth 2.0 for desktop apps: PKCE + loopback redirect

/// Talks to Google's sign-in and token endpoints. Tokens live in the Keychain (memory in QA).
@MainActor @Observable
final class GoogleAuth {
    enum State: Equatable { case notConfigured, signedOut, signingIn, signedIn, failed(String) }

    static let scope = "https://www.googleapis.com/auth/tasks"
    static let authEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    static let revokeEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!

    private(set) var state: State = .notConfigured

    /// Opens the sign-in page; self tests swap it so no browser opens.
    @ObservationIgnored var openBrowser: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// Sends a form POST and returns the JSON body; self tests answer with a fake token server.
    @ObservationIgnored var post: (URL, [String: String]) async throws -> [String: Any] = GoogleAuth.livePost
    @ObservationIgnored var clientOverride: OAuthClient?
    @ObservationIgnored private var receiver: LoopbackReceiver?
    @ObservationIgnored var now: () -> Date = Date.init

    var client: OAuthClient? { clientOverride ?? OAuthClient.current }

    init() { refreshState() }

    func refreshState() {
        if case .signingIn = state { return }
        if client == nil { state = .notConfigured } else { state = Secrets.has("google-tasks-refresh") ? .signedIn : .signedOut }
    }

    // PKCE (RFC 7636)
    static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64url(Data(bytes))
    }

    static func challenge(for verifier: String) -> String { base64url(Data(SHA256.hash(data: Data(verifier.utf8)))) }

    static func base64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func authorizationURL(client: OAuthClient, redirect: String, challenge: String, state: String) -> URL {
        var c = URLComponents(url: authEndpoint, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            .init(name: "client_id", value: client.id),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scope),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]
        return c.url!
    }

    /// Signs in through the default browser and a one-shot listener on 127.0.0.1.
    func signIn() async {
        guard let client else { state = .notConfigured; return }
        state = .signingIn
        let verifier = Self.makeVerifier()
        let nonce = Self.makeVerifier()
        let rx = LoopbackReceiver()
        receiver = rx
        defer { receiver = nil; rx.stop() }
        do {
            let port = try await rx.start()
            let redirect = "http://127.0.0.1:\(port)"
            openBrowser(Self.authorizationURL(client: client, redirect: redirect, challenge: Self.challenge(for: verifier), state: nonce))
            let reply = try await rx.waitForCallback(timeout: 300)
            if let e = reply["error"] { throw AuthError.denied(e) }
            guard reply["state"] == nonce, let code = reply["code"] else { throw AuthError.badReply }
            let token = try await post(Self.tokenEndpoint, client.form(["code": code, "redirect_uri": redirect,
                                                                         "grant_type": "authorization_code", "code_verifier": verifier]))
            try store(token, keepRefresh: false)
            state = .signedIn
        } catch {
            state = .failed(Self.describe(error))
        }
    }

    func cancelSignIn() {
        receiver?.stop()
    }

    /// A fresh access token, refreshed with the stored refresh token when it is about to expire.
    func accessToken() async throws -> String {
        let access = Secrets.get("google-tasks-access")
        let expiry = Double(Secrets.get("google-tasks-expiry")) ?? 0
        if !access.isEmpty, now().timeIntervalSince1970 < expiry - 60 { return access }
        guard let client else { throw AuthError.notConfigured }
        let refresh = Secrets.get("google-tasks-refresh")
        guard !refresh.isEmpty else { throw AuthError.signedOut }
        do {
            let token = try await post(Self.tokenEndpoint, client.form(["refresh_token": refresh, "grant_type": "refresh_token"]))
            try store(token, keepRefresh: true)
        } catch AuthError.google(let e) where e == "invalid_grant" {
            // Revoked, or a Testing-mode project's 7-day token ran out: sign in again.
            clearTokens()
            state = .failed(tr("Google asked to sign in again."))
            throw AuthError.signedOut
        }
        return Secrets.get("google-tasks-access")
    }

    func signOut() async {
        let refresh = Secrets.get("google-tasks-refresh")
        if !refresh.isEmpty { _ = try? await post(Self.revokeEndpoint, ["token": refresh]) }
        clearTokens()
        refreshState()
    }

    private func store(_ token: [String: Any], keepRefresh: Bool) throws {
        guard let access = token["access_token"] as? String else { throw AuthError.badReply }
        Secrets.set("google-tasks-access", access)
        let life = (token["expires_in"] as? Double) ?? (token["expires_in"] as? Int).map(Double.init) ?? 3600
        Secrets.set("google-tasks-expiry", String(now().timeIntervalSince1970 + life))
        if let refresh = token["refresh_token"] as? String { Secrets.set("google-tasks-refresh", refresh) }
        else if !keepRefresh { throw AuthError.noRefresh }
    }

    private func clearTokens() {
        for k in ["google-tasks-access", "google-tasks-expiry", "google-tasks-refresh"] { Secrets.set(k, "") }
    }

    enum AuthError: Error, Equatable {
        case notConfigured, signedOut, badReply, noRefresh, timedOut
        case denied(String)
        case google(String)
    }

    static func describe(_ e: Error) -> String {
        switch e as? AuthError {
        case .denied: tr("Sign-in was cancelled.")
        case .timedOut: tr("Sign-in timed out. Try again.")
        case .noRefresh: tr("Google didn't send a long-lived token. Remove Saku's access in your Google account, then sign in again.")
        case .google(let code): tr("Google said: %@", code)
        default: tr("Couldn't reach Google. Check the connection and try again.")
        }
    }

    static func livePost(_ url: URL, _ form: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var c = URLComponents()
        c.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = (c.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AuthError.google(json["error"] as? String ?? "HTTP \(http.statusCode)")
        }
        return json
    }
}

/// One-shot HTTP listener on 127.0.0.1 for Google's redirect: reads the query, answers with a small page.
final class LoopbackReceiver: @unchecked Sendable {
    private var listener: NWListener?
    private var callback: CheckedContinuation<[String: String], Error>?
    private var pending: Result<[String: String], Error>?
    private let lock = NSLock()

    func start() async throws -> UInt16 {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let l = try NWListener(using: params)
        listener = l
        l.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<UInt16, Error>) in
            let once = Once()
            l.stateUpdateHandler = { st in
                switch st {
                case .ready: if once.first() { c.resume(returning: l.port?.rawValue ?? 0) }
                case .failed(let e): if once.first() { c.resume(throwing: e) }
                default: break
                }
            }
            l.start(queue: .global())
        }
    }

    func waitForCallback(timeout: TimeInterval) async throws -> [String: String] {
        try await withCheckedThrowingContinuation { c in
            lock.lock()
            if let early = pending {
                pending = nil
                lock.unlock()
                c.resume(with: early)
                return
            }
            callback = c
            lock.unlock()
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(.failure(GoogleAuth.AuthError.timedOut))
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        finish(.failure(GoogleAuth.AuthError.denied("cancelled")))
    }

    private func finish(_ r: Result<[String: String], Error>) {
        lock.lock()
        let c = callback
        callback = nil
        if c == nil, pending == nil, case .success = r { pending = r }   // the browser beat us to it
        lock.unlock()
        c?.resume(with: r)
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global())
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, _ in
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let query = Self.query(fromRequest: text)
            let ok = query["code"] != nil
            let body = ok ? "<h2>🌸 Saku is connected to Google Tasks.</h2><p>You can close this tab.</p>"
                          : "<h2>Saku couldn't sign in.</h2><p>Close this tab and try again in Saku.</p>"
            let page = "<!doctype html><meta charset=utf-8><title>Saku</title><body style='font:16px -apple-system;padding:40px;color:#3A2537'>\(body)</body>"
            let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(page.utf8.count)\r\nConnection: close\r\n\r\n\(page)"
            conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
            if query["code"] != nil || query["error"] != nil { self?.finish(.success(query)) }
        }
    }

    /// True the first time only, from any thread.
    final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func first() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }
    }

    /// "GET /?state=x&code=4/abc HTTP/1.1" -> ["state": "x", "code": "4/abc"].
    static func query(fromRequest text: String) -> [String: String] {
        guard let line = text.split(separator: "\r\n").first ?? text.split(separator: "\n").first else { return [:] }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, let c = URLComponents(string: "http://127.0.0.1" + parts[1]) else { return [:] }
        var out: [String: String] = [:]
        for q in c.queryItems ?? [] { out[q.name] = q.value ?? "" }
        return out
    }
}

// MARK: - Google Tasks API

struct RemoteList: Equatable {
    var id: String
    var title: String
}

struct RemoteTask: Equatable {
    var id: String
    var title: String
    var notes = ""
    var done = false
    var due: Date?
    var completed: Date?
    var parent: String?
    var position = ""
    var updated = Date()
    var deleted = false
}

/// What the to-do sync needs from Google Tasks. The live client and the self-test fake both speak it.
@MainActor
protocol TasksAPI: AnyObject {
    func lists() async throws -> [RemoteList]
    func tasks(list: String) async throws -> [RemoteTask]
    func insertList(title: String) async throws -> RemoteList
    func insert(list: String, task: RemoteTask, parent: String?) async throws -> RemoteTask
    func patch(list: String, task: RemoteTask) async throws -> RemoteTask
    func delete(list: String, task: String) async throws
}

/// tasks.googleapis.com with the signed-in account's token.
@MainActor
final class GoogleTasksAPI: TasksAPI {
    let auth: GoogleAuth
    static let base = "https://tasks.googleapis.com/tasks/v1"

    init(auth: GoogleAuth) { self.auth = auth }

    private func call(_ method: String, _ path: String, query: [String: String] = [:], body: [String: Any]? = nil) async throws -> [String: Any] {
        var c = URLComponents(string: Self.base + path)!
        if !query.isEmpty { c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: c.url!)
        req.httpMethod = method
        req.setValue("Bearer \(try await auth.accessToken())", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw GoogleAuth.AuthError.google("HTTP \(http.statusCode)")
        }
        return data.isEmpty ? [:] : ((try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:])
    }

    func lists() async throws -> [RemoteList] {
        var out: [RemoteList] = [], page: String?
        repeat {
            var q = ["maxResults": "100"]
            if let page { q["pageToken"] = page }
            let r = try await call("GET", "/users/@me/lists", query: q)
            out += (r["items"] as? [[String: Any]] ?? []).compactMap { o in
                (o["id"] as? String).map { RemoteList(id: $0, title: o["title"] as? String ?? "") }
            }
            page = r["nextPageToken"] as? String
        } while page != nil
        return out
    }

    func tasks(list: String) async throws -> [RemoteTask] {
        var out: [RemoteTask] = [], page: String?
        repeat {
            var q = ["maxResults": "100", "showCompleted": "true", "showHidden": "true"]
            if let page { q["pageToken"] = page }
            let r = try await call("GET", "/lists/\(list)/tasks", query: q)
            out += (r["items"] as? [[String: Any]] ?? []).compactMap(Self.task)
            page = r["nextPageToken"] as? String
        } while page != nil
        return out
    }

    func insertList(title: String) async throws -> RemoteList {
        let r = try await call("POST", "/users/@me/lists", body: ["title": title])
        return RemoteList(id: r["id"] as? String ?? "", title: r["title"] as? String ?? title)
    }

    func insert(list: String, task: RemoteTask, parent: String?) async throws -> RemoteTask {
        var q: [String: String] = [:]
        if let parent { q["parent"] = parent }
        let r = try await call("POST", "/lists/\(list)/tasks", query: q, body: Self.body(task))
        return Self.task(r) ?? task
    }

    func patch(list: String, task: RemoteTask) async throws -> RemoteTask {
        let r = try await call("PATCH", "/lists/\(list)/tasks/\(task.id)", body: Self.body(task))
        return Self.task(r) ?? task
    }

    func delete(list: String, task: String) async throws {
        _ = try await call("DELETE", "/lists/\(list)/tasks/\(task)")
    }

    static func body(_ t: RemoteTask) -> [String: Any] {
        var b: [String: Any] = ["title": t.title, "notes": t.notes, "status": t.done ? "completed" : "needsAction"]
        b["due"] = t.due.map(dueString) ?? NSNull()
        if !t.done { b["completed"] = NSNull() }
        return b
    }

    /// Google keeps only the day of a due date: midnight UTC of that calendar day.
    static func dueString(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02dT00:00:00.000Z", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    static func dueDate(_ s: String) -> Date? {
        guard s.count >= 10 else { return nil }
        let p = s.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    static func task(_ o: [String: Any]) -> RemoteTask? {
        guard let id = o["id"] as? String else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func date(_ k: String) -> Date? { (o[k] as? String).flatMap { iso.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) } }
        return RemoteTask(id: id, title: o["title"] as? String ?? "", notes: o["notes"] as? String ?? "",
                          done: (o["status"] as? String) == "completed", due: (o["due"] as? String).flatMap(dueDate),
                          completed: date("completed"), parent: o["parent"] as? String, position: o["position"] as? String ?? "",
                          updated: date("updated") ?? Date(), deleted: o["deleted"] as? Bool ?? false)
    }
}

/// An in-memory Google Tasks for self tests and pictures: same answers, no network, no account.
@MainActor
final class FakeTasksAPI: TasksAPI {
    var store: [String: [RemoteTask]] = [:]
    var listTitles: [(id: String, title: String)] = []
    var offline = false
    private(set) var calls: [String] = []
    private var counter = 0
    var clock = Date(timeIntervalSince1970: 1_800_000_000)

    init(lists: [(String, String)] = [("gl-default", "My Tasks")]) {
        listTitles = lists.map { (id: $0.0, title: $0.1) }
        for l in lists { store[l.0] = [] }
    }

    private func tick() -> Date { clock = clock.addingTimeInterval(1); return clock }
    private func check(_ name: String) throws {
        calls.append(name)
        if offline { throw URLError(.notConnectedToInternet) }
    }

    func lists() async throws -> [RemoteList] {
        try check("lists")
        return listTitles.map { RemoteList(id: $0.id, title: $0.title) }
    }

    func tasks(list: String) async throws -> [RemoteTask] {
        try check("tasks \(list)")
        return store[list] ?? []
    }

    func insertList(title: String) async throws -> RemoteList {
        try check("insertList \(title)")
        counter += 1
        let id = "gl-\(counter)"
        listTitles.append((id: id, title: title))
        store[id] = []
        return RemoteList(id: id, title: title)
    }

    func insert(list: String, task: RemoteTask, parent: String?) async throws -> RemoteTask {
        try check("insert \(task.title)")
        counter += 1
        var t = task
        t.id = "gt-\(counter)"
        t.parent = parent
        t.updated = tick()
        t.position = String(format: "%020d", counter)
        store[list, default: []].append(t)
        return t
    }

    func patch(list: String, task: RemoteTask) async throws -> RemoteTask {
        try check("patch \(task.title)")
        guard let i = store[list]?.firstIndex(where: { $0.id == task.id }) else { throw GoogleAuth.AuthError.google("HTTP 404") }
        var t = task
        t.parent = store[list]![i].parent
        t.position = store[list]![i].position
        t.updated = tick()
        t.completed = task.done ? (store[list]![i].completed ?? clock) : nil
        store[list]![i] = t
        return t
    }

    func delete(list: String, task: String) async throws {
        try check("delete \(task)")
        store[list]?.removeAll { $0.id == task || $0.parent == task }
    }

    /// Someone edits on the phone.
    func remoteEdit(list: String, id: String, _ change: (inout RemoteTask) -> Void) {
        guard let i = store[list]?.firstIndex(where: { $0.id == id }) else { return }
        change(&store[list]![i])
        store[list]![i].updated = tick()
    }
}
