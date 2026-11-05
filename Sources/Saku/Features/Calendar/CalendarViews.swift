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
                    HStack {
                        Text(dayTitle(m.selectedDay)).font(Theme.font(13, .bold)).foregroundStyle(Theme.text)
                        Spacer()
                        Segments(items: [(false, tr("Events")), (true, tr("Reminders"))], selection: $cm.showReminders, tint: Theme.blossom)
                    }
                    if m.showReminders {
                        RemindersList(app: app)
                    } else if m.dayEvents.isEmpty {
                        EmptyState(icon: "calendar", title: tr("Nothing planned"), subtitle: tr("Enjoy the free time."))
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 4) {
                                ForEach(m.dayEvents) { e in EventRow(app: app, event: e) }
                            }
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
        EmptyState(icon: reminders ? "checklist" : "calendar",
                   title: reminders ? tr("See your reminders here") : tr("See your calendar here"),
                   subtitle: access == .denied ? tr("Saku is not allowed yet. Turn it on in Privacy & Security.")
                                               : tr("Today's events, a month view and a heads-up before meetings.")) {
            if access == .denied {
                PillButton(title: tr("Open Privacy settings"), icon: "lock.fill", primary: true) {
                    Privacy.open(reminders ? "Privacy_Reminders" : "Privacy_Calendars")
                }
            } else {
                PillButton(title: tr("Allow access"), icon: "checkmark", primary: true) {
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
        if m.reminderAccess != .granted {
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
                                Text(([r.list] + [r.due.map { RelativeDay.text($0, now: m.now) }].compactMap { $0 }).joined(separator: " · "))
                                    .font(Theme.font(10)).foregroundStyle(Theme.text3)
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
            Section {
                Toggle(tr("Show the month view"), isOn: $prefs.v.calendarMonthView)
                Toggle(tr("Hide events that have ended"), isOn: $prefs.v.calendarHideEnded)
                Toggle(tr("Show today's events on Home"), isOn: $prefs.v.calendarOnHome)
                Toggle(tr("Count down to the next meeting in the closed notch"), isOn: $prefs.v.meetingHeadsUp)
                Stepper(value: $prefs.v.meetingLead, in: 1...60) { LabeledContent(tr("Start the countdown"), value: tr("%d min before", Int(prefs.v.meetingLead))) }
                    .disabled(!prefs.v.meetingHeadsUp)
            }
            Section(tr("Calendars")) {
                if m.eventAccess != .granted {
                    Button(tr("Allow calendar access")) { m.requestAccess() }
                } else {
                    ForEach(m.source.calendars()) { c in
                        Toggle(isOn: Binding(get: { prefs.v.calendarIDs.isEmpty || prefs.v.calendarIDs.contains(c.id) }, set: { on in
                            var ids = prefs.v.calendarIDs.isEmpty ? m.source.calendars().map(\.id) : prefs.v.calendarIDs
                            ids.removeAll { $0 == c.id }
                            if on { ids.append(c.id) }
                            prefs.v.calendarIDs = ids.count == m.source.calendars().count ? [] : ids
                            m.reload()
                        })) { Label { Text(c.title) } icon: { Circle().fill(c.color).frame(width: 9, height: 9) } }
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
    }
}
