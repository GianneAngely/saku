import AppKit
import WebKit

@MainActor
enum WebChecks {
    static func run(_ app: AppModel) {
        func check(_ ok: Bool, _ name: String) { SelfTest.check(ok, name) }
        let g = SearchEngine.google
        check(WebModel.target(for: "https://apple.com/mac", engine: g)?.absoluteString == "https://apple.com/mac", "full URLs load as typed")
        check(WebModel.target(for: "itch.io", engine: g)?.absoluteString == "https://itch.io", "a bare domain gets https")
        check(WebModel.target(for: "localhost:4321/mascot", engine: g)?.absoluteString == "http://localhost:4321/mascot", "localhost works")
        check(WebModel.target(for: "how tall is mount agung", engine: g)?.absoluteString == "https://www.google.com/search?q=how%20tall%20is%20mount%20agung", "words search")
        check(WebModel.target(for: "file.v2", engine: .duckduckgo)?.host() == "duckduckgo.com", "a dotted word with digits searches")
        check(WebModel.target(for: "   ", engine: g) == nil, "empty input does nothing")
        check(SearchEngine.allCases.allSatisfy { $0.url(for: "mascot") != nil }, "every engine builds a search URL")

        app.notch.mode = .open
        app.notch.tab = .web
        check(app.openSize.height == max(app.prefs.v.openHeight, app.prefs.v.webHeight), "the Web tab opens taller")
        app.notch.tab = .home
        check(app.openSize.height == app.prefs.v.openHeight, "other tabs keep the normal size")
        app.notch.mode = .closed
        check(app.maxPanelSize.height >= app.prefs.v.webHeight, "the panel window is big enough for the Web tab")
        check(app.web.view.needsPanelToBecomeKey, "clicking a page lets you type in it")
        check(app.web.view.customUserAgent == WebModel.mobileAgent, "mobile layout by default")

        // Bookmarks.
        let b = app.bookmarks!
        for i in b.items { b.delete(i.id) }
        b.toggle(title: "itch.io", url: "https://itch.io/games")
        b.toggle(title: "", url: "https://github.com/GianneAngely")
        b.toggle(title: "bad", url: "notaurl")
        check(b.items.count == 2 && b.items[1].title == "github.com", "bookmarks add, untitled ones use the host")
        check(b.contains("https://itch.io/games") && b.items[0].initial == "I", "bookmark lookup and initial")
        b.toggle(title: "itch.io", url: "https://itch.io/games")
        check(!b.contains("https://itch.io/games"), "starring again removes it")
        check(JSONStore<[Bookmark]>("bookmarks.json").load()?.count == 1, "bookmarks are saved")
        for i in b.items { b.delete(i.id) }
    }

    /// Loads a local page in the real web view and takes a snapshot of it (no network).
    static func live(_ app: AppModel, _ c: NotchController) async {
        let w = app.web!
        c.open(.web)
        w.view.loadHTMLString("<html><body style='background:#15121A;color:#F7F2F6;font:24px -apple-system'><h1 id=t>Saku web</h1></body></html>", baseURL: nil)
        var waited = 0.0
        while w.view.isLoading && waited < 5 { try? await Task.sleep(for: .seconds(0.1)); waited += 0.1 }
        try? await Task.sleep(for: .seconds(0.3))
        let text = try? await w.view.evaluateJavaScript("document.getElementById('t').textContent") as? String
        LiveTest.expect(text == "Saku web", "the web view renders a page", text ?? "nil")
        let cfg = WKSnapshotConfiguration()
        let img = try? await w.view.takeSnapshot(configuration: cfg)
        LiveTest.expect((img?.size.width ?? 0) > 100, "the page can be snapshotted")
        LiveTest.expect(abs(c.interactiveRect.height - max(app.prefs.v.openHeight, app.prefs.v.webHeight)) < 0.5, "the open notch is taller on the Web tab")
        w.home()
        c.close()
    }

    static let scenes: [Render.Scene] = [
        Render.Scene(name: "open-web", settle: 0.5) { app in
            app.web.home()
            let b = app.bookmarks!
            for i in b.items { b.delete(i.id) }
            for (t, u) in [("itch.io", "https://gianneangely.itch.io"), ("GitHub", "https://github.com/GianneAngely"), ("Figma", "https://figma.com"),
                           ("Pinterest", "https://pinterest.com"), ("Notion", "https://notion.so"), ("YouTube", "https://youtube.com"),
                           ("Claude", "https://claude.ai"), ("Translate", "https://translate.google.com")] { b.toggle(title: t, url: u) }
            app.notch.mode = .open
            app.notch.tab = .web
        },
    ]
}
