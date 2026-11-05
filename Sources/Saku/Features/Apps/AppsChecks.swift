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
    }

    static let scenes: [Render.Scene] = [
        Render.Scene(name: "open-apps", settle: 0.6) { app in
            app.launcher.query = ""
            app.notch.mode = .open
            app.notch.tab = .apps
        },
    ]
}
