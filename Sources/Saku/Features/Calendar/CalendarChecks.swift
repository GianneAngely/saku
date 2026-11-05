import AppKit
import SwiftUI

@MainActor
enum CalendarChecks {
    static func run(_ app: AppModel) {
        func check(_ ok: Bool, _ name: String) { SelfTest.check(ok, name) }

        // Meeting links.
        check(MeetingLink.find(in: ["Join: https://meet.google.com/abc-defg-hij please"])?.absoluteString == "https://meet.google.com/abc-defg-hij", "Google Meet link")
        check(MeetingLink.find(in: [nil, "https://us02web.zoom.us/j/8812345678?pwd=xyz."])?.host() == "us02web.zoom.us", "Zoom link (trailing dot trimmed)")
        check(MeetingLink.find(in: ["https://teams.microsoft.com/l/meetup-join/19%3ameeting_x"]) != nil, "Teams link")
        check(MeetingLink.find(in: ["Room 4B", "https://example.com"]) == nil, "ordinary links are not meetings")

        // Next meeting and countdown text.
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let soon = CalEvent(id: "a", title: "Soon", start: now.addingTimeInterval(7 * 60), end: now.addingTimeInterval(40 * 60))
        let later = CalEvent(id: "b", title: "Later", start: now.addingTimeInterval(3 * 3600), end: now.addingTimeInterval(4 * 3600))
        let allDay = CalEvent(id: "c", title: "Holiday", start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(20 * 3600), allDay: true)
        let started = CalEvent(id: "d", title: "Started", start: now.addingTimeInterval(-120), end: now.addingTimeInterval(1800))
        check(CalendarModel.nextMeeting([later, soon, allDay], now: now, lead: 10)?.id == "a", "next meeting within the lead time")
        check(CalendarModel.nextMeeting([later], now: now, lead: 10) == nil, "nothing when the next meeting is far away")
        check(CalendarModel.nextMeeting([started, soon], now: now, lead: 10)?.id == "d", "a meeting that just started still shows")
        check(CalendarModel.nextMeeting([allDay], now: now, lead: 10) == nil, "all-day events are not meetings")
        check(CalendarModel.countdownText(to: now.addingTimeInterval(7 * 60 + 10), now: now) == tr("in %dm", 8), "countdown rounds up")
        check(CalendarModel.countdownText(to: now.addingTimeInterval(-30), now: now) == tr("now"), "countdown now")
        check(CalendarModel.countdownText(to: now.addingTimeInterval(65 * 60), now: now) == tr("in %dh %dm", 1, 5), "countdown hours")

        // Month grid.
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        let nov = c.date(from: DateComponents(year: 2026, month: 11, day: 15))!
        let grid = CalendarModel.gridDays(for: nov, calendar: c)
        check(grid.count % 7 == 0 && c.component(.weekday, from: grid[0]) == 2, "grid is whole weeks starting Monday")
        check(grid.contains { c.component(.day, from: $0) == 1 && c.component(.month, from: $0) == 11 } &&
              grid.contains { c.component(.day, from: $0) == 30 && c.component(.month, from: $0) == 11 }, "grid covers the month")

        // Demo source through the model.
        let m = app.calendar!
        m.reload()
        check(m.eventAccess == .granted && !m.todayEvents.isEmpty, "today's events load")
        app.prefs.v.closedStyle = "auto"
        app.prefs.v.musicLiveActivity = false
        app.timers.pomo = Pomodoro()
        app.timers.countdown = Countdown()
        app.timers.stopwatch = Stopwatch()
        if case .meeting(let text) = app.liveActivity {
            check(text == tr("in %dm", 8), "meeting heads-up in the closed notch")
        } else { check(false, "meeting heads-up shows") }
        app.prefs.v.meetingHeadsUp = false
        check(app.liveActivity == .none, "meeting heads-up can be turned off")
        app.prefs.v.meetingHeadsUp = true
        app.prefs.v.musicLiveActivity = true
        check(m.upcoming.contains { $0.joinURL != nil }, "join links come through")
        let before = m.reminders.count
        if let r = m.reminders.first {
            m.toggle(r)
            check(m.reminders.count == before - 1, "ticking a reminder removes it")
        }
        m.shiftMonth(1)
        m.shiftMonth(-1)
        check(Calendar.current.isDate(m.month, equalTo: Date(), toGranularity: .month), "month navigation")
    }

    static let scenes: [Render.Scene] = [
        Render.Scene(name: "open-calendar", settle: 0.5) { app in
            app.calendar.select(Date())
            app.calendar.showReminders = false
            app.notch.mode = .open
            app.notch.tab = .calendar
        },
        Render.Scene(name: "open-calendar-reminders", settle: 0.6) { app in
            app.calendar.reload()
            app.calendar.showReminders = true
            app.notch.mode = .open
            app.notch.tab = .calendar
        },
        Render.Scene(name: "closed-meeting", settle: 0.4) { app in
            app.prefs.v.musicLiveActivity = false
            app.calendar.reload()
        },
        Render.Scene(name: "open-calendar-access", settle: 0.4) { app in
            (app.calendar.source as? DemoCalendarSource)?.eventAccess = .unknown
            app.calendar.reload()
            app.notch.mode = .open
            app.notch.tab = .calendar
        },
        Render.Scene(name: "open-home-full", settle: 0.6) { app in
            app.prefs.v.weatherCity = City(name: "Denpasar", region: "Bali, Indonesia", latitude: -8.65, longitude: 115.22)
            app.weather.setDemo(WeatherNow(temp: 29, feels: 33, code: 2, isDay: true, high: 31, low: 25, fetched: Date()))
            (app.calendar.source as? DemoCalendarSource)?.eventAccess = .granted
            app.calendar.reload()
            app.notch.mode = .open
            app.notch.tab = .home
        },
    ]
}
