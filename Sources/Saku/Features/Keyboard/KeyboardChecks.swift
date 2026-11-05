import AppKit
import Carbon.HIToolbox

@MainActor
enum KeyboardChecks {
    static func run(_ app: AppModel) {
        func check(_ ok: Bool, _ name: String) { SelfTest.check(ok, name) }
        let h = app.hotkeys!
        check(HotkeySpec(keyCode: kVK_ANSI_V, mods: controlKey | optionKey).display == "⌃⌥V", "shortcut text")
        check(HotkeySpec(keyCode: kVK_Space, mods: cmdKey | shiftKey).display == "⇧⌘" + tr("Space"), "modifier order")
        check(h.spec(.toggle) == HotkeyAction.defaults["toggle"], "defaults apply")
        check(h.spec(.notes) == nil, "unbound actions have no keys")
        let rare = HotkeySpec(keyCode: kVK_F19, mods: controlKey | optionKey | cmdKey | shiftKey)
        h.set(.notes, rare)
        check(h.spec(.notes) == rare && app.prefs.v.hotkeys["notes"] == rare, "custom shortcut saved")
        h.set(.toggle, nil)
        check(h.spec(.toggle) == nil && app.prefs.v.hotkeysCleared.contains("toggle"), "a default can be removed")
        // Register only the rare combo for real, then unregister (no common key is ever taken by a test).
        app.prefs.v.hotkeysCleared = HotkeyAction.allCases.map(\.rawValue).filter { $0 != "notes" }
        h.apply()
        check(h.registeredCount == 1 && h.conflicts.isEmpty, "a free shortcut registers with macOS")
        app.prefs.v.hotkeys["notes"] = nil
        app.prefs.v.hotkeys["tray"] = rare
        app.prefs.v.hotkeys["web"] = rare
        app.prefs.v.hotkeysCleared = HotkeyAction.allCases.map(\.rawValue).filter { $0 != "tray" && $0 != "web" }
        h.apply()
        check(h.conflicts.count == 1, "the same keys twice are reported")
        h.unregisterAll()
        check(h.registeredCount == 0, "unregister")
        h.resetAll()
        h.unregisterAll()
        check(h.spec(.toggle) == HotkeyAction.defaults["toggle"], "restore defaults")
        check(HotkeyAction.defaults.values.allSatisfy { $0.mods & UInt32(controlKey | optionKey) == UInt32(controlKey | optionKey) }, "defaults use ⌃⌥")
        let rectangle: Set<Int> = [kVK_ANSI_U, kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_D, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_E, kVK_ANSI_T,
                                   kVK_ANSI_C, kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Return, kVK_Delete,
                                   kVK_ANSI_Equal, kVK_ANSI_Minus]
        check(HotkeyAction.defaults.values.allSatisfy { !rectangle.contains(Int($0.keyCode)) }, "defaults avoid Rectangle's keys")

        // Actions reach the features.
        app.timers.pomo = Pomodoro()
        h.perform(.pomodoro)
        check(app.timers.pomo.running, "Pomodoro shortcut starts focus")
        h.perform(.pomodoro)
        check(!app.timers.pomo.running, "and pauses it")
        app.timers.pomo = Pomodoro()
        app.notch.hud = nil
        let speed = app.prefs.v.prompterSpeed
        h.perform(.prompterFaster)
        check(app.prefs.v.prompterSpeed == speed + 10, "faster shortcut")
        app.prefs.v.prompterSpeed = speed
    }
}
