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
    var calendarID = ""
}

struct CalReminder: Identifiable, Equatable {
    enum Kind: Equatable { case reminder, event }
    var id: String
    var title: String
    var due: Date?
    var list = ""
    var color: Color = Theme.sky
    var done = false
    /// `.event`: a reminder Saku saved as a calendar event with an alert (for Google Calendar).
    var kind = Kind.reminder
}

struct CalList: Identifiable, Equatable {
    var id: String
    var title: String
    var color: Color
    /// The account it belongs to, as Calendar.app names it ("iCloud", "name@gmail.com", "On My Mac").
    var account = ""
    var google = false
    var writable = true
    var kind = CalSourceKind.other
}

/// A new event from the composer.
struct EventDraft: Equatable {
    var title: String
    var start: Date
    var end: Date
    var allDay = false
    var calendarID = ""
    /// Minutes before the start; nil = no alert.
    var alert: Double?
    var notes: String?
}

/// Google Calendar comes in through macOS Internet Accounts: Angel signs in there herself, Saku only reads and
/// writes through EventKit. No OAuth client, no API key, no account picked for her.
enum GoogleCalendar {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!

    /// Google accounts show up in EventKit as CalDAV sources; their name is the address or "Google".
    static func isGoogle(caldav: Bool, account: String, calendarTitles: [String]) -> Bool {
        guard caldav else { return false }
        let hints = ["google", "gmail.com", "googlemail.com"]
        return ([account] + calendarTitles).contains { t in hints.contains { t.lowercased().contains($0) } }
    }

    static let privacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!

    /// Opens a System Settings pane. Self tests swap this out so nothing opens on the real screen.
    @MainActor static var open: (URL) -> Void = { url in
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }

    @MainActor static func openInternetAccounts() { open(settingsURL) }
    @MainActor static func openPrivacy() { open(privacyURL) }
}

/// Reminders saved as calendar events carry this line in their notes, and get a tick in the title once done.
enum ReminderEvents {
    static let marker = "Reminder from Saku"
    static let donePrefix = "✓ "
    static let length: TimeInterval = 15 * 60

    static func mark(title: inout String?, done: Bool) {
        let t = title ?? ""
        if done {
            if !t.hasPrefix(donePrefix) { title = donePrefix + t }
        } else if t.hasPrefix(donePrefix) {
            title = String(t.dropFirst(donePrefix.count))
        }
    }
}

/// "Lunch with Rei tomorrow 12:30" → title "Lunch with Rei", the date it names (NSDataDetector, English dates).
enum QuickEvent {
    struct Parsed: Equatable {
        var title: String
        var date: Date?
        var duration: TimeInterval?
        var allDay = false
    }

    static func parse(_ text: String) -> Parsed {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let m = det.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let date = m.date, let r = Range(m.range, in: trimmed) else { return Parsed(title: trimmed) }
        var title = trimmed
        title.removeSubrange(r)
        title = title.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: CharacterSet.whitespaces.union(.punctuationCharacters))
        // "Pay rent on" → "Pay rent": drop the little word that led into the date.
        let joiners = ["on", "at", "by", "for", "from", "in", "di", "pada", "jam", "tanggal", "tgl"]
        while let last = title.split(separator: " ").last, joiners.contains(last.lowercased()), title.contains(" ") {
            title = String(title.dropLast(last.count)).trimmingCharacters(in: .whitespaces)
        }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let named = String(trimmed[r]).lowercased()
        let hasTime = named.contains(":") || named.contains("am") || named.contains("pm") || named.contains("noon")
            || (comps.hour != 12 || comps.minute != 0)
        return Parsed(title: title.isEmpty ? trimmed : title, date: date, duration: m.duration > 0 ? m.duration : nil, allDay: !hasTime)
    }
}

/// Calendar permission as Saku sees it. `addOnly` is macOS's "add events only" level, which can't read anything.
enum CalAccess: Equatable { case unknown, granted, denied, addOnly }

/// What kind of account a calendar comes from, for the status in Settings.
enum CalSourceKind: Equatable { case google, icloud, local, exchange, subscribed, birthdays, other }

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
    func defaultCalendarID() -> String?
    func defaultReminderListID() -> String?
    /// Saves a new event; returns its id, or nil when the calendar refused it.
    func addEvent(_ draft: EventDraft) -> String?
    func addReminder(title: String, due: Date?, listID: String?) -> Bool
    /// Open reminders Saku saved as events in one calendar.
    func reminderEvents(calendarID: String, from: Date, to: Date) -> [CalReminder]
    func setEventDone(_ id: String, _ done: Bool, alert: Double?)
    /// Asks macOS to pull new accounts and calendars (a Google account added in System Settings).
    func refresh()
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
    private var store = EKEventStore()

    private func access(_ type: EKEntityType) -> CalAccess {
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess: .granted
        case .notDetermined: .unknown
        case .writeOnly: .addOnly
        default: .denied
        }
    }

    /// A store made before access was granted can keep returning no calendars, so start a fresh one after the OK.
    private func renew() { store = EKEventStore() }

    func refresh() {
        guard eventAccess == .granted else { return }
        if store.sources.isEmpty { renew() }
        store.refreshSourcesIfNecessary()
    }

    var eventAccess: CalAccess { access(.event) }
    var reminderAccess: CalAccess { access(.reminder) }

    func requestEvents() async -> Bool {
        let ok = (try? await store.requestFullAccessToEvents()) ?? false
        if ok { renew() }
        return ok
    }

    func requestReminders() async -> Bool {
        let ok = (try? await store.requestFullAccessToReminders()) ?? false
        if ok { renew() }
        return ok
    }

    func calendars() -> [CalList] {
        guard eventAccess == .granted else { return [] }
        let all = store.calendars(for: .event)
        return all.map { c in
            let titles = all.filter { $0.source == c.source }.map(\.title)
            let google = GoogleCalendar.isGoogle(caldav: c.source.sourceType == .calDAV, account: c.source.title, calendarTitles: titles)
            return CalList(id: c.calendarIdentifier, title: c.title, color: Color(cgColor: c.cgColor), account: c.source.title,
                           google: google, writable: c.allowsContentModifications, kind: Self.kind(c, google: google))
        }
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
                     joinURL: MeetingLink.find(in: [e.url?.absoluteString, e.location, e.notes]), calendarID: e.calendar.calendarIdentifier)
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

    func defaultCalendarID() -> String? { eventAccess == .granted ? store.defaultCalendarForNewEvents?.calendarIdentifier : nil }
    func defaultReminderListID() -> String? { reminderAccess == .granted ? store.defaultCalendarForNewReminders()?.calendarIdentifier : nil }

    func addEvent(_ d: EventDraft) -> String? {
        guard eventAccess == .granted else { return nil }
        let e = EKEvent(eventStore: store)
        e.title = d.title
        e.startDate = d.start
        e.endDate = d.end
        e.isAllDay = d.allDay
        e.notes = d.notes
        guard let cal = store.calendar(withIdentifier: d.calendarID) ?? store.defaultCalendarForNewEvents, cal.allowsContentModifications else { return nil }
        e.calendar = cal
        if let a = d.alert { e.addAlarm(EKAlarm(relativeOffset: -a * 60)) }
        do { try store.save(e, span: .thisEvent, commit: true) } catch { return nil }
        return e.eventIdentifier
    }

    func addReminder(title: String, due: Date?, listID: String?) -> Bool {
        guard reminderAccess == .granted else { return false }
        let r = EKReminder(eventStore: store)
        r.title = title
        guard let list = listID.flatMap({ store.calendar(withIdentifier: $0) }) ?? store.defaultCalendarForNewReminders() else { return false }
        r.calendar = list
        if let due {
            r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            r.addAlarm(EKAlarm(absoluteDate: due))
        }
        return (try? store.save(r, commit: true)) != nil
    }

    func reminderEvents(calendarID: String, from: Date, to: Date) -> [CalReminder] {
        guard eventAccess == .granted, let cal = store.calendar(withIdentifier: calendarID) else { return [] }
        let pred = store.predicateForEvents(withStart: from, end: to, calendars: [cal])
        return store.events(matching: pred)
            .filter { ($0.notes ?? "").contains(ReminderEvents.marker) && !($0.title ?? "").hasPrefix(ReminderEvents.donePrefix) }
            .map { CalReminder(id: $0.eventIdentifier, title: $0.title ?? "", due: $0.startDate, list: cal.title,
                               color: Color(cgColor: cal.cgColor), kind: .event) }
    }

    func setEventDone(_ id: String, _ done: Bool, alert: Double?) {
        guard let e = store.event(withIdentifier: id) else { return }
        ReminderEvents.mark(title: &e.title, done: done)
        if done {
            for a in e.alarms ?? [] { e.removeAlarm(a) }
        } else if (e.alarms ?? []).isEmpty, let alert {
            e.addAlarm(EKAlarm(relativeOffset: -alert * 60))
        }
        try? store.save(e, span: .thisEvent, commit: true)
    }

    static func kind(_ c: EKCalendar, google: Bool) -> CalSourceKind {
        if google { return .google }
        switch c.type {
        case .subscription: return .subscribed
        case .birthday: return .birthdays
        case .exchange: return .exchange
        case .local: return .local
        default: break
        }
        if c.source.sourceType == .local { return .local }
        return c.source.title.lowercased().contains("icloud") ? .icloud : .other
    }

    /// Any store's change counts: the store is replaced after access is granted.
    func observe(_ change: @escaping @MainActor () -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { change() }
        }
    }
}

/// Fixed events relative to "now" for renders and self tests. Never touches EventKit.
/// Has a made-up Google account (name@gmail.com) next to iCloud, like a Mac with Google added in Internet Accounts.
@MainActor
final class DemoCalendarSource: CalendarSource {
    struct Saved {
        var event: CalEvent
        var notes: String?
        var alert: Double?
    }

    var now: Date
    var reminderItems: [CalReminder]
    private(set) var saved: [Saved] = []
    /// False shows a Mac without a Google account.
    var hasGoogle = true

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
    /// What the fake permission prompt answers.
    var promptAnswer = true
    private(set) var refreshes = 0

    func requestEvents() async -> Bool {
        if eventAccess == .unknown { eventAccess = promptAnswer ? .granted : .denied }
        return eventAccess == .granted
    }

    func requestReminders() async -> Bool {
        if reminderAccess == .unknown { reminderAccess = promptAnswer ? .granted : .denied }
        return reminderAccess == .granted
    }

    func refresh() { refreshes += 1 }

    func calendars() -> [CalList] {
        guard eventAccess == .granted else { return [] }
        var list = [CalList(id: "work", title: "Work", color: Theme.sky, account: "iCloud", kind: .icloud),
                    CalList(id: "home", title: "Personal", color: Theme.blossom, account: "iCloud", kind: .icloud)]
        if hasGoogle {
            list += [CalList(id: "google", title: "name@gmail.com", color: Theme.mint, account: "name@gmail.com", google: true, kind: .google),
                     CalList(id: "google-holidays", title: "Holidays in Indonesia", color: Theme.butter, account: "name@gmail.com",
                             google: true, writable: false, kind: .google)]
        }
        return list
    }

    func reminderLists() -> [CalList] {
        [CalList(id: "games", title: "Games", color: Theme.blossom, account: "iCloud"),
         CalList(id: "personal", title: "Personal", color: Theme.mint, account: "iCloud")]
    }

    func events(from: Date, to: Date, calendars: [String]) -> [CalEvent] {
        let cal = Calendar.current
        let day = cal.startOfDay(for: now)
        func at(_ dayOffset: Int, _ h: Int, _ m: Int) -> Date {
            cal.date(byAdding: .minute, value: dayOffset * 1440 + h * 60 + m, to: day)!
        }
        let fixed = [
            CalEvent(id: "e0", title: "Morning standup", start: at(0, 9, 0), end: at(0, 9, 15), color: Theme.sky, calendar: "Work", calendarID: "work"),
            CalEvent(id: "e1", title: "Design review: Saku", start: now.addingTimeInterval(8 * 60), end: now.addingTimeInterval(53 * 60),
                     color: Theme.sky, location: "Google Meet", calendar: "Work", joinURL: URL(string: "https://meet.google.com/abc-defg-hij"), calendarID: "work"),
            CalEvent(id: "e2", title: "Gym with Rei", start: at(0, 18, 30), end: at(0, 19, 30), color: Theme.blossom, location: "Studio", calendar: "Personal", calendarID: "home"),
            CalEvent(id: "e3", title: "SIM Jam results", start: at(6, 10, 0), end: at(6, 11, 0), color: Theme.blossom, calendar: "Personal", calendarID: "home"),
            CalEvent(id: "e4", title: "Thesis meeting", start: at(2, 13, 0), end: at(2, 14, 0), color: Theme.sky, calendar: "Work",
                     joinURL: URL(string: "https://us02web.zoom.us/j/123456789"), calendarID: "work"),
            CalEvent(id: "e5", title: "Holiday", start: at(3, 0, 0), end: at(4, 0, 0), allDay: true, color: Theme.mint, calendar: "Personal", calendarID: "home"),
        ]
        let known = Set(self.calendars().map(\.id))
        return (fixed + saved.map(\.event))
            .filter { $0.end > from && $0.start < to && known.contains($0.calendarID) && (calendars.isEmpty || calendars.contains($0.calendarID)) }
            .sorted { $0.start < $1.start }
    }

    func reminders(lists: [String]) async -> [CalReminder] { reminderItems.filter { !$0.done } }

    func setDone(_ id: String, _ done: Bool) {
        if let i = reminderItems.firstIndex(where: { $0.id == id }) { reminderItems[i].done = done }
    }

    func defaultCalendarID() -> String? { "home" }
    func defaultReminderListID() -> String? { "personal" }

    func addEvent(_ d: EventDraft) -> String? {
        guard let c = calendars().first(where: { $0.id == (d.calendarID.isEmpty ? "home" : d.calendarID) }), c.writable else { return nil }
        let id = "saved-\(saved.count + 1)"
        saved.append(Saved(event: CalEvent(id: id, title: d.title, start: d.start, end: d.end, allDay: d.allDay, color: c.color,
                                           calendar: c.title, calendarID: c.id), notes: d.notes, alert: d.alert))
        return id
    }

    func addReminder(title: String, due: Date?, listID: String?) -> Bool {
        let list = reminderLists().first { $0.id == (listID ?? "personal") } ?? reminderLists()[1]
        reminderItems.append(CalReminder(id: "r\(reminderItems.count + 1)", title: title, due: due, list: list.title, color: list.color))
        return true
    }

    func reminderEvents(calendarID: String, from: Date, to: Date) -> [CalReminder] {
        saved.filter { $0.event.calendarID == calendarID && ($0.notes ?? "").contains(ReminderEvents.marker)
                       && !$0.event.title.hasPrefix(ReminderEvents.donePrefix) && $0.event.start < to && $0.event.end > from }
            .map { CalReminder(id: $0.event.id, title: $0.event.title, due: $0.event.start, list: $0.event.calendar, color: $0.event.color, kind: .event) }
    }

    func setEventDone(_ id: String, _ done: Bool, alert: Double?) {
        guard let i = saved.firstIndex(where: { $0.event.id == id }) else { return }
        var t: String? = saved[i].event.title
        ReminderEvents.mark(title: &t, done: done)
        saved[i].event.title = t ?? ""
        saved[i].alert = done ? nil : (saved[i].alert ?? alert)
    }

    func savedItem(_ id: String) -> Saved? { saved.first { $0.event.id == id } }

    func clearSaved() {
        saved = []
        hasGoogle = true
        eventAccess = .granted
        promptAnswer = true
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
    private(set) var calendarList: [CalList] = []

    /// The composer in the Calendar tab: a new event or a new reminder.
    enum Compose: Equatable { case event, reminder }
    var composing: Compose?
    var draftTitle = ""
    var draftMinutes = 9 * 60.0              // time of day; the day is `selectedDay`
    var draftLength = 60.0                   // event minutes, 0 = all day
    var draftTimed = true                    // reminders: false = no time, just the day
    var draftCalendarID = ""
    var draftAlert = 10.0                    // minutes before, -1 = none
    /// True while Saku waits for a Google account to show up after opening Internet Accounts.
    private(set) var connecting = false
    @ObservationIgnored private var watch: Timer?
    @ObservationIgnored private var watchUntil = Date.distantPast

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
        calendarList = source.calendars()
        let cal = Calendar.current
        let ids = app.prefs.v.calendarIDs
        let today = cal.startOfDay(for: now)
        todayEvents = source.events(from: today, to: cal.date(byAdding: .day, value: 1, to: today)!, calendars: ids)
        upcoming = source.events(from: now.addingTimeInterval(-3600), to: cal.date(byAdding: .day, value: 2, to: today)!, calendars: ids)
        loadDay()
        loadMonth()
        if !googleAccounts.isEmpty {
            autoPickGoogle()
            if connecting { stopWatching() }
        }
        // Reminders saved as events update right away; Apple Reminders arrive a moment later.
        reminders = Self.merge(reminderAccess == .granted ? reminders.filter { $0.kind == .reminder } : [], reminderEventItems())
        if reminderAccess == .granted {
            Task { @MainActor in
                let rs = await self.source.reminders(lists: self.app.prefs.v.reminderListIDs)
                self.reminders = Self.merge(rs, self.reminderEventItems())
            }
        }
    }

    static func merge(_ a: [CalReminder], _ b: [CalReminder]) -> [CalReminder] {
        (a + b).sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    // MARK: Google Calendar and writing

    /// Accounts with calendars, in Calendar.app's names, Google ones first.
    var accounts: [String] {
        var seen: [String] = []
        for c in calendarList.sorted(by: { $0.google && !$1.google }) where !seen.contains(c.account) { seen.append(c.account) }
        return seen
    }

    var googleAccounts: [String] { accounts.filter { a in calendarList.contains { $0.account == a && $0.google } } }
    var writableCalendars: [CalList] { calendarList.filter(\.writable) }

    /// Reminders go to a calendar as events (so they reach Google Calendar) when that's picked and the calendar exists.
    var remindersAsEvents: Bool {
        app.prefs.v.reminderTarget == "calendar" && calendarList.contains { $0.id == app.prefs.v.reminderCalendarID && $0.writable }
    }

    var remindersAvailable: Bool { reminderAccess == .granted || (remindersAsEvents && eventAccess == .granted) }

    private func reminderEventItems() -> [CalReminder] {
        guard remindersAsEvents else { return [] }
        let cal = Calendar.current
        let from = cal.date(byAdding: .day, value: -14, to: cal.startOfDay(for: now))!
        let to = cal.date(byAdding: .day, value: 90, to: now)!
        return source.reminderEvents(calendarID: app.prefs.v.reminderCalendarID, from: from, to: to)
    }

    func calendar(_ id: String) -> CalList? { calendarList.first { $0.id == id } }

    /// Where a new event goes: the composer's pick, the saved default, or the system default.
    var targetCalendarID: String {
        for id in [draftCalendarID, app.prefs.v.newEventCalendarID, source.defaultCalendarID() ?? ""] where calendar(id)?.writable == true { return id }
        return writableCalendars.first?.id ?? ""
    }

    func startCompose(_ kind: Compose) {
        draftTitle = ""
        draftCalendarID = ""
        draftAlert = kind == .event ? app.prefs.v.newEventAlert : app.prefs.v.reminderAlert
        draftLength = 60
        draftTimed = true
        let mins = Calendar.current.dateComponents([.hour, .minute], from: now)
        let next = Double((mins.hour ?? 9) * 60 + (mins.minute ?? 0))
        draftMinutes = min(23 * 60 + 45, (next / 30).rounded(.up) * 30 + (kind == .event ? 30 : 0))
        if kind == .reminder { draftMinutes = max(draftMinutes, 9 * 60) }
        withAnimation(Theme.fade) { composing = kind }
    }

    func cancelCompose() { withAnimation(Theme.fade) { composing = nil } }

    /// Start of the draft: the picked day plus the time, or what the title names ("lunch tomorrow 12:30").
    func draftStart(parsed: QuickEvent.Parsed? = nil) -> (start: Date, allDay: Bool) {
        if let p = parsed, let d = p.date { return (p.allDay ? Calendar.current.startOfDay(for: d) : d, p.allDay) }
        let day = Calendar.current.startOfDay(for: selectedDay)
        let untimed = composing == .reminder ? !draftTimed : draftLength == 0
        return (untimed ? day : day.addingTimeInterval(draftMinutes * 60), untimed)
    }

    /// Saves the composer's event or reminder. Returns false when nothing could be saved.
    @discardableResult
    func saveCompose() -> Bool {
        guard let kind = composing else { return false }
        let parsed = QuickEvent.parse(draftTitle)
        let title = parsed.title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return false }
        let when = draftStart(parsed: parsed.date == nil ? nil : parsed)
        var ok = false
        switch kind {
        case .event:
            let length = parsed.duration ?? (when.allDay ? 86400 : max(15, draftLength) * 60)
            let draft = EventDraft(title: title, start: when.start, end: when.start.addingTimeInterval(when.allDay ? 86400 : length),
                                   allDay: when.allDay, calendarID: targetCalendarID, alert: draftAlert < 0 ? nil : draftAlert)
            ok = source.addEvent(draft) != nil
            if ok { app.flash("calendar.badge.plus", tr("Added to %@", calendar(draft.calendarID)?.title ?? tr("Calendar"))) }
        case .reminder:
            var due: Date? = parsed.date != nil || draftTimed ? when.start : nil
            if parsed.date != nil && parsed.allDay { due = when.start.addingTimeInterval(9 * 3600) }
            ok = addReminder(title: title, due: due)
        }
        if ok {
            withAnimation(Theme.fade) { composing = nil }
            reload()
        } else {
            app.flash("exclamationmark.triangle.fill", tr("Couldn't save. Check calendar access."), tint: Theme.coral)
        }
        return ok
    }

    /// A reminder: an Apple Reminder, or an event with an alert in the calendar Angel picked (that's how it reaches Google).
    func addReminder(title: String, due: Date?) -> Bool {
        if remindersAsEvents {
            let start = due ?? Calendar.current.startOfDay(for: selectedDay).addingTimeInterval(9 * 3600)
            let draft = EventDraft(title: title, start: start, end: start.addingTimeInterval(ReminderEvents.length),
                                   calendarID: app.prefs.v.reminderCalendarID, alert: max(0, draftAlert), notes: ReminderEvents.marker)
            let ok = source.addEvent(draft) != nil
            if ok { app.flash("bell.badge.fill", tr("Reminder added to %@", calendar(draft.calendarID)?.title ?? tr("Calendar"))) }
            return ok
        }
        let list = app.prefs.v.reminderListIDs.first ?? source.defaultReminderListID()
        let ok = source.addReminder(title: title, due: due, listID: list)
        if ok { app.flash("checklist", tr("Added to Reminders")) }
        return ok
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
            activateForPrompt()
            _ = await source.requestEvents()
            reload()
        }
    }

    func requestReminderAccess() {
        Task { @MainActor in
            activateForPrompt()
            _ = await source.requestReminders()
            reload()
        }
    }

    /// The permission prompt comes up in front of an active app; Saku is a menu bar app, so bring it forward first.
    private func activateForPrompt() {
        if !app.options.qa { NSApp.activate() }
    }

    /// Pulls in accounts added since launch (a Google account added in System Settings), then redraws.
    func refreshSources() {
        guard eventAccess == .granted else { return }
        source.refresh()
        reload()
    }

    // MARK: Connecting Google Calendar

    /// One button: ask for Calendar access if it was never asked, open Internet Accounts when no Google account is
    /// on the Mac yet, then watch until one appears. Denied access can only be turned on by the user in Privacy & Security.
    func connectGoogle() {
        Task { @MainActor in
            if eventAccess == .unknown {
                activateForPrompt()
                _ = await source.requestEvents()
                reload()
            }
            guard eventAccess == .granted else {
                GoogleCalendar.openPrivacy()
                return
            }
            refreshSources()
            guard googleAccounts.isEmpty else { return }
            GoogleCalendar.openInternetAccounts()
            startWatching()
        }
    }

    /// Checks every few seconds for a few minutes; the store's change notification usually wins first.
    func startWatching(for seconds: TimeInterval = 240) {
        connecting = true
        watchUntil = Date().addingTimeInterval(seconds)
        watch?.invalidate()
        guard !app.options.qa else { return }
        let t = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if Date() > self.watchUntil { self.stopWatching(); return }
                self.refreshSources()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        watch = t
    }

    func stopWatching() {
        watch?.invalidate()
        watch = nil
        connecting = false
    }

    /// The account's own calendar: Google names it after the address. Else the Mac's default if it's Google, else the first.
    var primaryGoogleCalendar: CalList? {
        let g = writableCalendars.filter(\.google)
        if let own = g.first(where: { $0.title.contains("@") && $0.title == $0.account }) { return own }
        if let own = g.first(where: { $0.title.contains("@") }) { return own }
        if let d = source.defaultCalendarID(), let c = g.first(where: { $0.id == d }) { return c }
        return g.first
    }

    /// The first time a Google calendar shows up, it becomes the home for new events and reminders, unless Angel
    /// already picked something herself. Then a small "Connected" note in the notch.
    func autoPickGoogle() {
        let p = app.prefs
        guard !p.v.googleAutoPicked, let g = primaryGoogleCalendar else { return }
        let eventsUnset = calendar(p.v.newEventCalendarID)?.writable != true
        let remindersUnset = p.v.reminderTarget == "reminders" ? p.v.reminderCalendarID.isEmpty : calendar(p.v.reminderCalendarID)?.writable != true
        if eventsUnset { p.v.newEventCalendarID = g.id }
        if remindersUnset {
            p.v.reminderTarget = "calendar"
            p.v.reminderCalendarID = g.id
        }
        p.v.googleAutoPicked = true
        app.flash("checkmark.circle.fill", tr("Connected to Google Calendar"), tint: Theme.mint, seconds: 3.5)
    }

    /// "Google (name@gmail.com): 3 calendars", one line per account, for the status in Settings.
    var sourceLines: [String] {
        accounts.map { acc in
            let cals = calendarList.filter { $0.account == acc }
            let kind = cals.first?.kind ?? .other
            let name: String
            switch kind {
            case .google: name = acc.lowercased() == "google" ? "Google" : "Google (\(acc))"
            case .icloud: name = "iCloud"
            case .local: name = tr("On this Mac")
            case .exchange: name = "Exchange (\(acc))"
            case .subscribed: name = tr("Subscribed")
            case .birthdays: name = tr("Birthdays")
            case .other: name = acc
            }
            return cals.count == 1 ? tr("%@: 1 calendar", name) : tr("%@: %d calendars", name, cals.count)
        }
    }

    func toggle(_ r: CalReminder) {
        if r.kind == .event {
            source.setEventDone(r.id, !r.done, alert: max(0, app.prefs.v.reminderAlert))
        } else {
            source.setDone(r.id, !r.done)
        }
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
