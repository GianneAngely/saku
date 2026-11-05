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

struct TrackersSave: Codable {
    var daysLeft: [DaysLeft] = []
}

@MainActor @Observable
final class TrackersModel {
    private(set) var daysLeft: [DaysLeft] = []

    @ObservationIgnored let app: AppModel
    @ObservationIgnored let store = JSONStore<TrackersSave>("trackers.json")
    @ObservationIgnored let saver = Debouncer(0.4)

    init(app: AppModel) {
        self.app = app
        load(store.load() ?? TrackersSave())
    }

    func load(_ s: TrackersSave) {
        daysLeft = s.daysLeft
    }

    var snapshot: TrackersSave { TrackersSave(daysLeft: daysLeft) }

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
