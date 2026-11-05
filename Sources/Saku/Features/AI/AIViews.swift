import AppKit
import SwiftUI

struct AIView: View {
    let app: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        let m = app.ai!
        @Bindable var am = m
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Menu {
                    ForEach(AIProvider.allCases, id: \.self) { p in
                        Button(p.title) { app.prefs.v.aiProvider = p.rawValue; m.newChat() }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.lavender)
                        Text(m.provider.title).font(Theme.font(11.5, .semibold)).foregroundStyle(Theme.text)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.text3)
                    }
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                ForEach([("summarize", tr("Summarize clipboard")), ("fix", tr("Fix grammar")), ("explain", tr("Explain"))], id: \.0) { q in
                    PillButton(title: q.1, compact: true) { m.quick(q.0) }
                }
                Spacer()
                IconButton(symbol: "square.and.pencil", size: 11, tint: Theme.text2, hit: 24, help: tr("New chat")) { m.newChat() }
            }
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        if m.messages.isEmpty {
                            AIEmpty(app: app)
                        }
                        ForEach(m.messages) { msg in ChatBubble(app: app, message: msg).id(msg.id) }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: m.messages.last?.text) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            }
            HStack(spacing: 6) {
                TextField("", text: $am.input, prompt: Text(tr("Ask anything")).foregroundStyle(Theme.text3), axis: .vertical)
                    .textFieldStyle(.plain).font(Theme.font(12.5)).foregroundStyle(Theme.text)
                    .lineLimit(1...3)
                    .focused($focused)
                    .onSubmit { m.send() }
                if m.busy {
                    IconButton(symbol: "stop.fill", size: 10, tint: Theme.coral, hit: 26, help: tr("Stop")) { m.stop() }
                } else {
                    Button { m.send() } label: {
                        Image(systemName: "arrow.up").font(.system(size: 11, weight: .heavy)).foregroundStyle(Color.black.opacity(0.85))
                            .frame(width: 26, height: 26).background(Circle().fill(Theme.lavender)).contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(m.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 4)
            .background(Theme.cardHi, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .onAppear {
            if app.notch.focusSearch { focused = true; app.notch.focusSearch = false }
        }
    }
}

struct AIEmpty: View {
    let app: AppModel
    var body: some View {
        let p = app.ai.provider
        VStack(alignment: .leading, spacing: 4) {
            Text(tr("Hi! What can I help with?")).font(Theme.font(14, .bold)).foregroundStyle(Theme.text)
            Text(p == .apple ? tr("Runs on this Mac with Apple Intelligence. Nothing leaves your computer.")
                             : tr("Uses your own %@ key. Messages go to %@.", p.title, p == .claude ? "Anthropic" : "Google"))
                .font(Theme.font(11.5)).foregroundStyle(Theme.text2)
            if p == .apple && !AIModel.appleAvailable {
                Text(AIModel.appleStatus).font(Theme.font(11.5, .semibold)).foregroundStyle(Theme.butter)
            }
        }
        .padding(.top, 6)
    }
}

struct ChatBubble: View {
    let app: AppModel
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 60)
                Text(message.text).font(Theme.font(12.5)).foregroundStyle(Theme.text).textSelection(.enabled)
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.lavender.opacity(0.22)))
            }
        case .assistant:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.lavender).padding(.top, 2)
                if message.text.isEmpty {
                    TypingDots()
                } else {
                    Text(Self.markdown(message.text)).font(Theme.font(12.5)).foregroundStyle(Theme.text).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !message.text.isEmpty {
                    IconButton(symbol: "doc.on.doc", size: 9.5, tint: Theme.text3, hit: 20, help: tr("Copy")) {
                        app.clipboard?.copy(text: message.text)
                        app.flash("checkmark.circle.fill", tr("Copied"), tint: Theme.mint)
                    }
                }
            }
        case .notice:
            Label(message.text, systemImage: "exclamationmark.circle.fill").font(Theme.font(11.5)).foregroundStyle(Theme.butter)
        }
    }

    /// Bold, italics, code and links; keeps line breaks.
    static func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

struct TypingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: Render.active)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle().fill(Theme.lavender).frame(width: 5, height: 5)
                        .opacity(0.35 + 0.65 * max(0, sin(t * 5 - Double(i) * 0.8)))
                }
            }
            .frame(height: 16)
        }
    }
}

struct AIPane: View {
    let app: AppModel
    @State private var claudeKey = ""
    @State private var geminiKey = ""

    var body: some View {
        @Bindable var prefs = app.prefs
        Form {
            Section {
                Picker(tr("Assistant"), selection: $prefs.v.aiProvider) {
                    ForEach(AIProvider.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                LabeledContent(tr("Apple Intelligence"), value: AIModel.appleStatus)
                TextEditor(text: $prefs.v.aiSystemPrompt).font(.body).frame(minHeight: 60)
                Text(tr("System prompt: how the assistant should behave. New chats use it.")).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                SecureField(tr("Anthropic API key"), text: $claudeKey)
                TextField(tr("Model"), text: $prefs.v.claudeModel)
                Picker(tr("Effort"), selection: $prefs.v.claudeEffort) {
                    Text(tr("Low (fastest)")).tag("low")
                    Text(tr("Medium")).tag("medium")
                    Text(tr("High")).tag("high")
                }
            } header: {
                Text("Claude")
            } footer: {
                Text(tr("Uses claude-opus-5-5 by default. If Claude declines a request, Anthropic's recommended fallback model answers instead."))
            }
            Section {
                SecureField(tr("Gemini API key"), text: $geminiKey)
                TextField(tr("Model"), text: $prefs.v.geminiModel)
            } header: {
                Text("Gemini")
            } footer: {
                Text(tr("Create a key in Google AI Studio. gemini-flash-latest always points at Google's newest Flash model."))
            }
            Section {
                HStack {
                    Spacer()
                    Button(tr("Save keys")) {
                        Secrets.set("anthropic", claudeKey)
                        Secrets.set("gemini", geminiKey)
                    }
                }
            } footer: {
                Text(tr("Keys are stored in your macOS keychain and only sent to their own service."))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            claudeKey = Secrets.get("anthropic")
            geminiKey = Secrets.get("gemini")
        }
    }
}
