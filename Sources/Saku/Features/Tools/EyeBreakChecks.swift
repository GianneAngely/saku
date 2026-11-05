import Foundation

@MainActor
enum EyeBreakChecks {
    static func run(_ app: AppModel) {
        func check(_ ok: Bool, _ name: String) { SelfTest.check(ok, name) }
        let e = app.eyeBreaks!
        check(EyeBreaks.idleSeconds >= 0, "idle time reads without permission")
        app.prefs.v.eyeBreakEvery = 20
        app.prefs.v.timerSound = false
        app.dismissAlert()
        var t = Date().addingTimeInterval(100_000)
        e.tick(now: t, idle: 0)
        for _ in 0..<38 { t = t.addingTimeInterval(30); e.tick(now: t, idle: 1) }   // 19 minutes
        check(app.notch.alert == nil, "no nudge before 20 minutes of screen time")
        for _ in 0..<3 { t = t.addingTimeInterval(30); e.tick(now: t, idle: 1) }
        check(app.notch.alert?.title == tr("Eye break"), "nudge after 20 minutes")
        app.dismissAlert()
        for _ in 0..<30 { t = t.addingTimeInterval(30); e.tick(now: t, idle: 1) }
        e.tick(now: t.addingTimeInterval(30), idle: 400)
        for _ in 0..<30 { t = t.addingTimeInterval(30); e.tick(now: t, idle: 1) }
        check(app.notch.alert == nil, "time away from the Mac resets the count")
        app.timers.pomo = Pomodoro()
        app.timers.pomoToggle()
        for _ in 0..<45 { t = t.addingTimeInterval(30); e.tick(now: t, idle: 1) }
        check(app.notch.alert == nil, "no nudge during focus")
        app.timers.pomoReset()
        app.timers.pomo = Pomodoro()
        app.prefs.v.eyeBreakEvery = 0
        for _ in 0..<100 { t = t.addingTimeInterval(30); e.tick(now: t, idle: 1) }
        check(app.notch.alert == nil, "off means off")
        app.prefs.v.timerSound = true
    }
}
