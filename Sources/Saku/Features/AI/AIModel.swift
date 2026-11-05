import AppKit
import FoundationModels
import Observation
import SwiftUI

enum AIProvider: String, CaseIterable, Codable {
    case apple, claude, gemini

    var title: String {
        switch self {
        case .apple: tr("Apple Intelligence")
        case .claude: "Claude"
        case .gemini: "Gemini"
        }
    }

    var short: String {
        switch self {
        case .apple: tr("On device")
        case .claude: "Claude"
        case .gemini: "Gemini"
        }
    }

    var secretName: String? {
        switch self {
        case .apple: nil
        case .claude: "anthropic"
        case .gemini: "gemini"
        }
    }
}

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant, notice }
    let id = UUID()
    var role: Role
    var text: String
    /// Claude: the assistant turn's content blocks exactly as the API sent them (thinking with its signature,
    /// text, fallback markers), replayed unchanged on the next request.
    var claudeBlocks: [[String: Any]]? = nil

    static func == (a: ChatMessage, b: ChatMessage) -> Bool { a.id == b.id && a.text == b.text && a.role == b.role }
}

/// Server-sent events from the Claude Messages API, folded into content blocks.
struct ClaudeStream {
    private(set) var blocks: [Int: [String: Any]] = [:]
    private(set) var stopReason: String?
    private(set) var model: String?
    private(set) var error: String?

    /// Feeds one `data:` payload. Returns new visible text, if any.
    mutating func feed(_ json: [String: Any]) -> String? {
        switch json["type"] as? String {
        case "message_start":
            model = (json["message"] as? [String: Any])?["model"] as? String
        case "content_block_start":
            if let i = json["index"] as? Int, let b = json["content_block"] as? [String: Any] {
                blocks[i] = b
                if b["type"] as? String == "text", let t = b["text"] as? String, !t.isEmpty { return t }
            }
        case "content_block_delta":
            guard let i = json["index"] as? Int, let d = json["delta"] as? [String: Any], var b = blocks[i] else { return nil }
            var out: String?
            switch d["type"] as? String {
            case "text_delta":
                let t = d["text"] as? String ?? ""
                b["text"] = (b["text"] as? String ?? "") + t
                out = t
            case "thinking_delta":
                b["thinking"] = (b["thinking"] as? String ?? "") + (d["thinking"] as? String ?? "")
            case "signature_delta":
                b["signature"] = (b["signature"] as? String ?? "") + (d["signature"] as? String ?? "")
            default:
                break
            }
            blocks[i] = b
            return out
        case "message_delta":
            if let d = json["delta"] as? [String: Any], let s = d["stop_reason"] as? String { stopReason = s }
        case "error":
            error = ((json["error"] as? [String: Any])?["message"] as? String) ?? "error"
        default:
            break
        }
        return nil
    }

    /// Blocks in order, for replaying the assistant turn.
    var orderedBlocks: [[String: Any]] { blocks.keys.sorted().compactMap { blocks[$0] } }

    /// What to show: the text after the last fallback switch (earlier partial text was declined and superseded).
    var visibleText: String {
        let ordered = orderedBlocks
        let start = (ordered.lastIndex { $0["type"] as? String == "fallback" }).map { $0 + 1 } ?? 0
        return ordered[start...].filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
    }
}

@MainActor @Observable
final class AIModel {
    private(set) var messages: [ChatMessage] = []
    var input = ""
    private(set) var busy = false

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var appleSession: LanguageModelSession?
    /// The system prompt this conversation started with; kept fixed so Claude's history stays valid.
    @ObservationIgnored private var conversationSystem: String?

    init(app: AppModel) { self.app = app }

    var provider: AIProvider { AIProvider(rawValue: app.prefs.v.aiProvider) ?? .apple }

    nonisolated static var appleAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    nonisolated static var appleStatus: String {
        switch SystemLanguageModel.default.availability {
        case .available: return tr("Ready on this Mac")
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled: return tr("Turn on Apple Intelligence in System Settings")
            case .deviceNotEligible: return tr("This Mac does not support Apple Intelligence")
            case .modelNotReady: return tr("The model is still downloading")
            @unknown default: return tr("Not available right now")
            }
        }
    }

    func setDemo(_ m: [ChatMessage]) { messages = m }

    func newChat() {
        task?.cancel()
        busy = false
        messages = []
        appleSession = nil
        conversationSystem = nil
    }

    func send(_ text: String? = nil) {
        let prompt = (text ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !busy else { return }
        input = ""
        messages.append(ChatMessage(role: .user, text: prompt))
        messages.append(ChatMessage(role: .assistant, text: ""))
        busy = true
        let provider = provider
        task = Task { @MainActor in
            defer { busy = false }
            do {
                switch provider {
                case .apple: try await runApple(prompt)
                case .claude: try await runClaude()
                case .gemini: try await runGemini()
                }
            } catch is CancellationError {
            } catch {
                setLast(text: nil, notice: (error as? AIError)?.message ?? error.localizedDescription)
            }
        }
    }

    func stop() {
        task?.cancel()
        busy = false
    }

    /// Prompts built from the newest clipboard text.
    func quick(_ kind: String) {
        let clip = app.clipboard?.history.first { $0.kind == .text || $0.kind == .link }?.text ?? ""
        guard !clip.isEmpty else {
            messages.append(ChatMessage(role: .notice, text: tr("Copy some text first, then try again.")))
            return
        }
        let ask: String
        switch kind {
        case "summarize": ask = tr("Summarize this in a few short bullet points:")
        case "fix": ask = tr("Fix the spelling and grammar. Reply with the corrected text only:")
        case "explain": ask = tr("Explain this simply:")
        default: ask = tr("Translate this into Indonesian:")
        }
        send(ask + "\n\n" + clip)
    }

    enum AIError: Error {
        case noKey(String), http(Int, String), unavailable, refused
        @MainActor var message: String {
            switch self {
            case .noKey(let s): tr("Add your %@ API key in Settings > AI Assistant.", s)
            case .http(let c, let b): tr("The service answered %d: %@", c, b)
            case .unavailable: AIModel.appleStatus
            case .refused: tr("Claude declined this request.")
            }
        }
    }

    private func setLast(text: String?, notice: String? = nil, blocks: [[String: Any]]? = nil) {
        guard let i = messages.indices.last else { return }
        if let notice {
            if messages[i].text.isEmpty { messages.remove(at: i) }
            messages.append(ChatMessage(role: .notice, text: notice))
            return
        }
        if let text { messages[i].text = text }
        if let blocks { messages[i].claudeBlocks = blocks }
    }

    private var systemPrompt: String {
        if conversationSystem == nil { conversationSystem = app.prefs.v.aiSystemPrompt }
        return conversationSystem ?? ""
    }

    // MARK: Apple Intelligence (on device)

    private func runApple(_ prompt: String) async throws {
        guard Self.appleAvailable else { throw AIError.unavailable }
        if appleSession == nil { appleSession = LanguageModelSession(instructions: systemPrompt) }
        guard let session = appleSession else { return }
        for try await snapshot in session.streamResponse(to: prompt) {
            try Task.checkCancellation()
            setLast(text: snapshot.content)
        }
    }

    // MARK: Claude (Messages API, Angel's own key)

    /// Request body: fixed system prompt, append-only history with earlier assistant turns replayed verbatim.
    static func claudeBody(model: String, system: String, effort: String, history: [ChatMessage]) -> [String: Any] {
        var msgs: [[String: Any]] = []
        for m in history {
            switch m.role {
            case .user: msgs.append(["role": "user", "content": m.text])
            case .assistant:
                if let blocks = m.claudeBlocks, !blocks.isEmpty { msgs.append(["role": "assistant", "content": blocks]) }
                else if !m.text.isEmpty { msgs.append(["role": "assistant", "content": m.text]) }
            case .notice: break
            }
        }
        return ["model": model, "max_tokens": 16000, "stream": true, "system": system,
                "output_config": ["effort": effort], "fallbacks": "default", "messages": msgs]
    }

    private func runClaude() async throws {
        let key = Secrets.get("anthropic")
        guard !key.isEmpty else { throw AIError.noKey("Claude") }
        let history = Array(messages.dropLast())
        // A failed turn leaves a user message without an answer; keep roles alternating by skipping it.
        var clean: [ChatMessage] = []
        for m in history where m.role != .notice {
            if m.role == .user, clean.last?.role == .user { clean.removeLast() }
            clean.append(m)
        }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 300
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        let body = Self.claudeBody(model: app.prefs.v.claudeModel, system: systemPrompt, effort: app.prefs.v.claudeEffort, history: clean)
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            var b = ""
            for try await line in bytes.lines { b += line; if b.count > 400 { break } }
            throw AIError.http(code, Self.apiMessage(b))
        }
        var stream = ClaudeStream()
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:"), let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces).data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if stream.feed(json) != nil { setLast(text: stream.visibleText) }
        }
        if let e = stream.error { throw AIError.http(0, e) }
        if stream.stopReason == "refusal" {
            setLast(text: "", notice: AIError.refused.message)
            return
        }
        setLast(text: stream.visibleText, blocks: stream.orderedBlocks)
    }

    static func apiMessage(_ body: String) -> String {
        guard let d = body.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let e = o["error"] as? [String: Any], let m = e["message"] as? String else { return String(body.prefix(200)) }
        return m
    }

    // MARK: Gemini (Angel's own key)

    static func geminiBody(system: String, history: [ChatMessage]) -> [String: Any] {
        let contents: [[String: Any]] = history.compactMap { m in
            switch m.role {
            case .user: ["role": "user", "parts": [["text": m.text]]]
            case .assistant where !m.text.isEmpty: ["role": "model", "parts": [["text": m.text]]]
            default: nil
            }
        }
        return ["systemInstruction": ["parts": [["text": system]]], "contents": contents]
    }

    private func runGemini() async throws {
        let key = Secrets.get("gemini")
        guard !key.isEmpty else { throw AIError.noKey("Gemini") }
        let model = app.prefs.v.geminiModel.trimmingCharacters(in: .whitespaces)
        var req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?alt=sse")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 300
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        req.httpBody = try JSONSerialization.data(withJSONObject: Self.geminiBody(system: systemPrompt, history: Array(messages.dropLast())))
        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            var b = ""
            for try await line in bytes.lines { b += line; if b.count > 400 { break } }
            throw AIError.http(code, Self.apiMessage(b))
        }
        var text = ""
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:"), let d = line.dropFirst(5).trimmingCharacters(in: .whitespaces).data(using: .utf8) else { continue }
            text += Self.geminiText(d)
            setLast(text: text)
        }
    }

    static func geminiText(_ data: Data) -> String {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let c = (o["candidates"] as? [[String: Any]])?.first, let content = c["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else { return "" }
        return parts.compactMap { $0["text"] as? String }.joined()
    }
}
