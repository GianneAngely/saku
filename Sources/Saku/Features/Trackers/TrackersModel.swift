import AppKit
import Observation
import SwiftUI

/// A day to count down to (or up from, once it passed). Yearly ones roll over to next year.
struct DaysLeft: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var date: Date
    var color = "#FF7EB6"
    var yearly = false

    /// Next occurrence for yearly items (birthdays), the date itself otherwise.
    func target(from today: Date, calendar cal: Calendar = .current) -> Date {
        let day = cal.startOfDay(for: date)
        guard yearly else { return day }
        var c = cal.dateComponents([.month, .day], from: day)
        c.year = cal.component(.year, from: today)
        let thisYear = cal.date(from: c).map { cal.startOfDay(for: $0) } ?? day
        if thisYear >= cal.startOfDay(for: today) { return thisYear }
        c.year! += 1
        return cal.date(from: c).map { cal.startOfDay(for: $0) } ?? day
    }

    /// Whole days from today: positive = left, 0 = today, negative = days since.
    func days(from today: Date, calendar cal: Calendar = .current) -> Int {
        cal.dateComponents([.day], from: cal.startOfDay(for: today), to: target(from: today, calendar: cal)).day ?? 0
    }
}

/// Tap-to-count tracker (push-ups, pages, glasses of tea). Can reset every day and have a goal.
struct Counter: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var value = 0
    var step = 1
    var goal = 0                    // 0 = no goal
    var daily = false
    var day = ""
    var color = "#FFD66B"
}

/// Today's water, in millilitres (shown in the unit from settings).
struct WaterDay: Codable, Equatable {
    var day = ""
    var ml = 0.0
    var drinks: [Date] = []
}

struct TrackersSave: Codable {
    var daysLeft: [DaysLeft] = []
    var counters: [Counter]? = nil
    var water: WaterDay? = nil
}

@MainActor @Observable
final class TrackersModel {
    private(set) var daysLeft: [DaysLeft] = []
    private(set) var counters: [Counter] = []
    private(set) var water = WaterDay()
    @ObservationIgnored private var waterTimer: Timer?

    @ObservationIgnored let app: AppModel
    @ObservationIgnored let store = JSONStore<TrackersSave>("trackers.json")
    @ObservationIgnored let saver = Debouncer(0.4)

    init(app: AppModel) {
        self.app = app
        load(store.load() ?? TrackersSave())
    }

    func load(_ s: TrackersSave) {
        daysLeft = s.daysLeft
        counters = s.counters ?? []
        water = s.water ?? WaterDay()
    }

    var snapshot: TrackersSave { TrackersSave(daysLeft: daysLeft, counters: counters, water: water) }

    func changed() { saver.run { [weak self] in self?.saveNow() } }
    func saveNow() { store.save(snapshot) }

    var today: Date { app.clock }

    // MARK: Days left

    /// Soonest first; days already passed go to the end.
    var sortedDays: [DaysLeft] {
        daysLeft.sorted { a, b in
            let da = a.days(from: today), db = b.days(from: today)
            if (da >= 0) != (db >= 0) { return da >= 0 }
            return da >= 0 ? da < db : da > db
        }
    }

    @discardableResult
    func addDay(title: String, date: Date, yearly: Bool = false, color: String = "#FF7EB6") -> DaysLeft {
        let d = DaysLeft(title: title.isEmpty ? tr("Untitled") : title, date: Calendar.current.startOfDay(for: date), color: color, yearly: yearly)
        daysLeft.append(d)
        changed()
        return d
    }

    func updateDay(_ d: DaysLeft) {
        guard let i = daysLeft.firstIndex(where: { $0.id == d.id }) else { return }
        daysLeft[i] = d
        changed()
    }

    func deleteDay(_ id: UUID) {
        daysLeft.removeAll { $0.id == id }
        changed()
    }

    // MARK: Counters

    /// Daily counters start from zero on a new day.
    func rollOver(now: Date = Date()) {
        let key = TimersModel.dayKey(now)
        var touched = false
        for i in counters.indices where counters[i].daily && counters[i].day != key {
            counters[i].value = 0
            counters[i].day = key
            touched = true
        }
        if touched { changed() }
    }

    @discardableResult
    func addCounter(title: String, goal: Int = 0, step: Int = 1, daily: Bool = false, color: String = "#FFD66B") -> Counter {
        let c = Counter(title: title.isEmpty ? tr("Counter") : title, step: max(1, step), goal: max(0, goal), daily: daily,
                        day: TimersModel.dayKey(Date()), color: color)
        counters.append(c)
        changed()
        return c
    }

    func bump(_ id: UUID, by sign: Int, now: Date = Date()) {
        rollOver(now: now)
        guard let i = counters.firstIndex(where: { $0.id == id }) else { return }
        counters[i].value = max(0, counters[i].value + sign * counters[i].step)
        counters[i].day = TimersModel.dayKey(now)
        if sign > 0, counters[i].goal > 0, counters[i].value == counters[i].goal {
            app.flash("checkmark.seal.fill", tr("%@ goal reached!", counters[i].title), tint: Theme.mint, seconds: 2.4)
        }
        changed()
    }

    func resetCounter(_ id: UUID) {
        guard let i = counters.firstIndex(where: { $0.id == id }) else { return }
        counters[i].value = 0
        changed()
    }

    func updateCounter(_ c: Counter) {
        guard let i = counters.firstIndex(where: { $0.id == c.id }) else { return }
        counters[i] = c
        changed()
    }

    func deleteCounter(_ id: UUID) {
        counters.removeAll { $0.id == id }
        changed()
    }

    // MARK: Water

    func waterToday(now: Date = Date()) -> WaterDay {
        water.day == TimersModel.dayKey(now) ? water : WaterDay(day: TimersModel.dayKey(now))
    }

    func drink(_ ml: Double? = nil, now: Date = Date()) {
        var w = waterToday(now: now)
        let before = w.ml
        w.ml += ml ?? app.prefs.v.waterSip
        w.drinks.append(now)
        water = w
        if before < app.prefs.v.waterGoal && w.ml >= app.prefs.v.waterGoal {
            app.flash("drop.fill", tr("Water goal reached!"), tint: Theme.sky, seconds: 2.4)
        }
        changed()
    }

    func undoDrink(now: Date = Date()) {
        var w = waterToday(now: now)
        guard !w.drinks.isEmpty else { return }
        w.drinks.removeLast()
        w.ml = max(0, w.ml - app.prefs.v.waterSip)
        water = w
        changed()
    }

    /// Reminds every N minutes between 9:00 and 21:00 while under the goal, if nothing was logged meanwhile.
    func scheduleWaterReminder() {
        waterTimer?.invalidate()
        waterTimer = nil
        let every = app.prefs.v.waterReminder
        guard every > 0 else { return }
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.checkWaterReminder() } }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .common)
        waterTimer = t
    }

    @ObservationIgnored private var lastNudge: Date?

    func checkWaterReminder(now: Date = Date()) {
        let every = app.prefs.v.waterReminder
        guard every > 0 else { return }
        let hour = Calendar.current.component(.hour, from: now)
        let w = waterToday(now: now)
        guard (9..<21).contains(hour), w.ml < app.prefs.v.waterGoal else { return }
        let last = max(w.drinks.last ?? .distantPast, lastNudge ?? .distantPast)
        guard now.timeIntervalSince(last) >= every * 60 else { return }
        lastNudge = now
        if app.prefs.v.timerSound { Sound.play("nudge", volume: app.prefs.v.timerVolume * 0.8) }
        app.present(NotchAlert(title: tr("Water break"), subtitle: tr("%@ of %@ so far today.", waterText(w.ml), waterText(app.prefs.v.waterGoal)),
                               icon: "drop.fill", tint: Theme.sky,
                               actions: [AlertAction(title: tr("I drank %@", waterText(app.prefs.v.waterSip)), primary: true) { [weak self] in self?.drink() },
                                         AlertAction(title: tr("Later"))],
                               autoDismiss: 45))
    }

    /// 250 ml, 8.5 oz or 1 cup, in the unit from settings.
    func waterText(_ ml: Double) -> String {
        switch app.prefs.v.waterUnit {
        case "oz": return String(format: "%.0f oz", ml / 29.5735)
        case "cups": let c = ml / 250; return c == c.rounded() ? tr("%d cups", Int(c)) : String(format: tr("%.1f cups"), c)
        default:
            guard ml >= 1000 else { return "\(Int(ml)) ml" }
            var s = String(format: "%.2f", ml / 1000)
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
            return s + " L"
        }
    }

    static func daysText(_ n: Int) -> String {
        switch n {
        case 0: tr("Today")
        case 1: tr("Tomorrow")
        case 2...: tr("%d days left", n)
        case -1: tr("Yesterday")
        default: tr("%d days ago", -n)
        }
    }
}
