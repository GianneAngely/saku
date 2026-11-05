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

        googleChecks(app)
    }

    /// Google Calendar through Internet Accounts, writing events, reminders saved as events. Demo source only.
    static func googleChecks(_ app: AppModel) {
        func check(_ ok: Bool, _ name: String) { SelfTest.check(ok, name) }
        let m = app.calendar!
        guard let demo = m.source as? DemoCalendarSource else { return check(false, "demo calendar in tests") }

        // Spotting Google accounts among EventKit sources.
        check(GoogleCalendar.isGoogle(caldav: true, account: "name@gmail.com", calendarTitles: []), "Gmail account is Google")
        check(GoogleCalendar.isGoogle(caldav: true, account: "Google", calendarTitles: ["Work"]), "account named Google")
        check(GoogleCalendar.isGoogle(caldav: true, account: "Studio", calendarTitles: ["me@googlemail.com"]), "Google calendar title")
        check(!GoogleCalendar.isGoogle(caldav: true, account: "iCloud", calendarTitles: ["Home"]), "iCloud is not Google")
        check(!GoogleCalendar.isGoogle(caldav: false, account: "Google", calendarTitles: []), "only CalDAV accounts count")
        check(NSWorkspace.shared.urlForApplication(toOpen: GoogleCalendar.settingsURL) != nil, "Internet Accounts link opens System Settings")

        // Accounts and calendars.
        demo.clearSaved()
        m.reload()
        check(m.accounts.first == "name@gmail.com" && m.googleAccounts == ["name@gmail.com"], "Google account listed first")
        check(m.writableCalendars.contains { $0.id == "google" } && !m.writableCalendars.contains { $0.id == "google-holidays" },
              "read-only calendars can't take new events")
        demo.hasGoogle = false
        m.reload()
        check(m.googleAccounts.isEmpty, "no Google account until one is added")
        demo.hasGoogle = true
        m.reload()

        // Typing the time into the title.
        let lunch = QuickEvent.parse("Lunch with Rei tomorrow at 12:30")
        let tmr = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        if let d = lunch.date {
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            check(lunch.title == "Lunch with Rei" && Calendar.current.isDate(d, inSameDayAs: tmr) && c.hour == 12 && c.minute == 30 && !lunch.allDay,
                  "title with a time: \(lunch.title)")
        } else { check(false, "title with a time is read") }
        let plain = QuickEvent.parse("Call the bank")
        check(plain.date == nil && plain.title == "Call the bank", "title without a time stays as it is")
        let dayOnly = QuickEvent.parse("Pay rent on Friday")
        check(dayOnly.date != nil && dayOnly.allDay && dayOnly.title == "Pay rent", "a day without a time is all day")

        // New event into the Google calendar, with an alert.
        app.prefs.v.newEventCalendarID = "google"
        app.prefs.v.newEventAlert = 10
        m.select(demo.now)
        m.startCompose(.event)
        check(m.targetCalendarID == "google", "new events go to the picked calendar")
        m.draftTitle = "Thesis writing"
        m.draftMinutes = 20 * 60
        m.draftLength = 90
        check(m.saveCompose() && m.composing == nil, "event saved and composer closed")
        let saved = demo.saved.last
        let startC = saved.map { Calendar.current.dateComponents([.hour, .minute], from: $0.event.start) }
        check(saved?.event.calendarID == "google" && saved?.alert == 10 && startC?.hour == 20 && saved.map { $0.event.end.timeIntervalSince($0.event.start) } == 5400,
              "event lands in Google at 20:00 for 90 min with a 10 min alert")
        check(m.dayEvents.contains { $0.title == "Thesis writing" }, "the new event shows in the day list")
        m.startCompose(.event)
        m.draftCalendarID = "google-holidays"
        check(m.targetCalendarID == "google", "a read-only pick falls back to a writable calendar")
        m.draftTitle = "   "
        check(!m.saveCompose(), "an empty title saves nothing")
        m.cancelCompose()

        // Reminders as events with an alert in the Google calendar.
        app.prefs.v.reminderTarget = "calendar"
        app.prefs.v.reminderCalendarID = "google"
        app.prefs.v.reminderAlert = 5
        m.reload()
        check(m.remindersAsEvents && m.remindersAvailable, "reminders go to the calendar")
        m.startCompose(.reminder)
        m.draftTitle = "Water the plants"
        m.draftMinutes = 18 * 60
        check(m.saveCompose(), "reminder saved")
        let rem = demo.saved.last
        check(rem?.event.calendarID == "google" && (rem?.notes ?? "").contains(ReminderEvents.marker) && rem?.alert == 5
              && rem.map { $0.event.end.timeIntervalSince($0.event.start) } == ReminderEvents.length,
              "reminder becomes a 15-minute Google event with a 5 min alert")
        check(m.reminders.contains { $0.title == "Water the plants" && $0.kind == .event }, "reminder event shows with the reminders")
        if let r = m.reminders.first(where: { $0.title == "Water the plants" }) {
            m.toggle(r)
            let done = demo.savedItem(r.id)
            check(done?.event.title == ReminderEvents.donePrefix + "Water the plants" && done?.alert == nil, "ticking it adds ✓ and drops the alert")
            m.reload()
            check(!m.reminders.contains { $0.id == r.id }, "ticked reminder leaves the list")
            demo.setEventDone(r.id, false, alert: 5)
            check(demo.savedItem(r.id)?.event.title == "Water the plants" && demo.savedItem(r.id)?.alert == 5, "unticking restores title and alert")
        } else { check(false, "reminder event found") }

        // Back to Apple Reminders.
        app.prefs.v.reminderTarget = "reminders"
        m.reload()
        let count = demo.reminderItems.count
        m.startCompose(.reminder)
        m.draftTitle = "Buy stamps"
        m.draftTimed = false
        check(m.saveCompose() && demo.reminderItems.count == count + 1 && demo.reminderItems.last?.due == nil, "untimed reminder goes to Apple Reminders")
        app.prefs.v.newEventCalendarID = ""
        app.prefs.v.reminderCalendarID = ""
        demo.clearSaved()
        m.reload()
        app.notch.hud = nil
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
        Render.Scene(name: "open-calendar-new-event", settle: 0.5) { app in
            app.prefs.v.newEventCalendarID = "google"
            app.calendar.select(Render.fixedDate)
            app.calendar.startCompose(.event)
            app.calendar.draftTitle = "Lunch with Rei"
            app.calendar.draftMinutes = 12 * 60 + 30
            app.notch.mode = .open
            app.notch.tab = .calendar
        },
        Render.Scene(name: "open-calendar-google-reminders", settle: 0.6) { app in
            app.prefs.v.reminderTarget = "calendar"
            app.prefs.v.reminderCalendarID = "google"
            app.prefs.v.reminderAlert = 10
            app.calendar.select(Render.fixedDate)
            app.calendar.startCompose(.reminder)
            app.calendar.draftTitle = "Send the thesis draft"
            app.calendar.draftMinutes = 19 * 60
            _ = app.calendar.saveCompose()
            app.calendar.showReminders = true
            app.notch.mode = .open
            app.notch.tab = .calendar
        },
        Render.Scene(name: "open-calendar-connect", settle: 0.5) { app in
            (app.calendar.source as? DemoCalendarSource)?.hasGoogle = false
            app.calendar.reload()
            app.calendar.showReminders = false
            app.calendar.select(Render.fixedDate)
            app.notch.mode = .open
            app.notch.tab = .calendar
        },
        Render.Scene(name: "closed-meeting", settle: 0.4) { app in
            app.prefs.v.meetingHeadsUp = true
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
