import AppKit
import SwiftUI

@MainActor
enum FinderChecks {
    static func run(_ app: AppModel) {
        func check(_ ok: Bool, _ name: String) { SelfTest.check(ok, name) }
        let all = FeatureCatalog.all

        // The list itself.
        check(Set(all.map(\.id)).count == all.count, "feature ids are unique")
        check(all.allSatisfy { !$0.title.isEmpty && !$0.place.isEmpty }, "every feature says where it lives")
        check(all.count >= 30, "every feature is listed (\(all.count))")

        // Search in English and Indonesian.
        func first(_ q: String) -> String? { all.first { $0.matches(q) }?.id }
        check(first("battery") == "battery" && first("baterai") == "battery", "battery in both languages")
        check(first("siklus") == "battery" && first("cycles") == "battery", "battery cycles")
        check(first("air minum") == "water" && first("water") == "water", "water tracker")
        check(first("hitung mundur") == "countdown", "countdown in Indonesian")
        check(all.filter { $0.matches("timer") }.count >= 2, "timer finds the timers")
        check(first("BATERAI") == "battery" && first("  wifi ") == "network", "search ignores case and spaces")
        check(all.filter { $0.matches("zzqq") }.isEmpty, "nonsense finds nothing")

        // Jumping there: right tab, right mode, the card glows. Settings never really open during a test.
        let realCommands = app.commands
        var panes: [String] = []
        app.commands.openSettings = { panes.append($0 ?? "") }
        app.commands.closeNotch = {}
        defer { app.commands = realCommands }
        app.notch.mode = .open
        app.toggleFinder()
        check(app.notch.finder, "grid button opens All features")
        all.first { $0.id == "battery" }?.go(app)
        check(app.notch.tab == .system && app.notch.highlight == "battery" && !app.notch.finder, "battery opens the System tab and lights its card")
        all.first { $0.id == "water" }?.go(app)
        check(app.notch.tab == .trackers && app.notch.highlight == "water", "water opens Trackers")
        all.first { $0.id == "countdown" }?.go(app)
        check(app.notch.tab == .timers && app.timers.mode == .countdown, "countdown opens its timer")
        all.first { $0.id == "reminders" }?.go(app)
        check(app.notch.tab == .calendar && app.calendar.showReminders, "reminders open the Reminders list")
        all.first { $0.id == "snippets" }?.go(app)
        check(app.notch.tab == .clipboard && app.clipboard.mode == 1, "snippets open in Clipboard")
        app.calendar.showReminders = false
        app.clipboard.mode = 0
        app.timers.mode = .pomodoro

        // Every tab can be reached from the list, so tabs that don't fit in the bar are never lost.
        for t in Tab.available {
            app.notch.tab = .home
            let reach = all.contains { f in
                f.go(app)
                return app.notch.tab == t
            }
            check(reach, "\(t.rawValue) tab is in All features")
        }

        // Features that live in Settings open the right pane.
        panes = []
        for id in ["browser-music", "google-calendar", "eye-breaks", "focus-hooks", "keyboard", "look"] { all.first { $0.id == id }?.go(app) }
        check(panes == ["music", "calendar", "tools", "timers", "keyboard", "appearance"] && panes.allSatisfy { SettingsPane(rawValue: $0) != nil },
              "settings features open their pane")

        // Closing resets the page.
        app.toggleFinder()
        app.notch.finderQuery = "water"
        app.notch.mode = .closed
        check(!app.notch.finder && app.notch.finderQuery.isEmpty && app.notch.highlight == nil, "closing the notch resets All features")
        app.select(.home)

        // The shortcut for it.
        let spec = HotkeyAction.defaults["features"]
        check(spec?.display.hasPrefix("⌃⌥") == true, "All features has a default shortcut")
        let specs = Array(HotkeyAction.defaults.values)
        check(Set(specs).count == specs.count, "default shortcuts don't clash")
    }

    static let scenes: [Render.Scene] = [
        Render.Scene(name: "open-finder", settle: 0.6) { app in
            app.notch.mode = .open
            app.notch.finder = true
        },
        Render.Scene(name: "open-finder-search", settle: 0.6) { app in
            app.notch.mode = .open
            app.notch.finder = true
            app.notch.finderQuery = "baterai"
        },
        Render.Scene(name: "open-system-spotlight", settle: 0.6) { app in
            app.monitor.fillDemo()
            app.battery.apply(BatteryInfo(present: true, level: 76, onAC: false, minutesToEmpty: 312, health: 88, cycles: 113, temperature: 31.5))
            app.notch.mode = .open
            app.notch.tab = .system
            app.notch.highlight = "battery"
        },
    ]
}
