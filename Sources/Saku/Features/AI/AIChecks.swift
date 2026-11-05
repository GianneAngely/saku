import AppKit

@MainActor
enum AIChecks {
    static func run(_ app: AppModel) {
        func check(_ ok: Bool, _ name: String) { SelfTest.check(ok, name) }

        // Claude stream: thinking + text + signature, folded into blocks.
        var s = ClaudeStream()
        let events: [[String: Any]] = [
            ["type": "message_start", "message": ["model": "claude-opus-5-5"]],
            ["type": "content_block_start", "index": 0, "content_block": ["type": "thinking", "thinking": "", "signature": ""]],
            ["type": "content_block_delta", "index": 0, "delta": ["type": "signature_delta", "signature": "sig123"]],
            ["type": "content_block_stop", "index": 0],
            ["type": "content_block_start", "index": 1, "content_block": ["type": "text", "text": ""]],
            ["type": "content_block_delta", "index": 1, "delta": ["type": "text_delta", "text": "Hel"]],
            ["type": "content_block_delta", "index": 1, "delta": ["type": "text_delta", "text": "lo!"]],
            ["type": "content_block_stop", "index": 1],
            ["type": "message_delta", "delta": ["stop_reason": "end_turn"]],
            ["type": "message_stop"],
        ]
        var shown = ""
        for e in events { if let t = s.feed(e) { shown += t } }
        check(shown == "Hello!" && s.visibleText == "Hello!", "stream text")
        check(s.model == "claude-opus-5-5" && s.stopReason == "end_turn", "stream model and stop reason")
        check(s.orderedBlocks.count == 2 && s.orderedBlocks[0]["signature"] as? String == "sig123", "thinking block kept with its signature")

        // A mid-stream fallback: only the text after the switch is shown, every block is kept for replay.
        var f = ClaudeStream()
        for e: [String: Any] in [
            ["type": "content_block_start", "index": 0, "content_block": ["type": "text", "text": "partial"]],
            ["type": "content_block_start", "index": 1, "content_block": ["type": "fallback", "from": ["model": "a"], "to": ["model": "b"]]],
            ["type": "content_block_start", "index": 2, "content_block": ["type": "text", "text": "rescued"]],
        ] { _ = f.feed(e) }
        check(f.visibleText == "rescued" && f.orderedBlocks.count == 3, "fallback switch")
        var r = ClaudeStream()
        _ = r.feed(["type": "message_delta", "delta": ["stop_reason": "refusal"]])
        check(r.stopReason == "refusal", "refusal stop reason")

        // Request body: fixed system prompt, effort, default fallbacks, assistant turns replayed verbatim.
        var a = ChatMessage(role: .assistant, text: "Hello!")
        a.claudeBlocks = s.orderedBlocks
        let body = AIModel.claudeBody(model: "claude-opus-5-5", system: "Be brief.", effort: "low",
                                      history: [ChatMessage(role: .user, text: "Hi"), a, ChatMessage(role: .notice, text: "x"), ChatMessage(role: .user, text: "Again")])
        let msgs = body["messages"] as? [[String: Any]] ?? []
        check(body["model"] as? String == "claude-opus-5-5" && body["fallbacks"] as? String == "default" && body["stream"] as? Bool == true, "Claude request basics")
        check((body["output_config"] as? [String: Any])?["effort"] as? String == "low" && body["thinking"] == nil, "effort set, thinking left adaptive")
        check(msgs.count == 3 && (msgs[1]["content"] as? [[String: Any]])?.count == 2, "history replays the assistant blocks, notices are skipped")
        check(JSONSerialization.isValidJSONObject(body), "body serialises")

        // Gemini body and stream chunk.
        let g = AIModel.geminiBody(system: "S", history: [ChatMessage(role: .user, text: "Hi"), ChatMessage(role: .assistant, text: "Yo")])
        check(((g["contents"] as? [[String: Any]])?.map { $0["role"] as? String }) == ["user", "model"], "Gemini roles")
        let chunk = #"{"candidates":[{"content":{"parts":[{"text":"Halo"}],"role":"model"}}]}"#.data(using: .utf8)!
        check(AIModel.geminiText(chunk) == "Halo", "Gemini stream chunk")
        check(AIModel.apiMessage(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#) == "invalid x-api-key", "API error message")

        // Missing keys explain themselves without any network call.
        let m = app.ai!
        app.prefs.v.aiProvider = "claude"
        m.newChat()
        m.send("Hi")
        let until = Date().addingTimeInterval(5)
        while m.busy && Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        check(m.messages.last?.role == .notice && m.messages.last?.text == tr("Add your %@ API key in Settings > AI Assistant.", "Claude"), "missing Claude key")

        // Apple Intelligence answers on device (no network, no prompt).
        app.prefs.v.aiProvider = "apple"
        m.newChat()
        if AIModel.appleAvailable {
            m.send("Reply with just the word: blossom")
            let until2 = Date().addingTimeInterval(60)
            while m.busy && Date() < until2 { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            let answer = m.messages.last { $0.role == .assistant }?.text ?? ""
            check(answer.lowercased().contains("blossom"), "Apple Intelligence replies (\(answer.prefix(40)))")
        }
        m.newChat()
    }

    static let scenes: [Render.Scene] = [
        Render.Scene(name: "open-ai", settle: 0.5) { app in
            let m = app.ai!
            m.newChat()
            app.prefs.v.aiProvider = "apple"
            m.injectDemo()
            app.notch.mode = .open
            app.notch.tab = .ai
        },
    ]
}

extension AIModel {
    /// A short made-up conversation for screenshots.
    func injectDemo() {
        input = ""
        let demo: [ChatMessage] = [
            ChatMessage(role: .user, text: "Give me 3 cute names for a café game cat"),
            ChatMessage(role: .assistant, text: "Here are three:\n- **Mochi Paws**, soft and sweet\n- **Latte**, the barista's shadow\n- **Kuro Bean**, a black cat who guards the espresso"),
        ]
        setDemo(demo)
    }
}
