import AppKit
import FoundationModels
import NaturalLanguage
import Observation
import SwiftUI
import Translation

enum TranslateProvider: String, CaseIterable, Codable {
    case apple, deepl, google, ai

    var title: String {
        switch self {
        case .apple: tr("Apple (on this Mac)")
        case .deepl: "DeepL"
        case .google: "Google Cloud"
        case .ai: tr("Apple Intelligence")
        }
    }

    var short: String {
        switch self {
        case .apple: tr("On device")
        case .deepl: "DeepL"
        case .google: "Google"
        case .ai: tr("AI")
        }
    }
}

/// Languages offered in the pickers (Apple Translation covers all of them).
struct Lang2: Identifiable, Hashable {
    let id: String          // BCP 47, e.g. "id", "zh-Hans"
    var name: String { Locale(identifier: Lang.shared.isIndonesian ? "id" : "en").localizedString(forIdentifier: id) ?? id }

    static let all: [Lang2] = ["en", "id", "ja", "ko", "zh-Hans", "zh-Hant", "es", "fr", "de", "it", "pt", "nl", "ru", "uk", "pl",
                               "tr", "ar", "hi", "th", "vi", "sv", "da", "nb"].map(Lang2.init)
}

@MainActor @Observable
final class TranslateModel {
    var source = ""
    var result = ""
    var from = "auto"
    var to = "id"
    private(set) var busy = false
    private(set) var error: String?
    private(set) var detected: String?
    /// Apple Translation needs these languages downloaded first.
    private(set) var needsDownload: (String, String)?

    @ObservationIgnored private let prefs: Prefs
    @ObservationIgnored private var task: Task<Void, Never>?

    init(prefs: Prefs) {
        self.prefs = prefs
        to = prefs.v.translateTo
    }

    var provider: TranslateProvider { TranslateProvider(rawValue: prefs.v.translateProvider) ?? .apple }

    static func detect(_ text: String) -> String? {
        let r = NLLanguageRecognizer()
        r.processString(text)
        guard let l = r.dominantLanguage else { return nil }
        switch l {
        case .simplifiedChinese: return "zh-Hans"
        case .traditionalChinese: return "zh-Hant"
        case .norwegian: return "nb"
        default: return l.rawValue
        }
    }

    func swap() {
        let f = from == "auto" ? (detected ?? Self.detect(source) ?? "en") : from
        from = to
        to = f
        if !result.isEmpty { source = result; result = "" }
        prefs.v.translateTo = to
    }

    func setTarget(_ t: String) {
        to = t
        prefs.v.translateTo = t
    }

    /// Translates `source`. Apple runs on device; DeepL and Google use Angel's own keys; AI uses Apple Intelligence.
    func translate() {
        task?.cancel()
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { result = ""; error = nil; return }
        busy = true
        error = nil
        needsDownload = nil
        let src = from == "auto" ? Self.detect(text) : from
        detected = src
        let target = to
        let provider = provider
        let template = prefs.v.translatePrompt
        task = Task { @MainActor in
            defer { busy = false }
            do {
                let out: String
                switch provider {
                case .apple: out = try await Self.apple(text, from: src ?? "en", to: target)
                case .deepl: out = try await Self.deepl(text, to: target, key: Secrets.get("deepl"))
                case .google: out = try await Self.google(text, to: target, key: Secrets.get("google-translate"))
                case .ai: out = try await Self.ai(text, to: target, template: template)
                }
                if !Task.isCancelled { result = out }
            } catch TranslateError.notInstalled(let a, let b) {
                needsDownload = (a, b)
                error = tr("%@ to %@ needs a one-time download.", Lang2(id: a).name, Lang2(id: b).name)
            } catch {
                if !Task.isCancelled { self.error = (error as? TranslateError)?.message ?? error.localizedDescription }
            }
        }
    }

    enum TranslateError: Error {
        case notInstalled(String, String), unsupported, noKey(String), http(Int, String), aiUnavailable, sameLanguage
        var message: String {
            switch self {
            case .notInstalled: tr("These languages need a one-time download.")
            case .unsupported: tr("Apple Translation does not support this pair yet.")
            case .noKey(let s): tr("Add your %@ API key in Settings > Translate.", s)
            case .http(let code, let body): tr("The service answered %d: %@", code, body)
            case .aiUnavailable: tr("Apple Intelligence is not available on this Mac right now.")
            case .sameLanguage: tr("Pick a different target language.")
            }
        }
    }

    static func apple(_ text: String, from: String, to: String) async throws -> String {
        guard from != to else { throw TranslateError.sameLanguage }
        let s = Locale.Language(identifier: from), t = Locale.Language(identifier: to)
        switch await LanguageAvailability().status(from: s, to: t) {
        case .installed:
            let session = TranslationSession(installedSource: s, target: t)
            return try await session.translate(text).targetText
        case .supported: throw TranslateError.notInstalled(from, to)
        default: throw TranslateError.unsupported
        }
    }

    static func deepl(_ text: String, to: String, key: String) async throws -> String {
        guard !key.isEmpty else { throw TranslateError.noKey("DeepL") }
        let host = key.hasSuffix(":fx") ? "api-free.deepl.com" : "api.deepl.com"
        var req = URLRequest(url: URL(string: "https://\(host)/v2/translate")!)
        req.httpMethod = "POST"
        req.setValue("DeepL-Auth-Key \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let target = to == "pt" ? "PT-BR" : to == "zh-Hans" ? "ZH-HANS" : to == "zh-Hant" ? "ZH-HANT" : to == "nb" ? "NB" : to.uppercased()
        req.httpBody = try JSONSerialization.data(withJSONObject: ["text": [text], "target_lang": target])
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw TranslateError.http(code, String(decoding: data.prefix(200), as: UTF8.self)) }
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return ((obj?["translations"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
    }

    static func google(_ text: String, to: String, key: String) async throws -> String {
        guard !key.isEmpty else { throw TranslateError.noKey("Google Cloud") }
        var c = URLComponents(string: "https://translation.googleapis.com/language/translate/v2")!
        c.queryItems = [URLQueryItem(name: "key", value: key)]
        var req = URLRequest(url: c.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["q": text, "target": to == "zh-Hans" ? "zh-CN" : to == "zh-Hant" ? "zh-TW" : to, "format": "text"])
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw TranslateError.http(code, String(decoding: data.prefix(200), as: UTF8.self)) }
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let first = ((obj?["data"] as? [String: Any])?["translations"] as? [[String: Any]])?.first
        return (first?["translatedText"] as? String) ?? ""
    }

    /// AI translation with a prompt template: {{text}} and {{to}} get filled in.
    static func aiPrompt(_ template: String, text: String, to: String) -> String {
        template.replacingOccurrences(of: "{{to}}", with: Locale(identifier: "en").localizedString(forIdentifier: to) ?? to)
            .replacingOccurrences(of: "{{text}}", with: text)
    }

    static func ai(_ text: String, to: String, template: String) async throws -> String {
        guard case .available = SystemLanguageModel.default.availability else { throw TranslateError.aiUnavailable }
        let session = LanguageModelSession(instructions: "You translate text. Reply with the translation only, no notes, no quotes.")
        return try await session.respond(to: aiPrompt(template, text: text, to: to)).content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func pasteFromClipboard() {
        if let s = NSPasteboard.general.string(forType: .string) { source = s; translate() }
    }
}
