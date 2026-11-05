import AppKit
import Observation
import SwiftUI

/// The 20-20-20 habit: every N minutes of screen time, look about 6 m (20 ft) away for 20 seconds.
/// Counts only time you are actually using the Mac; skips while reading the teleprompter or in a meeting.
@MainActor @Observable
final class EyeBreaks {
    private(set) var lastBreak = Date()
    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var activeSeconds = 0.0
    @ObservationIgnored private var lastTick = Date()

    init(app: AppModel) { self.app = app }

    func start() {
        timer?.invalidate()
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Seconds since the last key press or mouse move (no permission needed).
    nonisolated static var idleSeconds: Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    func tick(now: Date = Date(), idle: Double = EyeBreaks.idleSeconds) {
        let every = app.prefs.v.eyeBreakEvery
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        guard every > 0 else { activeSeconds = 0; return }
        if idle > 300 || dt > 150 {   // away for 5 minutes, or the Mac slept: that was a break
            activeSeconds = 0
            lastBreak = now
            return
        }
        activeSeconds += max(0, dt)
        guard activeSeconds >= every * 60, !busy(now) else { return }
        activeSeconds = 0
        lastBreak = now
        if app.prefs.v.timerSound { Sound.play("nudge", volume: app.prefs.v.timerVolume * 0.7) }
        app.present(NotchAlert(title: tr("Eye break"), subtitle: tr("Look at something far away for 20 seconds."),
                               icon: "eye.fill", tint: Theme.mint,
                               actions: [AlertAction(title: tr("Done"), primary: true), AlertAction(title: tr("Snooze 5 min")) { [weak self] in self?.snooze() }],
                               autoDismiss: 20))
    }

    /// No nudges while reading the teleprompter, during a meeting, or in focus mode when asked.
    func busy(_ now: Date) -> Bool {
        if app.prompter?.live == true { return true }
        if let cal = app.calendar, cal.upcoming.contains(where: { !$0.allDay && $0.start <= now && $0.end > now && $0.joinURL != nil }) { return true }
        if app.prefs.v.eyeBreakSkipFocus, app.timers?.pomo.running == true, app.timers?.pomo.phase == .focus { return true }
        return false
    }

    func snooze() {
        activeSeconds = max(0, app.prefs.v.eyeBreakEvery * 60 - 300)
    }
}

struct EyeBreakSection: View {
    let app: AppModel
    var body: some View {
        @Bindable var prefs = app.prefs
        Section {
            Picker(tr("Remind me"), selection: $prefs.v.eyeBreakEvery) {
                Text(tr("Never")).tag(0.0)
                ForEach([20.0, 30, 45, 60], id: \.self) { Text(tr("Every %d min of screen time", Int($0))).tag($0) }
            }
            Toggle(tr("Not during Pomodoro focus"), isOn: $prefs.v.eyeBreakSkipFocus)
        } header: {
            Text(tr("Eye breaks"))
        } footer: {
            Text(tr("The 20-20-20 rule: every 20 minutes, look 20 feet (6 m) away for 20 seconds. Time away from the Mac counts as a break, and meetings are never interrupted."))
        }
    }
}
