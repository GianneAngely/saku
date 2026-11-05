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

struct TrackersSave: Codable {
    var daysLeft: [DaysLeft] = []
    var counters: [Counter]? = nil
}

@MainActor @Observable
final class TrackersModel {
    private(set) var daysLeft: [DaysLeft] = []
    private(set) var counters: [Counter] = []

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
    }

    var snapshot: TrackersSave { TrackersSave(daysLeft: daysLeft, counters: counters) }

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
