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
        EmptyView()
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
        EmptyView()
    }
}
