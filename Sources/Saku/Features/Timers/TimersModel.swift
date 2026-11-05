import AppKit
import Observation
import SwiftUI

/// Pomodoro cycle: focus, short break, ... long break after N focus sessions.
struct Pomodoro: Codable, Equatable {
    enum Phase: String, Codable { case focus, short, long }

    var phase: Phase = .focus
    var endsAt: Date?
    var remaining: Double?          // set while paused; nil = not started (full length)
    var round = 1                   // which focus of the cycle (1...longEvery)
    var doneToday = 0
    var day = ""

    var running: Bool { endsAt != nil }
    var started: Bool { endsAt != nil || remaining != nil }

    func length(_ p: PrefsData) -> Double {
        switch phase {
        case .focus: p.pomoFocus * 60
        case .short: p.pomoShort * 60
        case .long: p.pomoLong * 60
        }
    }

    func left(at now: Date, _ p: PrefsData) -> Double {
        if let e = endsAt { return max(0, e.timeIntervalSince(now)) }
        return remaining ?? length(p)
    }

    mutating func start(at now: Date, _ p: PrefsData) {
        endsAt = now.addingTimeInterval(remaining ?? length(p))
        remaining = nil
    }

    mutating func pause(at now: Date, _ p: PrefsData) {
        remaining = left(at: now, p)
        endsAt = nil
    }

    mutating func reset() {
        endsAt = nil
        remaining = nil
    }

    /// Moves to the next phase. Only a finished (not skipped) focus counts towards today's total.
    mutating func advance(_ p: PrefsData, today: String, counted: Bool) {
        if day != today { day = today; doneToday = 0 }
        switch phase {
        case .focus:
            if counted { doneToday += 1 }
            phase = round >= max(1, p.pomoLongEvery) ? .long : .short
        case .short:
            round += 1
            phase = .focus
        case .long:
            round = 1
            phase = .focus
        }
        reset()
    }

    func today(_ key: String) -> Int { day == key ? doneToday : 0 }

    var title: String {
        switch phase {
        case .focus: tr("Focus")
        case .short: tr("Short break")
        case .long: tr("Long break")
        }
    }

    var icon: String { phase == .focus ? "flame.fill" : "cup.and.saucer.fill" }
    var tint: Color { phase == .focus ? Theme.butter : Theme.mint }
}

enum TimerMode: String, Codable, CaseIterable {
    case pomodoro, countdown, stopwatch

    var title: String {
        switch self {
        case .pomodoro: tr("Pomodoro")
        case .countdown: tr("Countdown")
        case .stopwatch: tr("Stopwatch")
        }
    }

    /// Modes whose feature has landed. Feature branches add themselves here.
    static let available: [TimerMode] = [.pomodoro]
}

/// Everything saved between launches, so a running timer survives a restart.
struct TimersSave: Codable {
    var pomo = Pomodoro()
    var mode = TimerMode.pomodoro
}

@MainActor @Observable
final class TimersModel {
    var pomo = Pomodoro() { didSet { changed() } }
    var mode = TimerMode.pomodoro { didSet { changed() } }
    /// Which timer was started last (decides what the closed notch shows when several are active).
    private(set) var lastStarted: TimerMode?

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let store = JSONStore<TimersSave>("timers.json")
    @ObservationIgnored private var fire: Timer?
    @ObservationIgnored private var loading = false
    /// Hooks other features attach to (focus Shortcuts).
    @ObservationIgnored var onPhaseStart: [@MainActor (Pomodoro.Phase) -> Void] = []
    @ObservationIgnored var onPhaseEnd: [@MainActor (Pomodoro.Phase) -> Void] = []

    init(app: AppModel) {
        self.app = app
        loading = true
        if let s = store.load() {
            pomo = s.pomo
            mode = TimerMode.available.contains(s.mode) ? s.mode : .pomodoro
        }
        loading = false
        check()
        schedule()
    }

    private var p: PrefsData { app.prefs.v }

    static func dayKey(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private func changed() {
        guard !loading else { return }
        save()
        schedule()
    }

    private func save() { store.save(TimersSave(pomo: pomo, mode: mode)) }

    // MARK: Pomodoro

    func pomoToggle(now: Date = Date()) {
        if pomo.running {
            pomo.pause(at: now, p)
        } else {
            let fresh = !pomo.started
            pomo.start(at: now, p)
            lastStarted = .pomodoro
            if fresh { onPhaseStart.forEach { $0(pomo.phase) } }
        }
    }

    func pomoReset() { pomo.reset() }

    func pomoSkip(now: Date = Date()) {
        let ended = pomo.phase
        pomo.advance(p, today: Self.dayKey(now), counted: false)
        onPhaseEnd.forEach { $0(ended) }
    }

    /// Completes anything that is due. Called by the fire timer, at launch and on wake.
    func check(now: Date = Date()) {
        if let e = pomo.endsAt, e <= now { finishPomodoro(now: now) }
    }

    private func finishPomodoro(now: Date) {
        let ended = pomo.phase
        pomo.advance(p, today: Self.dayKey(now), counted: true)
        onPhaseEnd.forEach { $0(ended) }
        let next = pomo
        if p.pomoAutoStart {
            pomo.start(at: now, p)
            lastStarted = .pomodoro
            onPhaseStart.forEach { $0(pomo.phase) }
        }
        ring()
        guard p.timerAlert else { return }
        let mins = Int((next.length(p) / 60).rounded())
        if ended == .focus {
            app.present(NotchAlert(
                title: tr("Focus done!"),
                subtitle: next.phase == .long ? tr("Great cycle. Take a %d-minute long break.", mins) : tr("Nice work. Take a %d-minute break.", mins),
                icon: "flame.fill", tint: Theme.butter,
                actions: p.pomoAutoStart ? [] : [
                    AlertAction(title: tr("Start break"), primary: true) { [weak self] in self?.pomoToggle() },
                    AlertAction(title: tr("Skip break")) { [weak self] in
                        self?.pomoSkip()
                        self?.pomoToggle()
                    },
                ],
                autoDismiss: p.pomoAutoStart ? 8 : 90))
        } else {
            app.present(NotchAlert(
                title: tr("Break's over"),
                subtitle: tr("Ready for focus %d of %d?", next.round, max(1, p.pomoLongEvery)),
                icon: "cup.and.saucer.fill", tint: Theme.mint,
                actions: p.pomoAutoStart ? [] : [AlertAction(title: tr("Start focus"), primary: true) { [weak self] in self?.pomoToggle() }],
                autoDismiss: p.pomoAutoStart ? 8 : 90))
        }
    }

    func ring() {
        if p.timerSound { Sound.play("timer-done", volume: p.timerVolume) }
    }

    // MARK: Firing

    /// Deadlines of everything that runs; feature branches extend this.
    private var deadlines: [Date] { [pomo.endsAt].compactMap { $0 } }

    /// One wall-clock timer for the earliest deadline. Nothing ticks while timers are idle.
    private func schedule() {
        fire?.invalidate()
        fire = nil
        guard let next = deadlines.min() else { return }
        let t = Timer(fire: next.addingTimeInterval(0.05), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.check()
                self?.schedule()
            }
        }
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        fire = t
    }

    // MARK: Closed notch

    func pomoDisplay(now: Date = Date()) -> TimerDisplay {
        TimerDisplay(icon: pomo.icon, tint: pomo.tint, countsUp: false, anchor: pomo.endsAt,
                     frozen: pomo.left(at: now, p), total: pomo.length(p))
    }

    /// A pinned timer style, or (auto) the most recently started active timer.
    func liveDisplay() -> TimerDisplay? {
        switch p.closedStyle {
        case "pomodoro": return pomoDisplay()
        case "auto": return pomo.started ? pomoDisplay() : nil
        default: return nil
        }
    }
}
