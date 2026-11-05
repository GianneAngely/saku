import AppKit
import SwiftUI

struct TrackersView: View {
    let app: AppModel

    var body: some View {
        HStack(spacing: 10) {
            DaysLeftColumn(app: app)
            TrackerExtras.view(app: app)
        }
    }
}

/// Columns added by the counter and water branches.
@MainActor
enum TrackerExtras {
    @ViewBuilder static func view(app: AppModel) -> some View {
        CountersColumn(app: app)
        WaterColumn(app: app).frame(width: 150)
    }
}

struct CountersColumn: View {
    let app: AppModel
    @State private var adding = false
    @State private var title = ""
    @State private var goal = 0.0
    @State private var daily = true

    var body: some View {
        let m = app.trackers!
        Card(padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Caption(text: tr("Counters"))
                    Spacer()
                    IconButton(symbol: adding ? "xmark" : "plus", size: 10, tint: Theme.text2, hit: 22, help: tr("Add a counter")) { adding.toggle() }
                }
                if adding {
                    NotchField(placeholder: tr("Push-ups, pages, cups of tea…"), text: $title, icon: "number")
                    HStack(spacing: 6) {
                        MinuteStepper(title: tr("Goal"), value: $goal, range: 0...1000, step: 5, unit: "")
                        ToggleChip(title: tr("Daily"), icon: "sunrise.fill", on: daily, tint: Theme.butter) { daily.toggle() }
                    }
                    PillButton(title: tr("Add"), icon: "checkmark", primary: true, tint: Theme.butter, compact: true) {
                        m.addCounter(title: title, goal: Int(goal), daily: daily)
                        title = ""
                        goal = 0
                        adding = false
                    }
                } else if m.counters.isEmpty {
                    EmptyState(icon: "number.circle", title: tr("No counters yet"), subtitle: tr("Track habits and workouts with one tap."), tint: Theme.butter)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 4) {
                            ForEach(m.counters) { c in
                                CounterRow(app: app, counter: c)
                                    .contextMenu {
                                        Button(tr("Reset to zero")) { m.resetCounter(c.id) }
                                        Button(tr("Delete"), role: .destructive) { m.deleteCounter(c.id) }
                                    }
                            }
                        }
                    }
                }
            }
        }
        .onAppear { m.rollOver() }
    }
}

struct CounterRow: View {
    let app: AppModel
    let counter: Counter

    var body: some View {
        let tint = Color(hexString: counter.color) ?? Theme.butter
        HStack(spacing: 8) {
            ZStack {
                if counter.goal > 0 {
                    TimerRing(progress: min(1, Double(counter.value) / Double(counter.goal)), tint: tint, line: 3)
                }
                Text("\(counter.value)").font(Theme.mono(counter.value >= 100 ? 11 : 13, .heavy)).foregroundStyle(Theme.text)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 0) {
                Text(counter.title).font(Theme.font(12, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(subtitle).font(Theme.font(10)).foregroundStyle(Theme.text3).lineLimit(1)
            }
            Spacer(minLength: 2)
            IconButton(symbol: "minus", size: 10, tint: Theme.text2, hit: 24) { app.trackers.bump(counter.id, by: -1) }
            Button { app.trackers.bump(counter.id, by: 1) } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .heavy)).foregroundStyle(Color.black.opacity(0.85))
                    .frame(width: 26, height: 26).background(Circle().fill(tint)).contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: 36)
    }

    private var subtitle: String {
        var parts: [String] = []
        if counter.goal > 0 { parts.append(tr("goal %d", counter.goal)) }
        if counter.daily { parts.append(tr("resets daily")) }
        return parts.isEmpty ? tr("tap + to count") : parts.joined(separator: " · ")
    }
}

struct WaterColumn: View {
    let app: AppModel

    var body: some View {
        let m = app.trackers!
        let w = m.waterToday(now: app.clock)
        let goal = max(1, app.prefs.v.waterGoal)
        Card(padding: 10) {
            VStack(spacing: 6) {
                HStack {
                    Caption(text: tr("Water"))
                    Spacer()
                    if !w.drinks.isEmpty { IconButton(symbol: "arrow.uturn.backward", size: 9.5, tint: Theme.text3, hit: 20, help: tr("Undo")) { m.undoDrink() } }
                }
                WaterGlass(level: w.ml / goal).frame(width: 46, height: 62)
                Text("\(m.waterText(w.ml)) / \(m.waterText(goal))").font(Theme.mono(10.5, .semibold)).foregroundStyle(Theme.text2)
                    .lineLimit(1).minimumScaleFactor(0.8)
                PillButton(title: "+ " + m.waterText(app.prefs.v.waterSip), primary: true, tint: Theme.sky, compact: true) { m.drink() }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// A glass with a wavy water line.
struct WaterGlass: View {
    var level: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: Render.active)) { ctx in
            let t = Render.active ? 0 : ctx.date.timeIntervalSinceReferenceDate
            Canvas { c, size in
                let glass = Path { p in
                    p.move(to: CGPoint(x: 2, y: 0))
                    p.addLine(to: CGPoint(x: size.width - 2, y: 0))
                    p.addLine(to: CGPoint(x: size.width - 7, y: size.height - 4))
                    p.addQuadCurve(to: CGPoint(x: size.width - 11, y: size.height), control: CGPoint(x: size.width - 7.5, y: size.height))
                    p.addLine(to: CGPoint(x: 11, y: size.height))
                    p.addQuadCurve(to: CGPoint(x: 7, y: size.height - 4), control: CGPoint(x: 7.5, y: size.height))
                    p.closeSubpath()
                }
                let fill = min(1, max(0, level))
                let top = size.height * (1 - fill * 0.92)
                var water = Path()
                water.move(to: CGPoint(x: 0, y: size.height))
                for x in stride(from: 0, through: size.width, by: 2) {
                    water.addLine(to: CGPoint(x: x, y: top + 2 * sin(x / 6 + t * 2.4)))
                }
                water.addLine(to: CGPoint(x: size.width, y: size.height))
                water.closeSubpath()
                var inner = c
                inner.clip(to: glass)
                inner.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.white.opacity(0.06)))
                if fill > 0 {
                    inner.fill(water, with: .linearGradient(Gradient(colors: [Theme.sky, Color(hex: 0x4E9BE8)]),
                                                            startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: size.height)))
                }
                c.stroke(glass, with: .color(Color.white.opacity(0.35)), lineWidth: 1.5)
            }
        }
    }
}

struct DaysLeftColumn: View {
    let app: AppModel
    @State private var adding = false
    @State private var title = ""
    @State private var date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var yearly = false

    var body: some View {
        let m = app.trackers!
        Card(padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Caption(text: tr("Days left"))
                    Spacer()
                    IconButton(symbol: adding ? "xmark" : "plus", size: 10, tint: Theme.text2, hit: 22, help: tr("Add a date")) { adding.toggle() }
                }
                if adding {
                    NotchField(placeholder: tr("What is it?"), text: $title, icon: "flag.fill")
                    HStack(spacing: 6) {
                        DatePicker("", selection: $date, displayedComponents: .date)
                            .labelsHidden().datePickerStyle(.field).controlSize(.small)
                        ToggleChip(title: tr("Yearly"), icon: "repeat", on: yearly) { yearly.toggle() }
                    }
                    PillButton(title: tr("Add"), icon: "checkmark", primary: true, compact: true) {
                        m.addDay(title: title, date: date, yearly: yearly)
                        title = ""
                        yearly = false
                        adding = false
                    }
                } else if m.daysLeft.isEmpty {
                    EmptyState(icon: "flag.checkered", title: tr("No dates yet"), subtitle: tr("Count down to trips, exams or birthdays."))
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 4) {
                            ForEach(m.sortedDays) { d in
                                DaysLeftRow(item: d, days: d.days(from: m.today), next: d.target(from: m.today))
                                    .contextMenu { Button(tr("Delete"), role: .destructive) { m.deleteDay(d.id) } }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct DaysLeftRow: View {
    let item: DaysLeft
    let days: Int
    let next: Date

    var body: some View {
        let tint = Color(hexString: item.color) ?? Theme.blossom
        HStack(spacing: 8) {
            Circle().fill(tint).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).font(Theme.font(12, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(dateText).font(Theme.font(10)).foregroundStyle(Theme.text3)
            }
            Spacer(minLength: 4)
            if days == 0 {
                Text(tr("Today")).font(Theme.font(13, .heavy)).foregroundStyle(tint)
            } else {
                VStack(alignment: .trailing, spacing: -2) {
                    Text("\(abs(days))").font(Theme.mono(18, .heavy)).foregroundStyle(days > 0 ? Theme.text : Theme.text3)
                    Text(days > 0 ? (days == 1 ? tr("day left") : tr("days left")) : tr("days ago")).font(Theme.font(9, .semibold)).foregroundStyle(Theme.text3)
                }
            }
        }
        .frame(height: 34)
    }

    private var dateText: String {
        let f = DateFormatter()
        f.locale = Lang.shared.isIndonesian ? Locale(identifier: "id_ID") : Locale(identifier: "en_US")
        f.setLocalizedDateFormatFromTemplate("EEEdMMMyyyy")
        return f.string(from: next) + (item.yearly ? " · " + tr("yearly") : "")
    }
}

struct TrackersPane: View {
    let app: AppModel

    var body: some View {
        let m = app.trackers!
        Form {
            Section(tr("Days left")) {
                if m.daysLeft.isEmpty { Text(tr("Add dates from the Trackers tab.")).foregroundStyle(.secondary) }
                ForEach(m.sortedDays) { d in
                    HStack {
                        ColorPicker("", selection: Binding(get: { Color(hexString: d.color) ?? .pink }, set: { c in
                            var n = d
                            n.color = c.hexString
                            m.updateDay(n)
                        }), supportsOpacity: false).labelsHidden()
                        TextField("", text: Binding(get: { d.title }, set: { t in
                            var n = d
                            n.title = t
                            m.updateDay(n)
                        }))
                        DatePicker("", selection: Binding(get: { d.date }, set: { v in
                            var n = d
                            n.date = Calendar.current.startOfDay(for: v)
                            m.updateDay(n)
                        }), displayedComponents: .date).labelsHidden()
                        Toggle(tr("Yearly"), isOn: Binding(get: { d.yearly }, set: { v in
                            var n = d
                            n.yearly = v
                            m.updateDay(n)
                        }))
                        Button(role: .destructive) { m.deleteDay(d.id) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                }
            }
            TrackersPaneExtras.view(app: app)
        }
        .formStyle(.grouped)
    }
}

@MainActor
enum TrackersPaneExtras {
    @ViewBuilder static func view(app: AppModel) -> some View {
        let m = app.trackers!
        @Bindable var prefs = app.prefs
        Section(tr("Water")) {
            Picker(tr("Unit"), selection: $prefs.v.waterUnit) {
                Text("ml").tag("ml")
                Text("oz").tag("oz")
                Text(tr("cups")).tag("cups")
            }
            SliderRow(title: tr("Daily goal"), value: $prefs.v.waterGoal, range: 500...5000, step: 250) { m.waterText($0) }
            SliderRow(title: tr("Each drink"), value: $prefs.v.waterSip, range: 50...1000, step: 50) { m.waterText($0) }
            Picker(tr("Remind me"), selection: $prefs.v.waterReminder) {
                Text(tr("Never")).tag(0.0)
                ForEach([30.0, 45, 60, 90, 120], id: \.self) { Text(tr("Every %d min", Int($0))).tag($0) }
            }
        }
        Section(tr("Counters")) {
            if m.counters.isEmpty { Text(tr("Add counters from the Trackers tab.")).foregroundStyle(.secondary) }
            ForEach(m.counters) { c in
                HStack {
                    TextField("", text: Binding(get: { c.title }, set: { t in var n = c; n.title = t; m.updateCounter(n) }))
                    Stepper(tr("Goal %d", c.goal), value: Binding(get: { c.goal }, set: { v in var n = c; n.goal = max(0, v); m.updateCounter(n) }), in: 0...10000, step: 5)
                    Stepper(tr("Step %d", c.step), value: Binding(get: { c.step }, set: { v in var n = c; n.step = max(1, v); m.updateCounter(n) }), in: 1...100)
                    Toggle(tr("Daily"), isOn: Binding(get: { c.daily }, set: { v in var n = c; n.daily = v; m.updateCounter(n) }))
                    Button(role: .destructive) { m.deleteCounter(c.id) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                }
            }
        }
    }
}
