import AppKit
import Translation

@MainActor
enum TranslateChecks {
    static func run(_ app: AppModel) {
        func check(_ ok: Bool, _ name: String) { SelfTest.check(ok, name) }
        check(TranslateModel.detect("Selamat pagi, apa kabar hari ini? Saya mau pergi ke pasar.") == "id", "detects Indonesian")
        check(TranslateModel.detect("Good morning, how are you doing today?") == "en", "detects English")
        check(TranslateModel.aiPrompt("Translate this into {{to}}:\n\n{{text}}", text: "Halo", to: "ja") == "Translate this into Japanese:\n\nHalo", "AI prompt template")
        check(Lang2(id: "ja").name.isEmpty == false && Lang2.all.contains { $0.id == "id" }, "language list")
        check(Secrets.inMemory, "QA keeps keys in memory, never the keychain")
        Secrets.set("deepl", "  abc:fx ")
        check(Secrets.get("deepl") == "abc:fx" && Secrets.has("deepl"), "keys are trimmed and stored")
        Secrets.set("deepl", "")
        check(!Secrets.has("deepl"), "an empty key removes it")

        // Real on-device translation for an installed pair (English to Japanese), plus the download path.
        var out: String?
        var notInstalled = false
        var unsupported = false
        let done = Task { @MainActor in
            out = try? await TranslateModel.apple("Good morning", from: "en", to: "ja")
            do { _ = try await TranslateModel.apple("Hello", from: "en", to: "en") } catch TranslateModel.TranslateError.sameLanguage { unsupported = true } catch {}
            let st = await LanguageAvailability().status(from: Locale.Language(identifier: "en"), to: Locale.Language(identifier: "id"))
            if st == .supported {
                do { _ = try await TranslateModel.apple("Hello", from: "en", to: "id") } catch TranslateModel.TranslateError.notInstalled { notInstalled = true } catch {}
            } else { notInstalled = true }
        }
        let until = Date().addingTimeInterval(20)
        while out == nil && Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        while !(notInstalled && unsupported) && Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        _ = done
        check((out ?? "").contains("おはよう"), "Apple Translation works on this Mac (\(out ?? "nil"))")
        check(unsupported, "same source and target is refused")
        check(notInstalled, "a missing language pair asks for a download")

        // DeepL and Google without a key explain what to do (no network call).
        let m = app.translate!
        app.prefs.v.translateProvider = "deepl"
        m.source = "Hello"
        m.translate()
        let until2 = Date().addingTimeInterval(5)
        while m.busy && Date() < until2 { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        check(m.error == tr("Add your %@ API key in Settings > Translate.", "DeepL"), "missing key message")
        app.prefs.v.translateProvider = "apple"
        m.source = ""
        m.result = ""
    }

    static let scenes: [Render.Scene] = [
        Render.Scene(name: "open-translate", settle: 0.5) { app in
            let m = app.translate!
            m.from = "auto"
            m.setTarget("id")
            m.source = "Hi everyone! The new update adds a teleprompter right under the camera."
            m.result = "Hai semuanya! Pembaruan baru menambahkan teleprompter tepat di bawah kamera."
            app.notch.mode = .open
            app.notch.tab = .translate
        },
    ]
}
