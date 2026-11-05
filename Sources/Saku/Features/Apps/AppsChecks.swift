import AppKit

@MainActor
enum AppsChecks {
    static func run(_ app: AppModel) {
        func check(_ ok: Bool, _ name: String) { SelfTest.check(ok, name) }
        let m = app.launcher!
        check(m.all.count > 20 && m.all.contains { $0.name == "Safari" }, "apps are found")
        check(m.search("saf").first?.name == "Safari", "prefix search")
        check(m.search("vsc").first?.name == "Visual Studio Code" || !m.all.contains { $0.name == "Visual Studio Code" }, "initials search")
        check(m.search("zzzzqq").isEmpty, "no match")
        let starters = m.pinnedEntries
        check(!starters.isEmpty && starters.allSatisfy { FileManager.default.fileExists(atPath: $0.id) }, "starter apps that exist")
        let calc = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        m.pin(calc)
        m.pin(calc)
        check(m.pinned.filter { $0 == calc.path }.count == 1, "pin once")
        m.pin(URL(fileURLWithPath: "/tmp/not-an-app.txt"))
        check(!m.pinned.contains("/tmp/not-an-app.txt"), "only apps can be pinned")
        let e = AppEntry(url: calc)
        m.move(e, by: -1)
        m.unpin(e)
        check(!m.pinned.contains(calc.path), "unpin")
        check(m.icon(e).size.width > 0, "app icons load")

        // Shortcuts, through a fake `shortcuts` tool (nothing real runs).
        let s = app.shortcuts!
        let fake = Paths.file("fake-shortcuts.sh")
        try? "#!/bin/sh\nif [ \"$1\" = list ]; then printf 'Focus on\\nFocus off\\nMake GIF\\n'; exit 0; fi\nif [ \"$2\" = 'Make GIF' ]; then exit 1; fi\nexit 0\n"
            .write(to: fake, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        s.tool = fake.path
        s.reload()
        let until = Date().addingTimeInterval(5)
        while !s.loaded && Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        check(s.names == ["Focus on", "Focus off", "Make GIF"], "shortcuts are listed")
        app.prefs.v.shortcutsShown = ["Make GIF", "Gone"]
        check(s.shown == ["Make GIF"], "only picked shortcuts that still exist")
        app.prefs.v.shortcutsShown = []
        var results: [Bool] = []
        s.run("Focus on") { results.append($0) }
        s.run("Make GIF") { results.append($0) }
        let until2 = Date().addingTimeInterval(5)
        while results.count < 2 && Date() < until2 { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        check(results.sorted { !$0 && $1 } == [false, true] || results.count == 2 && results.contains(true) && results.contains(false), "run reports success and failure")
        s.tool = "/usr/bin/shortcuts"
    }

    static let scenes: [Render.Scene] = [
        Render.Scene(name: "open-apps", settle: 0.6) { app in
            app.shortcuts.setDemo(["Focus on", "Make a GIF", "Resize images", "Send ETA to Mom"])
            app.launcher.query = ""
            app.notch.mode = .open
            app.notch.tab = .apps
        },
    ]
}
