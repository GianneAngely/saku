import AppKit
import SwiftUI

/// One thing Saku can do, where it lives, and how to jump there.
struct FeatureEntry: Identifiable {
    let id: String
    let icon: String
    let tint: Color
    let title: String
    /// Where to find it, in plain words ("System tab · left card").
    let place: String
    /// Extra search words in English and Indonesian.
    let keywords: String
    let go: @MainActor (AppModel) -> Void

    func matches(_ query: String) -> Bool {
        let q = Self.fold(query)
        guard !q.isEmpty else { return true }
        let hay = Self.fold([title, place, keywords, id].joined(separator: " "))
        return q.split(separator: " ").allSatisfy { hay.contains($0) }
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Every feature in one list, for the All features page, the menu bar menu and the README.
@MainActor
enum FeatureCatalog {
    static func tab(_ t: Tab, spot: String? = nil, _ setup: @escaping @MainActor (AppModel) -> Void = { _ in }) -> @MainActor (AppModel) -> Void {
        { app in
            setup(app)
            app.show(t, spotlight: spot)
        }
    }

    static func settings(_ pane: String) -> @MainActor (AppModel) -> Void {
        { app in
            app.commands.closeNotch()
            app.commands.openSettings(pane)
        }
    }

    static var all: [FeatureEntry] {
        [
            FeatureEntry(id: "music", icon: "music.note", tint: Theme.blossom, title: tr("Music"),
                         place: tr("Home tab · music card"),
                         keywords: "spotify apple music song player lagu musik putar", go: tab(.home, spot: "music")),
            FeatureEntry(id: "browser-music", icon: "play.rectangle.fill", tint: Theme.coral, title: tr("Browser music"),
                         place: tr("Settings › Music"),
                         keywords: "youtube soundcloud chrome safari browser web lagu", go: settings("music")),
            FeatureEntry(id: "tray", icon: "tray.full.fill", tint: Theme.blossom, title: tr("Tray"),
                         place: tr("Tray tab"),
                         keywords: "files file drop drag shelf berkas simpan seret", go: tab(.tray)),
            FeatureEntry(id: "airdrop", icon: "dot.radiowaves.left.and.right", tint: Theme.sky, title: tr("AirDrop"),
                         place: tr("Tray tab · AirDrop all"),
                         keywords: "airdrop share send kirim bagikan", go: tab(.tray)),
            FeatureEntry(id: "ocr", icon: "text.viewfinder", tint: Theme.lavender, title: tr("Copy text from an image"),
                         place: tr("Tray tab · right-click an image"),
                         keywords: "ocr text image scan teks gambar pindai", go: tab(.tray)),
            FeatureEntry(id: "clipboard", icon: "list.clipboard.fill", tint: Theme.sky, title: tr("Clipboard history"),
                         place: tr("Clipboard tab · History"),
                         keywords: "copy paste history salin tempel riwayat", go: tab(.clipboard) { $0.clipboard?.mode = 0 }),
            FeatureEntry(id: "snippets", icon: "text.badge.plus", tint: Theme.butter, title: tr("Snippets"),
                         place: tr("Clipboard tab · Snippets"),
                         keywords: "snippet template saved text teks cepat simpanan", go: tab(.clipboard) { $0.clipboard?.mode = 1 }),
            FeatureEntry(id: "pomodoro", icon: "timer", tint: Theme.butter, title: tr("Pomodoro"),
                         place: tr("Timers tab · Pomodoro"),
                         keywords: "focus study work fokus belajar kerja", go: tab(.timers) { $0.timers?.mode = .pomodoro }),
            FeatureEntry(id: "countdown", icon: "hourglass", tint: Theme.blossom, title: tr("Countdown timer"),
                         place: tr("Timers tab · Countdown"),
                         keywords: "timer alarm countdown hitung mundur", go: tab(.timers) { $0.timers?.mode = .countdown }),
            FeatureEntry(id: "stopwatch", icon: "stopwatch.fill", tint: Theme.sky, title: tr("Stopwatch"),
                         place: tr("Timers tab · Stopwatch"),
                         keywords: "stopwatch lap waktu", go: tab(.timers) { $0.timers?.mode = .stopwatch }),
            FeatureEntry(id: "calendar", icon: "calendar", tint: Theme.blossom, title: tr("Calendar and events"),
                         place: tr("Calendar tab · Events"),
                         keywords: "calendar event schedule meeting kalender acara jadwal", go: tab(.calendar) { $0.calendar?.showReminders = false }),
            FeatureEntry(id: "reminders", icon: "checklist", tint: Theme.mint, title: tr("Reminders"),
                         place: tr("Calendar tab · Reminders"),
                         keywords: "reminder todo task pengingat tugas", go: tab(.calendar) { $0.calendar?.showReminders = true }),
            FeatureEntry(id: "google-calendar", icon: "link", tint: Theme.sky, title: tr("Google Calendar"),
                         place: tr("Settings › Calendar"),
                         keywords: "google gmail calendar sync account sinkron akun", go: settings("calendar")),
            FeatureEntry(id: "meetings", icon: "video.fill", tint: Theme.blossom, title: tr("Join meetings"),
                         place: tr("Calendar tab · Join"),
                         keywords: "zoom meet teams webex meeting rapat join gabung", go: tab(.calendar) { $0.calendar?.showReminders = false }),
            FeatureEntry(id: "notes", icon: "note.text", tint: Theme.butter, title: tr("Notes"),
                         place: tr("Notes tab"),
                         keywords: "notes write catatan tulis", go: tab(.notes)),
            FeatureEntry(id: "todo", icon: "checklist.checked", tint: Theme.mint, title: tr("To-do list"),
                         place: tr("To-do tab"),
                         keywords: "todo to-do tasks task checklist tugas daftar centang", go: tab(.todo)),
            FeatureEntry(id: "google-tasks", icon: "checkmark.icloud.fill", tint: Theme.sky, title: tr("Google Tasks"),
                         place: tr("Settings › To-do"),
                         keywords: "google tasks sync android phone tugas sinkron hp", go: settings("todo")),
            FeatureEntry(id: "prompter", icon: "text.line.first.and.arrowtriangle.forward", tint: Theme.lavender, title: tr("Teleprompter"),
                         place: tr("Teleprompter tab"),
                         keywords: "teleprompter script video record naskah rekam", go: tab(.prompter)),
            FeatureEntry(id: "days-left", icon: "flag.checkered", tint: Theme.blossom, title: tr("Days left"),
                         place: tr("Trackers tab · left card"),
                         keywords: "countdown days deadline birthday hari lagi ulang tahun", go: tab(.trackers, spot: "days")),
            FeatureEntry(id: "counters", icon: "number.circle.fill", tint: Theme.butter, title: tr("Habit counters"),
                         place: tr("Trackers tab · middle card"),
                         keywords: "habit counter count push-ups kebiasaan hitung", go: tab(.trackers, spot: "counters")),
            FeatureEntry(id: "water", icon: "drop.fill", tint: Theme.sky, title: tr("Water tracker"),
                         place: tr("Trackers tab · right card"),
                         keywords: "water drink hydrate air minum", go: tab(.trackers, spot: "water")),
            FeatureEntry(id: "eye-breaks", icon: "eye.fill", tint: Theme.mint, title: tr("Eye breaks (20-20-20)"),
                         place: tr("Settings › Tools"),
                         keywords: "eye break rest mata istirahat 20-20-20", go: settings("tools")),
            FeatureEntry(id: "web", icon: "globe", tint: Theme.sky, title: tr("Mini browser"),
                         place: tr("Web tab"),
                         keywords: "web browser internet search google cari", go: tab(.web)),
            FeatureEntry(id: "bookmarks", icon: "star.fill", tint: Theme.butter, title: tr("Bookmarks"),
                         place: tr("Web tab · start page"),
                         keywords: "bookmark favourite favorite favorit", go: tab(.web)),
            FeatureEntry(id: "translate", icon: "character.bubble.fill", tint: Theme.lavender, title: tr("Translate"),
                         place: tr("Translate tab"),
                         keywords: "translate language terjemah bahasa", go: tab(.translate)),
            FeatureEntry(id: "ai", icon: "sparkles", tint: Theme.lavender, title: tr("AI assistant"),
                         place: tr("AI tab"),
                         keywords: "ai chat claude gemini apple intelligence ask tanya", go: tab(.ai)),
            FeatureEntry(id: "mirror", icon: "camera.fill", tint: Theme.blossom, title: tr("Mirror and ring light"),
                         place: tr("Mirror tab"),
                         keywords: "camera mirror ring light kamera cermin", go: tab(.camera)),
            FeatureEntry(id: "apps", icon: "square.grid.2x2.fill", tint: Theme.sky, title: tr("App launcher"),
                         place: tr("Apps tab"),
                         keywords: "apps launcher open aplikasi buka", go: tab(.apps)),
            FeatureEntry(id: "shortcuts", icon: "bolt.fill", tint: Theme.butter, title: tr("Apple Shortcuts"),
                         place: tr("Apps tab · right card"),
                         keywords: "shortcuts automation pintasan otomasi", go: tab(.apps)),
            FeatureEntry(id: "battery", icon: "battery.75percent", tint: Theme.mint, title: tr("Battery health and cycles"),
                         place: tr("System tab · left card"),
                         keywords: "battery health cycles charging temperature baterai kesehatan siklus cas suhu", go: tab(.system, spot: "battery")),
            FeatureEntry(id: "network", icon: "wifi", tint: Theme.sky, title: tr("Network speed and Wi-Fi"),
                         place: tr("System tab · middle card"),
                         keywords: "network wifi internet speed jaringan kecepatan sinyal", go: tab(.system, spot: "network")),
            FeatureEntry(id: "cpu", icon: "cpu.fill", tint: Theme.butter, title: tr("CPU, memory and disk"),
                         place: tr("System tab · right card"),
                         keywords: "cpu ram memory disk storage memori penyimpanan", go: tab(.system, spot: "cpu")),
            FeatureEntry(id: "calculator", icon: "plus.forwardslash.minus", tint: Theme.blossom, title: tr("Calculator and unit converter"),
                         place: tr("Tools tab · left card"),
                         keywords: "calculator math convert units kalkulator hitung konversi satuan", go: tab(.tools, spot: "calculator")),
            FeatureEntry(id: "colour", icon: "eyedropper.halffull", tint: Theme.lavender, title: tr("Colour picker"),
                         place: tr("Tools tab · right card"),
                         keywords: "color colour picker hex warna", go: tab(.tools, spot: "colour")),
            FeatureEntry(id: "weather", icon: "cloud.sun.fill", tint: Theme.butter, title: tr("Weather"),
                         place: tr("Home tab · date card"),
                         keywords: "weather temperature cuaca suhu hujan", go: tab(.home, spot: "weather")),
            FeatureEntry(id: "focus-hooks", icon: "moon.fill", tint: Theme.lavender, title: tr("Focus hooks"),
                         place: tr("Settings › Timers"),
                         keywords: "focus do not disturb shortcut fokus jangan ganggu", go: settings("timers")),
            FeatureEntry(id: "keyboard", icon: "keyboard.fill", tint: Theme.text2, title: tr("Keyboard shortcuts"),
                         place: tr("Settings › Keyboard"),
                         keywords: "keyboard shortcut hotkey keys pintasan tombol", go: settings("keyboard")),
            FeatureEntry(id: "look", icon: "paintbrush.fill", tint: Theme.blossom, title: tr("Notch look and live activities"),
                         place: tr("Settings › Appearance"),
                         keywords: "appearance glass style live activity theme tampilan gaya", go: settings("appearance")),
        ]
    }
}

/// All features: a search field and every feature as a tile, so nothing hides behind an icon.
struct FeatureFinder: View {
    let app: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var notch = app.notch
        let list = FeatureCatalog.all.filter { $0.matches(notch.finderQuery) }
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                NotchField(placeholder: tr("Find a feature: battery, water, timer…"), text: $notch.finderQuery, icon: "magnifyingglass") {
                    if let f = list.first { f.go(app) }
                }
                .focused($focused)
                Text(list.count == 1 ? tr("1 feature") : tr("%d features", list.count)).font(Theme.font(10.5, .semibold)).foregroundStyle(Theme.text3).fixedSize()
            }
            if list.isEmpty {
                EmptyState(icon: "magnifyingglass", title: tr("Nothing by that name"), subtitle: tr("Try another word, in English or Indonesian."))
            } else {
                FadingList(spacing: 6) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                        ForEach(list) { f in FeatureTile(app: app, entry: f) }
                    }
                }
            }
        }
        .onAppear {
            if app.notch.focusSearch {
                focused = true
                app.notch.focusSearch = false
            }
        }
    }
}

struct FeatureTile: View {
    let app: AppModel
    let entry: FeatureEntry
    @State private var hovering = false

    var body: some View {
        Button { entry.go(app) } label: {
            HStack(spacing: 9) {
                Image(systemName: entry.icon).font(.system(size: 12, weight: .bold)).foregroundStyle(entry.tint)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(entry.tint.opacity(0.16)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title).font(Theme.font(11.5, .semibold)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.8)
                    Text(entry.place).font(Theme.font(9.5, .medium)).foregroundStyle(Theme.text3).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 42)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(hovering ? 0.10 : 0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(entry.place)
    }
}

/// The grid button in the tab bar: opens All features (and stands in for tabs that don't fit).
struct FinderButton: View {
    let app: AppModel
    var lit = false
    @State private var hovering = false

    var body: some View {
        let on = app.notch.finder || lit
        Button { withAnimation(Theme.fade) { app.toggleFinder() } } label: {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(on ? Theme.blossom : hovering ? Theme.text : Theme.text3)
                .frame(width: TabBar.iconWidth, height: 24)
                .background(Capsule().fill(Color.white.opacity(app.notch.finder ? 0.11 : hovering ? 0.06 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .overlay(alignment: .bottom) { if hovering { TabLabel(text: tr("All features")) } }
        .zIndex(hovering ? 2 : 0)
    }
}

/// Name of a tab icon, shown under it on hover (tooltips don't show in a non-activating panel).
struct TabLabel: View {
    var text: String

    var body: some View {
        Text(text)
            .font(Theme.font(10.5, .semibold)).foregroundStyle(Theme.text)
            .padding(.horizontal, 8).frame(height: 20)
            .background(Capsule().fill(Theme.cardHi))
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            .fixedSize()
            .offset(y: 25)
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}

/// A soft glowing ring around the card the All features page jumped to.
struct Spotlight: ViewModifier {
    let app: AppModel
    let key: String

    func body(content: Content) -> some View {
        let on = app.notch.highlight == key
        content.overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.blossom, lineWidth: on ? 2 : 0)
                .shadow(color: Theme.blossom.opacity(on ? 0.8 : 0), radius: 8)
                .animation(.easeInOut(duration: 0.35), value: on)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    func spotlight(_ app: AppModel, _ key: String) -> some View { modifier(Spotlight(app: app, key: key)) }
}
