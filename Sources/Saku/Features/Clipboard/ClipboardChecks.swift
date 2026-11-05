import AppKit
import SwiftUI

@MainActor
enum ClipboardChecks {
    static func run(_ app: AppModel) {
        func check(_ ok: Bool, _ name: String) { SelfTest.check(ok, name) }
        let clip = app.clipboard!
        let pb = clip.pasteboard
        check(pb != NSPasteboard.general, "QA uses a private pasteboard")
        clip.clearHistory()
        for i in clip.history { clip.delete(i) }

        func put(_ s: String, rtf: Bool = false, types extra: [String] = []) {
            pb.clearContents()
            if rtf, let d = NSAttributedString(string: s, attributes: [.font: NSFont.boldSystemFont(ofSize: 12)])
                .rtf(from: NSRange(location: 0, length: s.count), documentAttributes: [:]) { pb.setData(d, forType: .rtf) }
            pb.setString(s, forType: .string)
            for t in extra { pb.setString("", forType: .init(t)) }
        }

        put("Hello notch")
        check(clip.capture(from: pb, app: "Notes")?.kind == .text, "plain text is captured")
        put("https://open.spotify.com/track/x")
        check(clip.capture(from: pb)?.kind == .link, "a URL is captured as a link")
        put("Hello notch")
        clip.capture(from: pb)
        check(clip.history.count == 2 && clip.history.first?.text == "Hello notch", "copying the same text again moves it up")
        put("Bold words", rtf: true)
        let rich = clip.capture(from: pb)
        check(rich?.rtfFile != nil && clip.rtf(of: rich!) != nil, "rich text keeps its formatting")
        put("hunter2", types: ["org.nspasteboard.ConcealedType"])
        check(clip.capture(from: pb) == nil, "password manager secrets are skipped")
        put("from 1Password")
        check(clip.capture(from: pb, appID: "com.1password.1password") == nil, "ignored apps are skipped")
        pb.clearContents()
        let png = MockPlayer.demoArtwork().tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }!
        pb.setData(png, forType: .png)
        let img = clip.capture(from: pb)
        check(img?.kind == .image && (img?.width ?? 0) > 0 && clip.image(of: img!) != nil, "images are captured as files")
        pb.clearContents()
        let files = TrayChecks.sampleFiles()
        pb.writeObjects(files.map { $0 as NSURL })
        check(clip.capture(from: pb)?.kind == .files, "copied files are captured")

        // Copying back writes to the pasteboard and is not recorded again.
        let before = clip.history.count
        let hello = clip.history.first { $0.text == "Hello notch" }!
        clip.copy(hello)
        check(pb.string(forType: .string) == "Hello notch", "copy writes the text")
        clip.tick()
        check(clip.history.count == before && clip.history.first?.id == hello.id, "Saku's own copy is not recorded twice")
        clip.copy(rich!, plain: true)
        check(pb.data(forType: .rtf) == nil, "copy as plain text drops formatting")

        // Search, pin, limit, clear.
        check(clip.search("spotify").count == 1 && clip.search("NOTCH").first?.text == "Hello notch", "search is case-insensitive")
        clip.togglePin(clip.history.last!)
        check(clip.search("").first?.pinned == true, "pinned items come first")
        app.prefs.v.clipboardLimit = 10
        for i in 0..<15 { put("item \(i)"); clip.capture(from: pb) }
        check(clip.history.filter { !$0.pinned }.count == 10 && clip.history.contains { $0.pinned }, "history is trimmed, pinned items stay")
        clip.clearHistory()
        check(clip.history.count == 1 && clip.history[0].pinned, "clear keeps pinned items")
        app.prefs.v.clipboardLimit = 200
        app.prefs.v.clipboardPaused = true
        put("while paused")
        clip.tick()
        check(!clip.history.contains { $0.text == "while paused" }, "paused history records nothing")
        app.prefs.v.clipboardPaused = false

        // Snippets.
        let s = clip.addSnippet(title: "Email", text: "hi@example.com", collection: "Work")
        check(clip.collections.contains("Work") && clip.snippets(in: "Work").count == 1, "snippet with a collection")
        var edited = s
        edited.text = "angel@example.com"
        clip.updateSnippet(edited)
        check(clip.snippets.first?.text == "angel@example.com", "snippet edit")
        check(clip.snippets(in: nil, matching: "angel").count == 1, "snippet search")
        clip.deleteCollection("Work")
        check(clip.snippets.first?.collection == "", "deleting a collection keeps its snippets")
        clip.deleteSnippet(s)
        check(clip.snippets.isEmpty, "snippet delete")

        clip.saveNow()
        check(JSONStore<ClipboardSave>("clipboard.json").load()?.history.map(\.id) == clip.history.map(\.id), "history is saved")

        let now = Date()
        check(RelativeTime.short(now.addingTimeInterval(-20), now: now) == tr("now") && RelativeTime.short(now.addingTimeInterval(-300), now: now) == "5m", "relative time")
    }

    static let scenes: [Render.Scene] = [
        Render.Scene(name: "open-clipboard", settle: 0.5) { app in
            fill(app)
            app.clipboard.mode = 0
            app.notch.mode = .open
            app.notch.tab = .clipboard
        },
        Render.Scene(name: "open-clipboard-snippets", settle: 0.5) { app in
            let c = app.clipboard!
            for s in c.snippets { c.deleteSnippet(s) }
            c.addCollection("Work")
            c.addCollection("Itch.io")
            _ = c.addSnippet(title: "Cake Tower link", text: "https://gianneangely.itch.io/cake-tower", collection: "Itch.io")
            _ = c.addSnippet(title: "Thanks reply", text: "Thank you so much for playing! Updates every Friday.", collection: "Itch.io")
            _ = c.addSnippet(title: "Meeting intro", text: "Hi everyone, I'm Angel, an informatics student and game developer.", collection: "Work")
            c.mode = 1
            app.notch.mode = .open
            app.notch.tab = .clipboard
        },
    ]

    static func fill(_ app: AppModel) {
        let c = app.clipboard!
        let pb = c.pasteboard
        for i in c.history { c.delete(i) }
        let entries: [(String, String)] = [
            ("Sakura palette: #FF7EB6 #E36A9A #FFD66B #C7A6FF", "Figma"),
            ("https://gianneangely.itch.io/cake-tower", "Google Chrome"),
            ("git commit -m \"Add notch tray\"", "Terminal"),
            ("Meeting at 14:00 with the design team about the onboarding flow and the new icon.", "Notes"),
            ("Hi from the café!", "Messages"),
        ]
        for (text, appName) in entries.reversed() {
            pb.clearContents()
            pb.setString(text, forType: .string)
            c.capture(from: pb, app: appName)
        }
        pb.clearContents()
        if let png = MockPlayer.demoArtwork().tiffRepresentation.flatMap({ NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }) {
            pb.setData(png, forType: .png)
            c.capture(from: pb, app: "Preview")
        }
        c.togglePin(c.history.first { $0.text.hasPrefix("Sakura") }!)
    }
}
