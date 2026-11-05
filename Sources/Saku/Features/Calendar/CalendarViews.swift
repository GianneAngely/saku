import AppKit
import SwiftUI

struct CalendarView: View {
    let app: AppModel

    var body: some View {
        let m = app.calendar!
        @Bindable var cm = m
        if m.eventAccess != .granted {
            CalendarAccessPrompt(app: app, reminders: false)
        } else {
            HStack(alignment: .top, spacing: 12) {
                if app.prefs.v.calendarMonthView {
                    MonthGrid(app: app).frame(width: 214)
                }
                VStack(alignment: .leading, spacing: 8) {
                    if let kind = m.composing {
                        EventComposer(app: app, kind: kind)
                    } else {
                        HStack(spacing: 6) {
                            Text(dayTitle(m.selectedDay)).font(Theme.font(13, .bold)).foregroundStyle(Theme.text)
                            Spacer()
                            IconButton(symbol: "plus", size: 11, tint: Theme.text2, hit: 24,
                                       help: m.showReminders ? tr("New reminder") : tr("New event")) {
                                m.startCompose(m.showReminders ? .reminder : .event)
                            }
                            Segments(items: [(false, tr("Events")), (true, tr("Reminders"))], selection: $cm.showReminders, tint: Theme.blossom)
                        }
                        if m.showReminders {
                            RemindersList(app: app)
                        } else if m.dayEvents.isEmpty {
                            EmptyState(icon: "calendar", title: tr("Nothing planned"), subtitle: tr("Enjoy the free time."))
                        } else {
                            FadingList {
                                ForEach(m.dayEvents) { e in EventRow(app: app, event: e) }
                            }
                        }
                        if !m.showReminders && m.googleAccounts.isEmpty && !app.prefs.v.googleHintDismissed {
                            GoogleHint(app: app)
                        }
                    }
                }
            }
        }
    }

    private func dayTitle(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return tr("Today") }
        if cal.isDateInTomorrow(d) { return tr("Tomorrow") }
        let f = DateFormatter()
        f.locale = Lang.shared.isIndonesian ? Locale(identifier: "id_ID") : Locale(identifier: "en_US")
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return f.string(from: d)
    }
}

struct CalendarAccessPrompt: View {
    let app: AppModel
    let reminders: Bool

    var body: some View {
        let m = app.calendar!
        let access = reminders ? m.reminderAccess : m.eventAccess
        let blocked = access == .denied || access == .addOnly
        EmptyState(icon: reminders ? "checklist" : "calendar",
                   title: blocked ? (reminders ? tr("Saku can't see your reminders") : tr("Saku can't see your calendars"))
                                  : (reminders ? tr("See your reminders here") : tr("Connect your calendars")),
                   subtitle: blocked ? (reminders ? tr("Turn on Saku in Privacy & Security › Reminders, then come back.")
                                                  : tr("Turn on Saku with full access in Privacy & Security › Calendars, then come back."))
                                     : (reminders ? tr("Allow Reminders once and your lists show up here.")
                                                  : tr("Allow Calendar access once. Your events show up here, Google Calendar too."))) {
            if blocked {
                PillButton(title: tr("Open Privacy & Security"), icon: "lock.fill", primary: true) {
                    if reminders { Privacy.open("Privacy_Reminders") } else { GoogleCalendar.openPrivacy() }
                }
            } else {
                PillButton(title: reminders ? tr("Allow Reminders access") : tr("Allow Calendar access"), icon: "checkmark", primary: true) {
                    if reminders { m.requestReminderAccess() } else { m.requestAccess() }
                }
            }
        }
    }
}

struct MonthGrid: View {
    let app: AppModel

    var body: some View {
        let m = app.calendar!
        let cal = Calendar.current
        let days = CalendarModel.gridDays(for: m.month)
        let symbols = Self.weekdaySymbols()
        VStack(spacing: 4) {
            HStack {
                Text(monthTitle(m.month)).font(Theme.font(12, .bold)).foregroundStyle(Theme.text)
                Spacer()
                IconButton(symbol: "chevron.left", size: 9, tint: Theme.text2, hit: 20) { m.shiftMonth(-1) }
                IconButton(symbol: "chevron.right", size: 9, tint: Theme.text2, hit: 20) { m.shiftMonth(1) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 1) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, s in
                    Text(s).font(Theme.font(9, .bold)).foregroundStyle(Theme.text3).frame(height: 14)
                }
                ForEach(days, id: \.self) { d in
                    let inMonth = cal.isDate(d, equalTo: m.month, toGranularity: .month)
                    let today = cal.isDateInToday(d)
                    let sel = cal.isDate(d, inSameDayAs: m.selectedDay)
                    Button { m.select(d) } label: {
                        VStack(spacing: 1) {
                            Text("\(cal.component(.day, from: d))")
                                .font(Theme.mono(10.5, today || sel ? .bold : .medium))
                                .foregroundStyle(today ? Color.black.opacity(0.85) : inMonth ? Theme.text : Theme.text3.opacity(0.6))
                                .frame(width: 20, height: 18)
                                .background(Circle().fill(today ? Theme.blossom : Color.clear))
                                .overlay(Circle().strokeBorder(sel && !today ? Theme.blossom : .clear, lineWidth: 1.2))
                            HStack(spacing: 1.5) {
                                ForEach(Array((m.monthDots[cal.startOfDay(for: d)] ?? []).enumerated()), id: \.offset) { _, c in
                                    Circle().fill(c).frame(width: 3, height: 3)
                                }
                            }
                            .frame(height: 3)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func monthTitle(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Lang.shared.isIndonesian ? Locale(identifier: "id_ID") : Locale(identifier: "en_US")
        f.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return f.string(from: d)
    }

    static func weekdaySymbols() -> [String] {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Lang.shared.isIndonesian ? Locale(identifier: "id_ID") : Locale(identifier: "en_US")
        let s = f.veryShortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        return Array(s[(cal.firstWeekday - 1)...] + s[..<(cal.firstWeekday - 1)])
    }
}

struct EventRow: View {
    let app: AppModel
    let event: CalEvent
    var compact = false

    var body: some View {
        let m = app.calendar!
        let now = m.now
        let live = event.start <= now && event.end > now
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(event.color).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(Theme.font(compact ? 11.5 : 12, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(timeText(now: now)).font(Theme.font(10.5)).foregroundStyle(live ? Theme.blossom : Theme.text3).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let _ = event.joinURL, !event.allDay, event.end > now {
                if compact {
                    Button { m.join(event) } label: {
                        Image(systemName: "video.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.black.opacity(0.85))
                            .frame(width: 30, height: 22).background(Capsule().fill(Theme.blossom)).contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(tr("Join"))
                } else {
                    PillButton(title: tr("Join"), icon: "video.fill", primary: event.start.timeIntervalSince(now) < 15 * 60, compact: true) { m.join(event) }
                }
            }
        }
        .padding(.vertical, 4).padding(.trailing, 4)
        .frame(height: compact ? 34 : 38)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { m.open(event) }
    }

    private func timeText(now: Date) -> String {
        if event.allDay { return tr("All day") }
        let f = DateFormatter()
        f.dateFormat = app.prefs.v.use24Hour ? "HH:mm" : "h:mm a"
        var s = "\(f.string(from: event.start)) – \(f.string(from: event.end))"
        if event.start > now && event.start.timeIntervalSince(now) < 12 * 3600 { s += " · " + CalendarModel.countdownText(to: event.start, now: now) }
        else if event.start <= now && event.end > now { s += " · " + tr("now") }
        if !event.location.isEmpty { s += " · " + event.location }
        return s
    }
}

struct RemindersList: View {
    let app: AppModel

    var body: some View {
        let m = app.calendar!
        if !m.remindersAvailable {
            CalendarAccessPrompt(app: app, reminders: true)
        } else if m.reminders.isEmpty {
            EmptyState(icon: "checkmark.circle", title: tr("All done"), subtitle: tr("No open reminders."), tint: Theme.mint)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(m.reminders) { r in
                        HStack(spacing: 8) {
                            Button { m.toggle(r) } label: {
                                Image(systemName: r.done ? "checkmark.circle.fill" : "circle").font(.system(size: 14)).foregroundStyle(r.color)
                            }
                            .buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(r.title).font(Theme.font(12, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                                HStack(spacing: 4) {
                                    if r.kind == .event {
                                        Image(systemName: "calendar").font(.system(size: 8.5, weight: .bold)).foregroundStyle(r.color)
                                            .help(tr("Saved as an event with an alert"))
                                    }
                                    Text(([r.list] + [r.due.map { RelativeDay.text($0, now: m.now) }].compactMap { $0 }).joined(separator: " · "))
                                        .font(Theme.font(10)).foregroundStyle(Theme.text3).lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .frame(height: 32)
                    }
                }
            }
        }
    }
}

/// New event or reminder, right in the notch. The title may name the time ("Lunch with Rei tomorrow 12:30").
struct EventComposer: View {
    let app: AppModel
    let kind: CalendarModel.Compose

    var body: some View {
        let m = app.calendar!
        @Bindable var cm = m
        let parsed = QuickEvent.parse(m.draftTitle)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(kind == .event ? tr("New event") : tr("New reminder")).font(Theme.font(13, .bold)).foregroundStyle(Theme.text)
                Spacer()
                IconButton(symbol: "xmark", size: 10, tint: Theme.text2, hit: 22, help: tr("Cancel")) { m.cancelCompose() }
            }
            NotchField(placeholder: kind == .event ? tr("What's on? e.g. Lunch with Rei 12:30") : tr("Remind me to…"),
                       text: $cm.draftTitle, icon: kind == .event ? "calendar.badge.plus" : "bell.fill") { m.saveCompose() }
            HStack(spacing: 6) {
                if parsed.date != nil {
                    Label(whenText(parsed), systemImage: "wand.and.stars")
                        .font(Theme.font(11, .semibold)).foregroundStyle(Theme.blossom).lineLimit(1)
                        .help(tr("Saku read the time from what you typed."))
                } else {
                    DayStepper(app: app)
                    if kind == .event {
                        if m.draftLength > 0 { ClockStepper(app: app, minutes: $cm.draftMinutes) }
                        ForEach([(30.0, "30m"), (60, "1h"), (120, "2h"), (0, tr("All day"))], id: \.0) { len, title in
                            ChoiceChip(title: title, on: m.draftLength == len) { m.draftLength = len }
                        }
                    } else {
                        if m.draftTimed { ClockStepper(app: app, minutes: $cm.draftMinutes) }
                        ChoiceChip(title: tr("No time"), on: !m.draftTimed) { m.draftTimed.toggle() }
                    }
                }
            }
            HStack(spacing: 6) {
                if kind == .event { CalendarMenu(app: app) } else { ReminderTargetMenu(app: app) }
                AlertMenu(app: app)
                Spacer(minLength: 0)
                PillButton(title: tr("Add"), icon: "checkmark", primary: true, compact: true) { m.saveCompose() }
                    .disabled(parsed.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func whenText(_ p: QuickEvent.Parsed) -> String {
        guard let d = p.date else { return "" }
        if p.allDay {
            let f = DateFormatter()
            f.locale = Lang.shared.isIndonesian ? Locale(identifier: "id_ID") : Locale(identifier: "en_US")
            f.setLocalizedDateFormatFromTemplate("EEEdMMM")
            return f.string(from: d) + " · " + tr("All day")
        }
        return RelativeDay.text(d, now: app.calendar.now)
    }
}

/// ‹ Today › — moves the composer's day (the month grid moves it too).
struct DayStepper: View {
    let app: AppModel

    var body: some View {
        let m = app.calendar!
        let cal = Calendar.current
        HStack(spacing: 0) {
            IconButton(symbol: "chevron.left", size: 8.5, tint: Theme.text2, hit: 20) {
                m.select(cal.date(byAdding: .day, value: -1, to: m.selectedDay) ?? m.selectedDay)
            }
            Text(label(m.selectedDay)).font(Theme.font(11, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                .frame(minWidth: 58)
            IconButton(symbol: "chevron.right", size: 8.5, tint: Theme.text2, hit: 20) {
                m.select(cal.date(byAdding: .day, value: 1, to: m.selectedDay) ?? m.selectedDay)
            }
        }
        .frame(height: 24)
        .background(Capsule().fill(Color.white.opacity(0.07)))
    }

    private func label(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return tr("Today") }
        if cal.isDateInTomorrow(d) { return tr("Tomorrow") }
        let f = DateFormatter()
        f.locale = Lang.shared.isIndonesian ? Locale(identifier: "id_ID") : Locale(identifier: "en_US")
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return f.string(from: d)
    }
}

/// − 12:30 + in 15-minute steps.
struct ClockStepper: View {
    let app: AppModel
    @Binding var minutes: Double

    var body: some View {
        HStack(spacing: 0) {
            step("minus", -15)
            Text(text).font(Theme.mono(11.5, .bold)).foregroundStyle(Theme.text).frame(minWidth: 40)
            step("plus", 15)
        }
        .frame(height: 24)
        .background(Capsule().fill(Color.white.opacity(0.07)))
    }

    private var text: String {
        let h = Int(minutes) / 60, mm = Int(minutes) % 60
        if app.prefs.v.use24Hour { return String(format: "%02d:%02d", h, mm) }
        return String(format: "%d:%02d %@", h % 12 == 0 ? 12 : h % 12, mm, h < 12 ? "am" : "pm")
    }

    private func step(_ symbol: String, _ by: Double) -> some View {
        Button { minutes = (minutes + by + 1440).truncatingRemainder(dividingBy: 1440) } label: {
            Image(systemName: symbol).font(.system(size: 8.5, weight: .bold)).foregroundStyle(Theme.text2)
                .frame(width: 18, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Small pill that's either on (filled) or off.
struct ChoiceChip: View {
    var title: String
    var on: Bool
    var tint: Color = Theme.blossom
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(Theme.font(10.5, .semibold)).lineLimit(1)
                .foregroundStyle(on ? Color.black.opacity(0.85) : Theme.text2)
                .padding(.horizontal, 8).frame(height: 22)
                .background(Capsule().fill(on ? tint : Color.white.opacity(0.07)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Which calendar a new event goes to, grouped by account (Google first).
struct CalendarMenu: View {
    let app: AppModel

    var body: some View {
        let m = app.calendar!
        let target = m.calendar(m.targetCalendarID)
        Menu {
            ForEach(m.accounts, id: \.self) { acc in
                Section(acc) {
                    ForEach(m.writableCalendars.filter { $0.account == acc }) { c in
                        Button { m.draftCalendarID = c.id } label: {
                            Label(c.title, systemImage: c.id == target?.id ? "checkmark" : "circle")
                        }
                    }
                }
            }
        } label: {
            MenuPill(dot: target?.color ?? Theme.text3, text: target.map { $0.google ? "\($0.title) · Google" : $0.title } ?? tr("No calendar"))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help(tr("Calendar for this event"))
    }
}

/// Where a new reminder goes: Apple Reminders, or a calendar as an event with an alert (that's the way into Google Calendar).
struct ReminderTargetMenu: View {
    let app: AppModel

    var body: some View {
        let m = app.calendar!
        let p = app.prefs
        Menu {
            Button { p.v.reminderTarget = "reminders"; m.reload() } label: {
                Label(tr("Apple Reminders"), systemImage: m.remindersAsEvents ? "circle" : "checkmark")
            }
            ForEach(m.accounts, id: \.self) { acc in
                Section(acc) {
                    ForEach(m.writableCalendars.filter { $0.account == acc }) { c in
                        Button {
                            p.v.reminderTarget = "calendar"
                            p.v.reminderCalendarID = c.id
                            m.reload()
                        } label: {
                            Label(tr("%@ (as an event)", c.title), systemImage: m.remindersAsEvents && p.v.reminderCalendarID == c.id ? "checkmark" : "circle")
                        }
                    }
                }
            }
        } label: {
            if m.remindersAsEvents, let c = m.calendar(p.v.reminderCalendarID) {
                MenuPill(dot: c.color, text: c.google ? "\(c.title) · Google" : c.title)
            } else {
                MenuPill(dot: Theme.sky, text: tr("Reminders"))
            }
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help(tr("Where new reminders go"))
    }
}

/// Alert before the event: none, at the start, 5 to 60 minutes before.
struct AlertMenu: View {
    let app: AppModel
    static let choices: [Double] = [-1, 0, 5, 10, 15, 30, 60]

    var body: some View {
        let m = app.calendar!
        Menu {
            ForEach(Self.choices, id: \.self) { v in
                Button { m.draftAlert = v } label: { Label(Self.title(v), systemImage: m.draftAlert == v ? "checkmark" : "circle") }
            }
        } label: {
            MenuPill(icon: m.draftAlert < 0 ? "bell.slash.fill" : "bell.fill", text: Self.short(m.draftAlert))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help(tr("Alert"))
    }

    static func title(_ v: Double) -> String {
        switch v {
        case ..<0: tr("No alert")
        case 0: tr("At the start")
        case 60: tr("1 hour before")
        default: tr("%d min before", Int(v))
        }
    }

    static func short(_ v: Double) -> String {
        switch v {
        case ..<0: tr("None")
        case 0: tr("At start")
        case 60: "1h"
        default: "\(Int(v))m"
        }
    }
}

struct MenuPill: View {
    var dot: Color? = nil
    var icon: String? = nil
    var text: String

    var body: some View {
        HStack(spacing: 5) {
            if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
            if let icon { Image(systemName: icon).font(.system(size: 9.5, weight: .bold)).foregroundStyle(Theme.text2) }
            Text(text).font(Theme.font(11, .semibold)).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 150, alignment: .leading).fixedSize(horizontal: true, vertical: false)
            Image(systemName: "chevron.down").font(.system(size: 7.5, weight: .bold)).foregroundStyle(Theme.text3)
        }
        .padding(.horizontal, 9).frame(height: 24)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .contentShape(Capsule())
    }
}

/// One line under the events when no Google account is on this Mac yet.
struct GoogleHint: View {
    let app: AppModel

    var body: some View {
        let m = app.calendar!
        HStack(spacing: 6) {
            if m.connecting {
                ProgressView().controlSize(.mini)
                Text(tr("Waiting for Google… sign in in System Settings")).font(Theme.font(11, .medium)).foregroundStyle(Theme.text2).lineLimit(1)
                Spacer(minLength: 4)
                IconButton(symbol: "xmark", size: 8.5, tint: Theme.text3, hit: 18, help: tr("Stop waiting")) { m.stopWatching() }
            } else {
                Image(systemName: "link").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.sky)
                Text(tr("Want your Google Calendar here too?")).font(Theme.font(11, .medium)).foregroundStyle(Theme.text2).lineLimit(1)
                Spacer(minLength: 4)
                PillButton(title: tr("Connect"), compact: true) { m.connectGoogle() }
                IconButton(symbol: "xmark", size: 8.5, tint: Theme.text3, hit: 18, help: tr("Hide")) { app.prefs.v.googleHintDismissed = true }
            }
        }
        .padding(.leading, 9).padding(.trailing, 3)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.sky.opacity(0.08)))
    }
}

/// "Today 15:00", "Tomorrow", "Mon 9 Nov".
enum RelativeDay {
    static func text(_ d: Date, now: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Lang.shared.isIndonesian ? Locale(identifier: "id_ID") : Locale(identifier: "en_US")
        f.dateFormat = "HH:mm"
        if cal.isDate(d, inSameDayAs: now) { return tr("Today %@", f.string(from: d)) }
        if let t = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(d, inSameDayAs: t) { return tr("Tomorrow %@", f.string(from: d)) }
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return f.string(from: d)
    }
}

struct CalendarPane: View {
    let app: AppModel

    var body: some View {
        @Bindable var prefs = app.prefs
        let m = app.calendar!
        Form {
            GoogleCalendarSection(app: app)
            Section {
                Toggle(tr("Show the month view"), isOn: $prefs.v.calendarMonthView)
                Toggle(tr("Hide events that have ended"), isOn: $prefs.v.calendarHideEnded)
                Toggle(tr("Show today's events on Home"), isOn: $prefs.v.calendarOnHome)
                Toggle(tr("Count down to the next meeting in the closed notch"), isOn: $prefs.v.meetingHeadsUp)
                Stepper(value: $prefs.v.meetingLead, in: 1...60) { LabeledContent(tr("Start the countdown"), value: tr("%d min before", Int(prefs.v.meetingLead))) }
                    .disabled(!prefs.v.meetingHeadsUp)
            }
            Section {
                Picker(tr("New events go to"), selection: $prefs.v.newEventCalendarID) {
                    Text(tr("Default calendar")).tag("")
                    CalendarPickerItems(app: app)
                }
                Picker(tr("Alert"), selection: $prefs.v.newEventAlert) {
                    ForEach(AlertMenu.choices, id: \.self) { Text(AlertMenu.title($0)).tag($0) }
                }
            } header: {
                Text(tr("New events"))
            } footer: {
                Text(tr("Add one with + in the Calendar tab. You can type the time into the title in English, like “Lunch with Rei tomorrow 12:30”."))
            }
            Section {
                Picker(tr("Save new reminders to"), selection: $prefs.v.reminderTarget) {
                    Text(tr("Apple Reminders")).tag("reminders")
                    Text(tr("A calendar, as an event with an alert")).tag("calendar")
                }
                if prefs.v.reminderTarget == "calendar" {
                    Picker(tr("Calendar"), selection: $prefs.v.reminderCalendarID) {
                        Text(tr("Pick a calendar")).tag("")
                        CalendarPickerItems(app: app)
                    }
                    Picker(tr("Alert"), selection: $prefs.v.reminderAlert) {
                        ForEach(AlertMenu.choices.filter { $0 >= 0 }, id: \.self) { Text(AlertMenu.title($0)).tag($0) }
                    }
                }
            } header: {
                Text(tr("Reminders"))
            } footer: {
                Text(tr("Apple Reminders doesn't sync with Google Tasks. Pick your Google calendar here and every reminder you add in Saku becomes a 15-minute event with an alert in it, so it rings on your phone too. Ticking it off in Saku puts ✓ in front of the title and removes the alert."))
            }
            Section(tr("Calendars")) {
                if m.eventAccess != .granted {
                    Button(tr("Allow calendar access")) { m.requestAccess() }
                } else {
                    ForEach(m.accounts, id: \.self) { acc in
                        Text(acc + (m.googleAccounts.contains(acc) ? " · Google" : "")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(m.calendarList.filter { $0.account == acc }) { c in
                            Toggle(isOn: Binding(get: { prefs.v.calendarIDs.isEmpty || prefs.v.calendarIDs.contains(c.id) }, set: { on in
                                let all = m.calendarList.map(\.id)
                                var ids = prefs.v.calendarIDs.isEmpty ? all : prefs.v.calendarIDs
                                ids.removeAll { $0 == c.id }
                                if on { ids.append(c.id) }
                                prefs.v.calendarIDs = ids.count == all.count ? [] : ids
                                m.reload()
                            })) { Label { Text(c.title) } icon: { Circle().fill(c.color).frame(width: 9, height: 9) } }
                        }
                    }
                }
            }
            Section(tr("Reminder lists")) {
                if m.reminderAccess != .granted {
                    Button(tr("Allow reminders access")) { m.requestReminderAccess() }
                } else {
                    ForEach(m.source.reminderLists()) { c in
                        Toggle(isOn: Binding(get: { prefs.v.reminderListIDs.isEmpty || prefs.v.reminderListIDs.contains(c.id) }, set: { on in
                            var ids = prefs.v.reminderListIDs.isEmpty ? m.source.reminderLists().map(\.id) : prefs.v.reminderListIDs
                            ids.removeAll { $0 == c.id }
                            if on { ids.append(c.id) }
                            prefs.v.reminderListIDs = ids.count == m.source.reminderLists().count ? [] : ids
                            m.reload()
                        })) { Label { Text(c.title) } icon: { Circle().fill(c.color).frame(width: 9, height: 9) } }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { m.reload() }
        .onChange(of: prefs.v.reminderTarget) { m.reload() }
        .onChange(of: prefs.v.reminderCalendarID) { m.reload() }
    }
}

/// Writable calendars as picker rows, Google accounts first.
struct CalendarPickerItems: View {
    let app: AppModel

    var body: some View {
        let m = app.calendar!
        ForEach(m.accounts, id: \.self) { acc in
            Section(acc + (m.googleAccounts.contains(acc) ? " · Google" : "")) {
                ForEach(m.writableCalendars.filter { $0.account == acc }) { c in Text(c.title).tag(c.id) }
            }
        }
    }
}

/// Everything about the calendar connection in one place: permission, the accounts Saku can read, where new
/// events and reminders go, and one button to bring in Google through macOS Internet Accounts.
struct GoogleCalendarSection: View {
    let app: AppModel

    var body: some View {
        let m = app.calendar!
        let p = app.prefs.v
        Section {
            LabeledContent(tr("Calendar access")) {
                HStack(spacing: 8) {
                    StatusDot(color: m.eventAccess == .granted ? .green : m.eventAccess == .unknown ? .orange : .red)
                    Text(accessText(m.eventAccess)).foregroundStyle(.secondary)
                    switch m.eventAccess {
                    case .unknown: Button(tr("Allow Calendar access")) { m.requestAccess() }.buttonStyle(.borderedProminent)
                    case .denied, .addOnly: Button(tr("Open Privacy & Security")) { GoogleCalendar.openPrivacy() }
                    case .granted: EmptyView()
                    }
                }
            }
            if m.eventAccess == .denied || m.eventAccess == .addOnly {
                Text(tr("Turn on Saku with full access in Privacy & Security › Calendars, then come back. macOS only asks once."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if m.eventAccess == .granted {
                LabeledContent(tr("Calendars Saku can see")) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if m.sourceLines.isEmpty { Text(tr("None yet")).foregroundStyle(.secondary) }
                        ForEach(m.sourceLines, id: \.self) { Text($0).foregroundStyle(.secondary) }
                    }
                }
                LabeledContent(tr("New events go to")) {
                    Text(m.calendar(m.targetCalendarID).map(Self.name) ?? tr("Default calendar")).foregroundStyle(.secondary)
                }
                LabeledContent(tr("New reminders go to")) {
                    Text(m.remindersAsEvents ? (m.calendar(p.reminderCalendarID).map(Self.name) ?? "–") : tr("Apple Reminders")).foregroundStyle(.secondary)
                }
            }
            if !m.googleAccounts.isEmpty {
                ForEach(m.googleAccounts, id: \.self) { acc in
                    Label(tr("Connected: %@", acc), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                HStack {
                    Spacer()
                    Button(tr("Add another account")) { GoogleCalendar.openInternetAccounts() }
                    Button { m.refreshSources() } label: { Image(systemName: "arrow.clockwise") }.help(tr("Refresh"))
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("1. Click Connect: macOS opens Internet Accounts.")).font(.callout)
                    Text(tr("2. Add Account › Google, then sign in with the Google account you want.")).font(.callout)
                    Text(tr("3. Keep Calendars on. Saku picks your Google calendar and says when it's connected.")).font(.callout)
                }
                .foregroundStyle(.secondary)
                HStack {
                    if m.connecting {
                        ProgressView().controlSize(.small)
                        Text(tr("Waiting for your Google account…")).foregroundStyle(.secondary)
                        Button(tr("Stop waiting")) { m.stopWatching() }
                    }
                    Spacer()
                    Button { m.refreshSources() } label: { Image(systemName: "arrow.clockwise") }.help(tr("Refresh"))
                    Button(tr("Connect Google Calendar")) { m.connectGoogle() }.buttonStyle(.borderedProminent)
                }
            }
        } header: {
            Text(tr("Google Calendar"))
        } footer: {
            Text(tr("Saku never sees your Google password: macOS signs in and keeps the calendars in sync, Saku reads and writes them on this Mac. No Google key, nothing sent anywhere else."))
        }
    }

    static func name(_ c: CalList) -> String { c.google ? "\(c.title) · Google" : c.title }

    private func accessText(_ a: CalAccess) -> String {
        switch a {
        case .granted: tr("Allowed")
        case .unknown: tr("Not asked yet")
        case .denied: tr("Not allowed")
        case .addOnly: tr("Add-only (Saku needs full access)")
        }
    }
}

struct StatusDot: View {
    var color: Color
    var body: some View { Circle().fill(color).frame(width: 8, height: 8) }
}
