import AppKit
import SwiftUI

/// `Saku --selftest`: logic checks that run inside the real binary (no window, no sound, scratch data folder).
@MainActor
enum SelfTest {
    private static var passed = 0
    private static var failed: [String] = []
    private static var suite = ""

    static func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
        if ok {
            passed += 1
        } else {
            let d = detail()
            failed.append("\(suite): \(name)\(d.isEmpty ? "" : " (\(d))")")
        }
    }

    static func section(_ name: String) { suite = name }

    /// Feature branches append their suites here (see Features.install).
    static var suites: [(String, @MainActor (AppModel) -> Void)] = [
        ("core", core),
    ]

    static func run(app: AppModel) -> Bool {
        for (name, body) in suites {
            section(name)
            body(app)
        }
        print("selftest: \(passed) passed, \(failed.count) failed")
        for f in failed { print("  FAIL \(f)") }
        QA.cleanUp()
        return failed.isEmpty
    }

    static func core(_ app: AppModel) {
        // Prefs: saved JSON laid over defaults, unknown keys ignored, wrong types fall back.
        let partial = try! JSONSerialization.data(withJSONObject: ["openWidth": 700, "bogus": 1, "language": "id"])
        let p = Prefs.load(from: partial)
        check(p.openWidth == 700, "prefs keeps saved value")
        check(p.openHeight == PrefsData().openHeight, "prefs fills missing value")
        check(p.language == "id", "prefs string value")
        let wrong = try! JSONSerialization.data(withJSONObject: ["openWidth": "wide"])
        check(Prefs.load(from: wrong) == PrefsData(), "prefs with a wrong type falls back to defaults")
        check(Prefs.load(from: nil) == PrefsData(), "prefs without data")

        // Language.
        let before = Lang.shared.code
        Lang.shared.code = "en"
        check(tr("Settings") == "Settings", "english passthrough")
        Lang.shared.code = "id"
        check(tr("zz unknown zz") == "zz unknown zz", "missing translation falls back")
        check(tr("Settings") == "Pengaturan" && Tab.home.title == "Beranda" && tr("%d words", 5) == "5 kata", "Bahasa Indonesia")
        check(Indonesian.table.values.allSatisfy { v in
            !v.split(whereSeparator: { ".!?\n".contains($0) }).contains { $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("yang ") }
        }, "no Indonesian sentence starts with Yang")
        check(Indonesian.table.count > 500, "Indonesian covers the whole app")
        Lang.shared.code = before

        // Colours.
        check(Color(hexString: "#FF7EB6")?.hexString == "#FF7EB6", "hex round trip")
        check(Color(hexString: "nope") == nil, "bad hex rejected")

        // Geometry.
        let g = NotchGeo.detect()
        if g.real {
            check(abs(g.notchW - 185) < 0.6 && g.notchH == 32, "measured notch is 185 x 32 on this Mac", "\(g.notchW) x \(g.notchH)")
        }
        let r = g.topRect(width: 660, height: 236)
        check(abs(r.midX - (g.screenFrame.minX + g.midX)) < 0.01 && r.maxY == g.screenFrame.maxY, "open rect hangs centred from the top")
        let tuned = NotchGeo.detect(widthOffset: 10, heightOffset: -4)
        check(abs(tuned.notchW - (g.notchW + 10)) < 0.01 && tuned.notchH == g.notchH - 4, "fine-tuning offsets apply")

        // Live activity and closed size.
        app.prefs.v.closedStyle = "none"
        app.prefs.v.idleMark = "none"
        app.notch.hud = nil
        check(app.liveActivity == .none, "plain style has no wings")
        check(app.closedSize.width == app.notch.geo.notchW, "plain closed notch is notch-sized")
        app.prefs.v.closedStyle = "date"
        check(app.liveActivity == .date, "date style")
        check(app.closedSize.width == app.notch.geo.notchW + 2 * (LiveActivity.date.wing + 6), "wings are symmetric")
        app.notch.hud = NotchHUD(icon: "x", text: "Hi")
        check(app.liveActivity == .hud(app.notch.hud!), "hud wins over the idle style")
        app.notch.hud = nil
        app.prefs.v.closedStyle = "auto"

        // Tabs.
        app.prefs.v.hiddenTabs = ["home"]
        check(app.visibleTabs.contains(.home), "home cannot be hidden")
        app.prefs.v.hiddenTabs = []
        check(app.visibleTabs.first == .home, "home first by default")

        // Tab bar: everything fits at the default width, overflow goes into a menu.
        let eight = Array(Tab.allCases.prefix(8)), all = Tab.allCases
        let l8 = TabBar.layout(tabs: eight, panelWidth: 660, notchWidth: 185)
        check(l8.more.isEmpty && l8.left.count + l8.right.count == 8 && l8.left.count >= l8.right.count, "eight tabs fit around the camera")
        let l15 = TabBar.layout(tabs: all, panelWidth: 660, notchWidth: 185)
        check(!l15.more.isEmpty && l15.left.count + l15.right.count + l15.more.count == all.count, "extra tabs go into the more menu")
        let side = (660.0 - 185 - 20 - 32) / 2
        check(Double(l15.left.count) * TabBar.iconWidth <= side && Double(l15.right.count + 1) * TabBar.iconWidth + TabBar.toolsWidth <= side, "icons never overflow")
        check(TabBar.layout(tabs: all, panelWidth: 820, notchWidth: 185).more.count < l15.more.count, "a wider panel shows more tabs")

        // JSON store round trip.
        struct Sample: Codable, Equatable { var a: Int; var d: Date }
        let store = JSONStore<Sample>("selftest-sample.json")
        let sample = Sample(a: 7, d: Date(timeIntervalSince1970: 1_000_000))
        store.save(sample)
        check(store.load() == sample, "json store round trip")
        try? FileManager.default.removeItem(at: store.url)
    }
}

enum QA {
    static let suiteName = "local.saku.app.qa"

    /// Removes the QA defaults domain and scratch data so test runs leave nothing behind.
    static func cleanUp() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        let tmp = FileManager.default.temporaryDirectory.path
        if Paths.dataDir.path.hasPrefix(tmp) { try? FileManager.default.removeItem(at: Paths.dataDir) }
    }
}
