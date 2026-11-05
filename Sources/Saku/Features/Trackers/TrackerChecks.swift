import AppKit
import SwiftUI

@MainActor
enum TrackerChecks {
    static func run(_ app: AppModel) {
        func check(_ ok: Bool, _ name: String) { SelfTest.check(ok, name) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let today = cal.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 15))!
        func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }

        check(DaysLeft(title: "Jam", date: day(2026, 11, 11)).days(from: today, calendar: cal) == 6, "days left")
        check(DaysLeft(title: "Now", date: day(2026, 11, 5)).days(from: today, calendar: cal) == 0, "today is zero")
        check(DaysLeft(title: "Past", date: day(2026, 10, 30)).days(from: today, calendar: cal) == -6, "days since")
        let bday = DaysLeft(title: "Birthday", date: day(2004, 3, 14), yearly: true)
        check(bday.target(from: today, calendar: cal) == day(2027, 3, 14) && bday.days(from: today, calendar: cal) == 129, "yearly rolls to next year")
        check(DaysLeft(title: "Soon", date: day(1999, 11, 20), yearly: true).days(from: today, calendar: cal) == 15, "yearly later this year")
        check(TrackersModel.daysText(1) == tr("Tomorrow") && TrackersModel.daysText(-3) == tr("%d days ago", 3), "day texts")

        let m = app.trackers!
        for d in m.daysLeft { m.deleteDay(d.id) }
        let now = app.clock
        m.addDay(title: "Past", date: now.addingTimeInterval(-3 * 86400))
        m.addDay(title: "Far", date: now.addingTimeInterval(40 * 86400))
        m.addDay(title: "Near", date: now.addingTimeInterval(2 * 86400))
        check(m.sortedDays.map(\.title) == ["Near", "Far", "Past"], "soonest first, past at the end")
        // Counters.
        for c in m.counters { m.deleteCounter(c.id) }
        let c = m.addCounter(title: "Push-ups", goal: 3, daily: true)
        m.bump(c.id, by: 1)
        m.bump(c.id, by: 1)
        m.bump(c.id, by: -1)
        m.bump(c.id, by: 1)
        m.bump(c.id, by: 1)
        check(m.counters[0].value == 3, "counter counts up and down")
        check(app.notch.hud?.text == tr("%@ goal reached!", "Push-ups"), "goal reached flash")
        app.notch.hud = nil
        for _ in 0..<5 { m.bump(c.id, by: -1) }
        check(m.counters[0].value == 0, "counter never goes below zero")
        m.bump(c.id, by: 1)
        m.rollOver(now: Date().addingTimeInterval(86400))
        check(m.counters[0].value == 0, "daily counters reset on a new day")
        let w = m.addCounter(title: "Pages", step: 5)
        m.bump(w.id, by: 1)
        m.rollOver(now: Date().addingTimeInterval(86400 * 2))
        check(m.counters.first { $0.id == w.id }?.value == 5, "step size, and non-daily counters keep their value")

        // Water.
        app.prefs.v.waterGoal = 2000
        app.prefs.v.waterSip = 250
        app.prefs.v.waterUnit = "ml"
        let start = Date()
        check(m.waterToday(now: start).ml >= 0, "water day")
        let base = m.waterToday(now: start).ml
        for _ in 0..<3 { m.drink(now: start) }
        check(m.waterToday(now: start).ml == base + 750, "drinks add up")
        m.undoDrink(now: start)
        check(m.waterToday(now: start).ml == base + 500, "undo a drink")
        check(m.waterToday(now: start.addingTimeInterval(86400)).ml == 0, "a new day starts at zero")
        check(m.waterText(250) == "250 ml" && m.waterText(1500) == "1.5 L" && m.waterText(2000) == "2 L" && m.waterText(1250) == "1.25 L", "millilitres")
        app.prefs.v.waterUnit = "oz"
        check(m.waterText(250) == "8 oz", "ounces")
        app.prefs.v.waterUnit = "cups"
        check(m.waterText(500) == tr("%d cups", 2), "cups")
        app.prefs.v.waterUnit = "ml"
        var c9 = DateComponents()
        (c9.year, c9.month, c9.day, c9.hour, c9.minute) = (2030, 1, 7, 10, 0)
        let ten = Calendar.current.date(from: c9)!
        app.prefs.v.waterReminder = 60
        app.dismissAlert()
        m.checkWaterReminder(now: ten)
        check(app.notch.alert?.title == tr("Water break"), "water reminder during the day")
        app.notch.alert?.actions.first?.run()
        check(m.waterToday(now: Date()).ml > 0, "logging from the reminder")
        app.dismissAlert()
        m.checkWaterReminder(now: ten.addingTimeInterval(600))
        check(app.notch.alert == nil, "no second reminder within the interval")
        c9.hour = 23
        m.checkWaterReminder(now: Calendar.current.date(from: c9)!)
        check(app.notch.alert == nil, "no reminders at night")
        app.prefs.v.waterReminder = 0

        m.saveNow()
        let saved = JSONStore<TrackersSave>("trackers.json").load()
        check(saved?.daysLeft.count == 3 && saved?.counters?.count == 2, "trackers are saved")
    }

    static let scenes: [Render.Scene] = [
        Render.Scene(name: "open-trackers", settle: 0.5) { app in
            fill(app)
            app.notch.mode = .open
            app.notch.tab = .trackers
        },
    ]

    static func fill(_ app: AppModel) {
        let m = app.trackers!
        for d in m.daysLeft { m.deleteDay(d.id) }
        let cal = Calendar.current
        let now = app.clock
        m.addDay(title: "SIM Jam results", date: cal.date(byAdding: .day, value: 6, to: now)!, color: "#C7A6FF")
        m.addDay(title: "Bali trip", date: cal.date(byAdding: .day, value: 23, to: now)!, color: "#8CC8FF")
        m.addDay(title: "Grandma's birthday", date: cal.date(byAdding: .day, value: 79, to: now)!, yearly: true)
        m.addDay(title: "Started Saku", date: cal.date(byAdding: .day, value: -2, to: now)!, color: "#FFD66B")
        for c in m.counters { m.deleteCounter(c.id) }
        let a = m.addCounter(title: "Push-ups", goal: 30, step: 5, daily: true)
        for _ in 0..<4 { m.bump(a.id, by: 1) }
        let b = m.addCounter(title: "Pages read", goal: 50, daily: true, color: "#8CC8FF")
        for _ in 0..<12 { m.bump(b.id, by: 1) }
        let d = m.addCounter(title: "Game jam builds", color: "#C7A6FF")
        for _ in 0..<7 { m.bump(d.id, by: 1) }
        for _ in 0..<5 { m.drink() }
        app.notch.hud = nil
    }
}
