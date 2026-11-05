import AppKit
import SwiftUI
import Translation

struct TranslateView: View {
    let app: AppModel
    @State private var typing: Task<Void, Never>?

    var body: some View {
        let m = app.translate!
        @Bindable var tm = m
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                LanguageMenu(selection: m.from, includeAuto: true, detected: m.from == "auto" ? m.detected : nil) { m.from = $0; m.translate() }
                IconButton(symbol: "arrow.left.arrow.right", size: 11, tint: Theme.text2, hit: 26, help: tr("Swap languages")) { m.swap(); m.translate() }
                LanguageMenu(selection: m.to, includeAuto: false) { m.setTarget($0); m.translate() }
                Spacer()
                Text(m.provider.short).font(Theme.font(10, .semibold)).foregroundStyle(Theme.lavender)
                    .padding(.horizontal, 8).frame(height: 20).background(Capsule().fill(Theme.lavender.opacity(0.14)))
            }
            HStack(spacing: 8) {
                Card(padding: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextEditor(text: $tm.source)
                            .font(Theme.font(12.5)).foregroundStyle(Theme.text)
                            .scrollContentBackground(.hidden).scrollIndicators(.never)
                            .overlay(alignment: .topLeading) {
                                if m.source.isEmpty {
                                    Text(tr("Type or paste text")).font(Theme.font(12.5)).foregroundStyle(Theme.text3).padding(.leading, 5).allowsHitTesting(false)
                                }
                            }
                        HStack(spacing: 6) {
                            PillButton(title: tr("Paste"), icon: "doc.on.clipboard", compact: true) { m.pasteFromClipboard() }
                            if !m.source.isEmpty { IconButton(symbol: "xmark", size: 9, tint: Theme.text3, hit: 20) { m.source = ""; m.result = "" } }
                            Spacer()
                            PillButton(title: tr("Translate"), icon: "character.bubble.fill", primary: true, tint: Theme.lavender, compact: true) { m.translate() }
                                .keyboardShortcut(.return, modifiers: .command)
                        }
                    }
                }
                Card(padding: 8, fill: Theme.cardHi.opacity(0.6)) {
                    VStack(alignment: .leading, spacing: 4) {
                        ScrollView(.vertical, showsIndicators: false) {
                            Group {
                                if m.busy {
                                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, alignment: .leading)
                                } else if let e = m.error {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(e).font(Theme.font(11.5)).foregroundStyle(Theme.butter)
                                        if m.needsDownload != nil {
                                            PillButton(title: tr("Download in Settings"), icon: "arrow.down.circle", compact: true) { app.commands.openSettings("translate") }
                                        }
                                    }
                                } else {
                                    Text(m.result).font(Theme.font(12.5)).foregroundStyle(Theme.text).textSelection(.enabled)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HStack {
                            Spacer()
                            if !m.result.isEmpty {
                                PillButton(title: tr("Copy"), icon: "doc.on.doc", compact: true) {
                                    app.clipboard?.copy(text: m.result)
                                    app.flash("checkmark.circle.fill", tr("Copied"), tint: Theme.mint)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: m.source) { _, _ in
            // Apple Translation is free and local: translate a moment after typing stops.
            guard m.provider == .apple else { return }
            typing?.cancel()
            typing = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.6))
                if !Task.isCancelled { m.translate() }
            }
        }
    }
}

struct LanguageMenu: View {
    let selection: String
    let includeAuto: Bool
    var detected: String? = nil
    let pick: (String) -> Void

    var body: some View {
        Menu {
            if includeAuto { Button(tr("Detect language")) { pick("auto") } }
            ForEach(Lang2.all) { l in Button(l.name) { pick(l.id) } }
        } label: {
            HStack(spacing: 4) {
                Text(label).font(Theme.font(11.5, .semibold)).foregroundStyle(Theme.text)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.text3)
            }
            .padding(.horizontal, 10).frame(height: 24)
            .background(Capsule().fill(Color.white.opacity(0.07)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var label: String {
        if selection == "auto" { return detected.map { tr("Auto: %@", Lang2(id: $0).name) } ?? tr("Detect language") }
        return Lang2(id: selection).name
    }
}

struct TranslatePane: View {
    let app: AppModel
    @State private var deepl = ""
    @State private var google = ""
    @State private var downloadFrom = "en"
    @State private var downloadTo = "id"
    @State private var config: TranslationSession.Configuration?
    @State private var status = ""

    var body: some View {
        @Bindable var prefs = app.prefs
        Form {
            Section {
                Picker(tr("Translate with"), selection: $prefs.v.translateProvider) {
                    ForEach(TranslateProvider.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                Picker(tr("Default target"), selection: $prefs.v.translateTo) {
                    ForEach(Lang2.all) { Text($0.name).tag($0.id) }
                }
            } footer: {
                Text(tr("Apple Translation and Apple Intelligence run on this Mac for free. DeepL and Google need your own API key."))
            }
            Section(tr("Download languages for Apple Translation")) {
                HStack {
                    Picker("", selection: $downloadFrom) { ForEach(Lang2.all) { Text($0.name).tag($0.id) } }.labelsHidden()
                    Image(systemName: "arrow.left.arrow.right")
                    Picker("", selection: $downloadTo) { ForEach(Lang2.all) { Text($0.name).tag($0.id) } }.labelsHidden()
                    Button(tr("Download")) {
                        config = TranslationSession.Configuration(source: Locale.Language(identifier: downloadFrom), target: Locale.Language(identifier: downloadTo))
                    }
                }
                if !status.isEmpty { Text(status).foregroundStyle(.secondary) }
            }
            .translationTask(config) { session in
                do {
                    try await session.prepareTranslation()
                    status = tr("Ready: %@ and %@ work offline now.", Lang2(id: downloadFrom).name, Lang2(id: downloadTo).name)
                } catch {
                    status = error.localizedDescription
                }
            }
            Section {
                SecureField("DeepL API key", text: $deepl)
                SecureField("Google Cloud Translation API key", text: $google)
                HStack {
                    Spacer()
                    Button(tr("Save keys")) {
                        Secrets.set("deepl", deepl)
                        Secrets.set("google-translate", google)
                    }
                }
            } header: {
                Text(tr("Your own keys (optional)"))
            } footer: {
                Text(tr("Keys are stored in your macOS keychain and only sent to that service."))
            }
            Section(tr("AI translation prompt")) {
                TextEditor(text: $prefs.v.translatePrompt).font(.body).frame(minHeight: 60)
                Text(tr("{{text}} is the text to translate, {{to}} the target language.")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            deepl = Secrets.get("deepl")
            google = Secrets.get("google-translate")
            downloadTo = app.prefs.v.translateTo
            if let n = app.translate.needsDownload { downloadFrom = n.0; downloadTo = n.1 }
        }
    }
}
