import AppKit
import SwiftUI

@MainActor
enum TimerChecks {
    static func run(_ app: AppModel) {
        func check(_ ok: Bool, _ name: String) { SelfTest.check(ok, name) }
        var p = PrefsData()
        p.pomoFocus = 25; p.pomoShort = 5; p.pomoLong = 15; p.pomoLongEvery = 4
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)

        // Pure cycle logic.
        var pomo = Pomodoro()
        check(!pomo.started && pomo.left(at: t0, p) == 1500, "fresh focus is full length")
        pomo.start(at: t0, p)
        check(pomo.running && pomo.endsAt == t0.addingTimeInterval(1500), "start sets the deadline")
        pomo.pause(at: t0.addingTimeInterval(600), p)
        check(!pomo.running && pomo.remaining == 900, "pause keeps what is left")
        pomo.start(at: t0.addingTimeInterval(1000), p)
        check(pomo.endsAt == t0.addingTimeInterval(1900), "resume continues from what is left")
        var cycle = Pomodoro()
        var phases: [Pomodoro.Phase] = []
        for _ in 0..<9 { cycle.advance(p, today: "d1", counted: true); phases.append(cycle.phase) }
        check(phases == [.short, .focus, .short, .focus, .short, .focus, .long, .focus, .short], "4 focus sessions then a long break")
        check(cycle.doneToday == 5, "finished focus sessions are counted")
        cycle.advance(p, today: "d2", counted: false)
        check(cycle.doneToday == 0 && cycle.today("d2") == 0 && cycle.today("d1") == 0, "a new day starts from zero")
        var skip = Pomodoro()
        skip.advance(p, today: "d1", counted: false)
        check(skip.doneToday == 0 && skip.phase == .short, "skipping a focus does not count it")

        // Clock text.
        check(TimerDisplay.clock(65.2, roundUp: true) == "1:06" && TimerDisplay.clock(65.8, roundUp: false) == "1:05", "clock rounding")
        check(TimerDisplay.clock(3725, roundUp: false) == "1:02:05", "clock hours")
        let d = TimerDisplay(icon: "x", tint: .white, anchor: t0.addingTimeInterval(30), frozen: 0, total: 120)
        check(abs(d.progress(at: t0) - 0.75) < 0.001 && d.text(at: t0) == "0:30", "display progress and text")

        // Model: start, finish, alert, auto-start, live activity.
        let m = app.timers!
        app.prefs.v.pomoFocus = 25
        app.prefs.v.pomoAutoStart = false
        app.prefs.v.timerAlert = true
        app.prefs.v.closedStyle = "auto"
        m.pomo = Pomodoro()
        let now = Date()
        m.pomoToggle(now: now)
        check(m.pomo.running, "model starts")
        if case .timer = app.liveActivity {} else { check(false, "running pomodoro shows in the closed notch") }
        m.check(now: now.addingTimeInterval(1501))
        check(m.pomo.phase == .short && !m.pomo.running, "finishing focus moves to a paused break")
        check(app.notch.alert?.title == tr("Focus done!"), "focus done alert")
        check(app.notch.alert?.actions.count == 2, "alert offers start and skip")
        app.notch.alert?.actions.first?.run()
        check(m.pomo.running && m.pomo.phase == .short, "start break from the alert")
        app.dismissAlert()
        app.prefs.v.pomoAutoStart = true
        m.check(now: Date().addingTimeInterval(400))
        check(m.pomo.phase == .focus && m.pomo.running, "auto-start runs the next focus")
        app.prefs.v.pomoAutoStart = false
        m.pomoReset()
        app.prefs.v.closedStyle = "none"
        check(m.liveDisplay() == nil, "plain style hides timers")
        app.prefs.v.closedStyle = "pomodoro"
        check(m.liveDisplay() != nil, "pinned pomodoro style shows even when idle")
        app.prefs.v.closedStyle = "auto"
        m.pomo = Pomodoro()
        check(m.liveDisplay() == nil, "idle pomodoro stays out of the closed notch in auto")
        app.dismissAlert()

        // Saved state survives a restart.
        let saved = JSONStore<TimersSave>("timers.json").load()
        check(saved?.pomo == m.pomo, "timers are saved")

        // The chime exists and decodes (it is never played here).
        let snd = Sound.url("timer-done").flatMap { NSSound(contentsOf: $0, byReference: true) }
        check((snd?.duration ?? 0) > 1, "chime loads")
        check(Sound.muted, "QA runs are muted")
    }

    static let scenes: [Render.Scene] = [
        Render.Scene(name: "closed-pomodoro", settle: 0.4) { app in
            app.timers.pomo = Pomodoro()
            app.timers.pomoToggle(now: Date().addingTimeInterval(-107))
        },
        Render.Scene(name: "open-timers-pomodoro", settle: 0.4) { app in
            app.notch.mode = .open
            app.notch.tab = .timers
            app.timers.mode = .pomodoro
            app.timers.pomo = Pomodoro(round: 2, doneToday: 3, day: TimersModel.dayKey(Date()))
            app.timers.pomoToggle(now: Date().addingTimeInterval(-107))
        },
        Render.Scene(name: "open-timers-break", settle: 0.4) { app in
            app.notch.mode = .open
            app.notch.tab = .timers
            app.timers.mode = .pomodoro
            app.timers.pomo = Pomodoro(phase: .short, remaining: 222, round: 2, doneToday: 4, day: TimersModel.dayKey(Date()))
        },
    ]
}
