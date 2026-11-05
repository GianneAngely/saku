import AppKit
import EventKit
import Observation
import SwiftUI

struct CalEvent: Identifiable, Equatable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var allDay = false
    var color: Color = Theme.blossom
    var location = ""
    var calendar = ""
    var joinURL: URL?
}

struct CalReminder: Identifiable, Equatable {
    var id: String
    var title: String
    var due: Date?
    var list = ""
    var color: Color = Theme.sky
    var done = false
}

struct CalList: Identifiable, Equatable {
    var id: String
    var title: String
    var color: Color
}

enum CalAccess: Equatable { case unknown, granted, denied }

/// Where events and reminders come from: EventKit, or a fixed demo set for QA.
@MainActor
protocol CalendarSource: AnyObject {
    var eventAccess: CalAccess { get }
    var reminderAccess: CalAccess { get }
    func requestEvents() async -> Bool
    func requestReminders() async -> Bool
    func calendars() -> [CalList]
    func reminderLists() -> [CalList]
    func events(from: Date, to: Date, calendars: [String]) -> [CalEvent]
    func reminders(lists: [String]) async -> [CalReminder]
    func setDone(_ id: String, _ done: Bool)
}

/// Finds a meeting link (Zoom, Meet, Teams, Webex, FaceTime) in an event.
enum MeetingLink {
    static let pattern = try! NSRegularExpression(pattern:
        #"https?://(?:[\w-]+\.)?(?:zoom\.us/(?:j|my|w)/[^\s<>"]+|meet\.google\.com/[a-z0-9-]+|teams\.microsoft\.com/l/meetup-join/[^\s<>"]+|teams\.live\.com/meet/[^\s<>"]+|[\w-]+\.webex\.com/[^\s<>"]+|facetime\.apple\.com/join[^\s<>"]*)"#,
        options: [.caseInsensitive])

    static func find(in texts: [String?]) -> URL? {
        for t in texts.compactMap({ $0 }) where !t.isEmpty {
            let r = NSRange(t.startIndex..., in: t)
            if let m = pattern.firstMatch(in: t, range: r), let range = Range(m.range, in: t) {
                return URL(string: String(t[range]).trimmingCharacters(in: CharacterSet(charactersIn: ">).,")))
            }
        }
        return nil
    }
}

@MainActor
final class EventKitSource: CalendarSource {
    private let store = EKEventStore()

    private func access(_ type: EKEntityType) -> CalAccess {
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess: .granted
        case .notDetermined: .unknown
        default: .denied
        }
    }

    var eventAccess: CalAccess { access(.event) }
    var reminderAccess: CalAccess { access(.reminder) }

    func requestEvents() async -> Bool { (try? await store.requestFullAccessToEvents()) ?? false }
    func requestReminders() async -> Bool { (try? await store.requestFullAccessToReminders()) ?? false }

    func calendars() -> [CalList] {
        guard eventAccess == .granted else { return [] }
        return store.calendars(for: .event).map { CalList(id: $0.calendarIdentifier, title: $0.title, color: Color(cgColor: $0.cgColor)) }
    }

    func reminderLists() -> [CalList] {
        guard reminderAccess == .granted else { return [] }
        return store.calendars(for: .reminder).map { CalList(id: $0.calendarIdentifier, title: $0.title, color: Color(cgColor: $0.cgColor)) }
    }

    func events(from: Date, to: Date, calendars ids: [String]) -> [CalEvent] {
        guard eventAccess == .granted else { return [] }
        let cals = ids.isEmpty ? nil : store.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) }
        if let cals, cals.isEmpty { return [] }
        let pred = store.predicateForEvents(withStart: from, end: to, calendars: cals)
        return store.events(matching: pred).map { e in
            CalEvent(id: e.calendarItemIdentifier + "@\(e.startDate.timeIntervalSince1970)", title: e.title ?? tr("Untitled"),
                     start: e.startDate, end: e.endDate, allDay: e.isAllDay, color: Color(cgColor: e.calendar.cgColor),
                     location: e.location ?? "", calendar: e.calendar.title,
                     joinURL: MeetingLink.find(in: [e.url?.absoluteString, e.location, e.notes]))
        }
        .sorted { $0.start < $1.start }
    }

    func reminders(lists ids: [String]) async -> [CalReminder] {
        guard reminderAccess == .granted else { return [] }
        let cals = ids.isEmpty ? nil : store.calendars(for: .reminder).filter { ids.contains($0.calendarIdentifier) }
        let pred = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: cals)
        let items: [CalReminder] = await withCheckedContinuation { c in
            store.fetchReminders(matching: pred) { rs in
                let mapped = (rs ?? []).map { r in
                    CalReminder(id: r.calendarItemIdentifier, title: r.title ?? "", due: r.dueDateComponents?.date,
                                list: r.calendar.title, color: Color(cgColor: r.calendar.cgColor), done: r.isCompleted)
                }
                c.resume(returning: mapped)
            }
        }
        return items.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    func setDone(_ id: String, _ done: Bool) {
        guard let r = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        r.isCompleted = done
        try? store.save(r, commit: true)
    }

    func observe(_ change: @escaping @MainActor () -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { change() }
        }
    }
}

/// Fixed events relative to "now" for renders and self tests. Never touches EventKit.
@MainActor
final class DemoCalendarSource: CalendarSource {
    var now: Date
    var reminderItems: [CalReminder]

    init(now: Date) {
        self.now = now
        reminderItems = [
            CalReminder(id: "r1", title: "Submit SIM Jam build", due: now.addingTimeInterval(3 * 3600), list: "Games", color: Theme.blossom),
            CalReminder(id: "r2", title: "Buy matcha", list: "Personal", color: Theme.mint),
            CalReminder(id: "r3", title: "Reply to itch.io comments", due: now.addingTimeInterval(26 * 3600), list: "Games", color: Theme.blossom),
        ]
    }

    var eventAccess = CalAccess.granted
    var reminderAccess = CalAccess.granted
    func requestEvents() async -> Bool { true }
    func requestReminders() async -> Bool { true }

    func calendars() -> [CalList] {
        [CalList(id: "work", title: "Work", color: Theme.sky), CalList(id: "home", title: "Personal", color: Theme.blossom)]
    }

    func reminderLists() -> [CalList] {
        [CalList(id: "games", title: "Games", color: Theme.blossom), CalList(id: "personal", title: "Personal", color: Theme.mint)]
    }

    func events(from: Date, to: Date, calendars: [String]) -> [CalEvent] {
        let cal = Calendar.current
        let day = cal.startOfDay(for: now)
        func at(_ dayOffset: Int, _ h: Int, _ m: Int) -> Date {
            cal.date(byAdding: .minute, value: dayOffset * 1440 + h * 60 + m, to: day)!
        }
        let all = [
            CalEvent(id: "e0", title: "Morning standup", start: at(0, 9, 0), end: at(0, 9, 15), color: Theme.sky, calendar: "Work"),
            CalEvent(id: "e1", title: "Design review: Saku", start: now.addingTimeInterval(8 * 60), end: now.addingTimeInterval(53 * 60),
                     color: Theme.sky, location: "Google Meet", calendar: "Work", joinURL: URL(string: "https://meet.google.com/abc-defg-hij")),
            CalEvent(id: "e2", title: "Gym with Rei", start: at(0, 18, 30), end: at(0, 19, 30), color: Theme.blossom, location: "Kuta", calendar: "Personal"),
            CalEvent(id: "e3", title: "SIM Jam results", start: at(6, 10, 0), end: at(6, 11, 0), color: Theme.blossom, calendar: "Personal"),
            CalEvent(id: "e4", title: "Thesis meeting", start: at(2, 13, 0), end: at(2, 14, 0), color: Theme.sky, calendar: "Work",
                     joinURL: URL(string: "https://us02web.zoom.us/j/123456789")),
            CalEvent(id: "e5", title: "Holiday", start: at(3, 0, 0), end: at(4, 0, 0), allDay: true, color: Theme.mint, calendar: "Personal"),
        ]
        return all.filter { $0.end > from && $0.start < to && (calendars.isEmpty || calendars.contains($0.calendar.lowercased() == "work" ? "work" : "home")) }
            .sorted { $0.start < $1.start }
    }

    func reminders(lists: [String]) async -> [CalReminder] { reminderItems.filter { !$0.done } }

    func setDone(_ id: String, _ done: Bool) {
        if let i = reminderItems.firstIndex(where: { $0.id == id }) { reminderItems[i].done = done }
    }
}

@MainActor @Observable
final class CalendarModel {
    var selectedDay = Calendar.current.startOfDay(for: Date())
    var month = Calendar.current.startOfDay(for: Date())
    var showReminders = false
    private(set) var dayEvents: [CalEvent] = []
    private(set) var todayEvents: [CalEvent] = []
    private(set) var upcoming: [CalEvent] = []          // today and tomorrow, for "next meeting"
    private(set) var monthDots: [Date: [Color]] = [:]
    private(set) var reminders: [CalReminder] = []
    private(set) var eventAccess = CalAccess.unknown
    private(set) var reminderAccess = CalAccess.unknown

    @ObservationIgnored let source: CalendarSource
    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private var token: NSObjectProtocol?

    init(app: AppModel, source: CalendarSource) {
        self.app = app
        self.source = source
        if let ek = source as? EventKitSource { token = ek.observe { [weak self] in self?.reload() } }
        reload()
    }

    var now: Date { (source as? DemoCalendarSource)?.now ?? Date() }

    func reload() {
        eventAccess = source.eventAccess
        reminderAccess = source.reminderAccess
        let cal = Calendar.current
        let ids = app.prefs.v.calendarIDs
        let today = cal.startOfDay(for: now)
        todayEvents = source.events(from: today, to: cal.date(byAdding: .day, value: 1, to: today)!, calendars: ids)
        upcoming = source.events(from: now.addingTimeInterval(-3600), to: cal.date(byAdding: .day, value: 2, to: today)!, calendars: ids)
        loadDay()
        loadMonth()
        if reminderAccess == .granted {
            Task { @MainActor in self.reminders = await self.source.reminders(lists: self.app.prefs.v.reminderListIDs) }
        }
    }

    func loadDay() {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 1, to: selectedDay)!
        var list = source.events(from: selectedDay, to: end, calendars: app.prefs.v.calendarIDs)
        if app.prefs.v.calendarHideEnded { list.removeAll { !$0.allDay && $0.end < now } }
        dayEvents = list
    }

    func loadMonth() {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: month) else { return }
        var dots: [Date: [Color]] = [:]
        for e in source.events(from: interval.start, to: interval.end, calendars: app.prefs.v.calendarIDs) {
            let d = cal.startOfDay(for: e.start)
            if (dots[d]?.count ?? 0) < 3 { dots[d, default: []].append(e.color) }
        }
        monthDots = dots
    }

    func select(_ day: Date) {
        selectedDay = Calendar.current.startOfDay(for: day)
        loadDay()
    }

    func shiftMonth(_ n: Int) {
        month = Calendar.current.date(byAdding: .month, value: n, to: month) ?? month
        loadMonth()
    }

    func requestAccess() {
        Task { @MainActor in
            _ = await source.requestEvents()
            reload()
        }
    }

    func requestReminderAccess() {
        Task { @MainActor in
            _ = await source.requestReminders()
            reload()
        }
    }

    func toggle(_ r: CalReminder) {
        source.setDone(r.id, !r.done)
        withAnimation(Theme.fade) { reminders.removeAll { $0.id == r.id } }
    }

    func open(_ e: CalEvent) {
        if let u = URL(string: "ical://") { NSWorkspace.shared.open(u) }
    }

    func join(_ e: CalEvent) {
        if let u = e.joinURL { NSWorkspace.shared.open(u) }
    }

    /// The meeting to mention in the closed notch: starting within `lead` minutes, or started less than 5 minutes ago.
    static func nextMeeting(_ events: [CalEvent], now: Date, lead: Double) -> CalEvent? {
        events.filter { !$0.allDay && $0.start.timeIntervalSince(now) <= lead * 60 && now.timeIntervalSince($0.start) <= 300 && $0.end > now }
            .min { $0.start < $1.start }
    }

    /// "in 8m", "in 1h 5m", "now".
    static func countdownText(to start: Date, now: Date) -> String {
        let m = Int(ceil(start.timeIntervalSince(now) / 60))
        if m <= 0 { return tr("now") }
        if m < 60 { return tr("in %dm", m) }
        return m % 60 == 0 ? tr("in %dh", m / 60) : tr("in %dh %dm", m / 60, m % 60)
    }

    /// Days shown in the month grid (whole weeks, starting on the locale's first weekday).
    static func gridDays(for month: Date, calendar cal: Calendar = .current) -> [Date] {
        guard let interval = cal.dateInterval(of: .month, for: month) else { return [] }
        let first = interval.start
        let lead = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        let start = cal.date(byAdding: .day, value: -lead, to: first)!
        let days = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        let cells = Int(ceil(Double(lead + days) / 7)) * 7
        return (0..<cells).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }
}
