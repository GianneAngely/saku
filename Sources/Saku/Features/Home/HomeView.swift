import SwiftUI

/// Which view fills the open notch for a tab. Feature branches add their case here.
struct TabContent: View {
    let app: AppModel
    let tab: Tab

    var body: some View {
        switch tab {
        case .home: HomeView(app: app)
        case .timers: TimersView(app: app)
        case .tray: TrayView(app: app)
        case .clipboard: ClipboardView(app: app)
        case .notes: NotesView(app: app)
        case .prompter: PrompterTab(app: app)
        default: EmptyState(icon: tab.icon, title: tab.title, subtitle: tr("Turn this tab on in Settings"))
        }
    }
}

struct HomeView: View {
    let app: AppModel

    var body: some View {
        HStack(spacing: 10) {
            if app.prefs.v.musicOnHome, app.music != nil {
                MusicCard(app: app)
                TodayCard(app: app).frame(width: 200)
            } else {
                TodayCard(app: app).frame(width: 210)
                GlanceColumn(app: app)
            }
        }
    }
}

/// Date, time and (with the Calendar feature) the next events.
struct TodayCard: View {
    let app: AppModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 2) {
                Text(weekday).font(Theme.font(11, .bold)).foregroundStyle(Theme.blossom)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(day).font(Theme.font(34, .heavy)).foregroundStyle(Theme.text)
                    Text(month).font(Theme.font(13, .semibold)).foregroundStyle(Theme.text2)
                }
                Text(time).font(Theme.mono(13, .semibold)).foregroundStyle(Theme.text2)
                Spacer(minLength: 0)
            }
        }
    }

    private func fmt(_ template: String) -> String {
        let f = DateFormatter()
        f.locale = Lang.shared.isIndonesian ? Locale(identifier: "id_ID") : Locale(identifier: "en_US")
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: app.clock)
    }

    private var weekday: String { fmt("EEEE") }
    private var day: String { fmt("d") }
    private var month: String { fmt("MMMM yyyy") }
    private var time: String {
        let f = DateFormatter()
        f.dateFormat = app.prefs.v.use24Hour ? "HH:mm" : "h:mm a"
        return f.string(from: app.clock)
    }
}

/// Small stacked widgets on the right of Home. Features add rows as they land.
struct GlanceColumn: View {
    let app: AppModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Caption(text: tr("Hover the notch to open Saku. Drag files onto it to keep them."))
                Spacer(minLength: 0)
                HStack {
                    BlossomMark(size: 16)
                    Text("Saku").font(Theme.font(13, .bold)).foregroundStyle(Theme.text)
                    Spacer()
                    PillButton(title: tr("Settings"), icon: "gearshape.fill", compact: true) { app.commands.openSettings(nil) }
                }
            }
        }
    }
}
