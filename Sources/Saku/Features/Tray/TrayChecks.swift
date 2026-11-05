import AppKit
import SwiftUI

@MainActor
enum TrayChecks {
    /// Makes a few real files in the scratch data folder.
    static func sampleFiles() -> [URL] {
        let dir = Paths.folder("qa-files")
        var out: [URL] = []
        let note = dir.appendingPathComponent("Meeting notes.txt")
        try? "Agenda\n- notch\n- teleprompter".write(to: note, atomically: true, encoding: .utf8)
        out.append(note)
        let png = dir.appendingPathComponent("Sakura moodboard.png")
        if let tiff = MockPlayer.demoArtwork().tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: png) }
        out.append(png)
        let pdf = dir.appendingPathComponent("Portfolio draft.pdf")
        let pdfData = NSMutableData()
        if let consumer = CGDataConsumer(data: pdfData) {
            var box = CGRect(x: 0, y: 0, width: 300, height: 400)
            if let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) {
                ctx.beginPDFPage(nil)
                ctx.setFillColor(NSColor(red: 1, green: 0.5, blue: 0.7, alpha: 1).cgColor)
                ctx.fill(CGRect(x: 30, y: 250, width: 240, height: 100))
                ctx.endPDFPage()
                ctx.closePDF()
            }
        }
        pdfData.write(to: pdf, atomically: true)
        out.append(pdf)
        return out
    }

    static func run(_ app: AppModel) {
        func check(_ ok: Bool, _ name: String) { SelfTest.check(ok, name) }
        let tray = app.tray!
        tray.clear()
        app.prefs.v.trayCopyFiles = false
        let files = sampleFiles()

        check(tray.add(DropPayload(files: files)) == 3, "three files land in the tray")
        check(tray.add(DropPayload(files: [files[0]])) == 0, "the same file is not added twice")
        check(tray.items.first?.name == "Portfolio draft.pdf", "newest first")
        check(tray.add(DropPayload(texts: ["https://example.com/a", "  ", "Hello from Saku"])) == 2, "links and text from text drops")
        check(tray.items.contains { $0.kind == .link && $0.link == "https://example.com/a" }, "a URL string becomes a link")
        check(tray.add(DropPayload(links: [URL(string: "https://example.com")!])) == 1, "link drop")
        let img = MockPlayer.demoArtwork().tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
        check(tray.add(DropPayload(images: [img ?? Data()])) == 1, "image data is saved as a file")
        let saved = tray.items.first!
        check(saved.owned && saved.path.hasPrefix(tray.ownFolder.path) && saved.exists, "dropped image lives in the tray folder")
        tray.remove(saved)
        check(!FileManager.default.fileExists(atPath: saved.path), "removing an owned file deletes Saku's copy")

        // Copy mode keeps its own copy.
        app.prefs.v.trayCopyFiles = true
        let extra = Paths.folder("qa-files").appendingPathComponent("Copy me.txt")
        try? "copy".write(to: extra, atomically: true, encoding: .utf8)
        tray.add(DropPayload(files: [extra]))
        let copied = tray.items.first!
        check(copied.owned && copied.path.hasPrefix(tray.ownFolder.path), "copy mode stores a copy")
        app.prefs.v.trayCopyFiles = false

        // Missing originals.
        let gone = Paths.folder("qa-files").appendingPathComponent("Gone.txt")
        try? "x".write(to: gone, atomically: true, encoding: .utf8)
        tray.add(DropPayload(files: [gone]))
        try? FileManager.default.removeItem(at: gone)
        check(tray.items.first.map { !$0.exists } ?? false, "a moved original shows as missing")
        tray.removeMissing()
        check(!tray.items.contains { $0.path == gone.path }, "remove missing files")

        // Saved between launches.
        let saved2 = JSONStore<TraySave>("tray.json").load()
        check(saved2?.items.map(\.id) == tray.items.map(\.id) && saved2?.items.map(\.path) == tray.items.map(\.path), "tray is saved")
        if let a = saved2?.items.first?.addedAt, let b = tray.items.first?.addedAt { check(abs(a.timeIntervalSince(b)) < 0.002, "dates keep milliseconds") }

        // Folders.
        tray.pin(folder: Paths.folder("qa-files"))
        tray.pin(folder: Paths.folder("qa-files"))
        check(tray.folders.count == 1, "a folder is pinned once")
        tray.unpin(tray.folders[0])
        check(tray.folders.isEmpty, "unpin")

        // Drag-out providers.
        let fileItem = tray.items.first { $0.kind == .file }!
        check(tray.provider(for: fileItem).hasItemConformingToTypeIdentifier("public.file-url"), "files drag out as files")
        let textItem = tray.items.first { $0.kind == .text }!
        check(tray.provider(for: textItem).canLoadObject(ofClass: NSString.self), "text drags out as text")

        // DropReader turns item providers into a payload.
        var payload: DropPayload?
        DropReader.read([NSItemProvider(object: files[0] as NSURL), NSItemProvider(object: "snippet" as NSString)]) { payload = $0 }
        let until = Date().addingTimeInterval(3)
        while payload == nil && Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        check(payload?.files.first?.path == files[0].path && payload?.texts == ["snippet"], "drop reader")

        // The notch drop handler.
        let before = tray.items.count
        app.handleDrop(DropPayload(texts: ["Dropped on the notch"]), zone: .tray)
        check(tray.items.count == before + 1 && app.notch.hud != nil, "notch drop adds and shows a HUD")
        app.notch.hud = nil
    }

    static let scenes: [Render.Scene] = [
        Render.Scene(name: "open-tray-empty", settle: 0.3) { app in
            app.tray.clear()
            app.notch.mode = .open
            app.notch.tab = .tray
        },
        Render.Scene(name: "open-tray", settle: 1.2) { app in
            app.tray.clear()
            app.tray.add(DropPayload(texts: ["Ideas: notch pet, sakura petals when a timer ends"]))
            app.tray.add(DropPayload(links: [URL(string: "https://gianneangely.itch.io")!]))
            app.tray.add(DropPayload(files: sampleFiles()))
            app.tray.pin(folder: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0])
            app.tray.pin(folder: FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0])
            app.notch.mode = .open
            app.notch.tab = .tray
        },
        Render.Scene(name: "drop-targets", settle: 0.3) { app in
            app.notch.mode = .drop
        },
    ]
}
