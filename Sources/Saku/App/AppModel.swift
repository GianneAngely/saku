import AppKit
import Observation
import SwiftUI

/// Launch options (command line). QA runs use their own defaults domain and data folder.
struct LaunchOptions {
    var qa = false
    var mute = false
    var mock = false
    var dataDir: String?
    var renderDir: String?
    var selfTest = false
    var liveTest = false
    var iconDir: String?

    static func parse(_ args: [String]) -> LaunchOptions {
        var o = LaunchOptions()
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--qa": o.qa = true
            case "--mute": o.mute = true
            case "--mock": o.mock = true
            case "--data-dir": i += 1; if i < args.count { o.dataDir = args[i] }
            case "--render": i += 1; if i < args.count { o.renderDir = args[i] }
            case "--selftest": o.selfTest = true
            case "--livetest": o.liveTest = true
            case "--make-icon": i += 1; if i < args.count { o.iconDir = args[i] }
            default: break
            }
            i += 1
        }
        if o.renderDir != nil || o.selfTest || o.liveTest || o.iconDir != nil { o.qa = true; o.mute = true; o.mock = true }
        return o
    }
}

/// Everything the notch shows. One instance per app run.
@MainActor @Observable
final class AppModel {
    let options: LaunchOptions
    let prefs: Prefs
    let notch = NotchState()

    // Feature models (created in Features.install).
    var music: MusicModel!
    var timers: TimersModel!
    var tray: TrayModel!
    var clipboard: ClipboardModel!
    var notes: NotesModel!
    var prompter: PrompterModel!
    var calendar: CalendarModel!
    var battery: BatteryModel!
    var monitor: SystemMonitor!
    var trackers: TrackersModel!
    var web: WebModel!
    var bookmarks: BookmarksModel!
    var translate: TranslateModel!

    /// Trackpad scrolling over the open notch (the teleprompter uses it).
    @ObservationIgnored var scrollHandler: ((CGFloat) -> Bool)?

    @ObservationIgnored private var hudClear: DispatchWorkItem?
    @ObservationIgnored private var alertClear: DispatchWorkItem?
    @ObservationIgnored var commands = Commands()

    /// Updated on every minute boundary (date style, "in 8m" texts).
    var clock = Date()

    /// While non-empty the open notch does not close on mouse-out (file pickers, live prompter, recording...).
    var keepOpenReasons: Set<String> = []

    /// Features that accept drops register here (Tray, AirDrop).
    @ObservationIgnored var dropHandlers: [DropZone: @MainActor (DropPayload) -> Void] = [:]

    init(options: LaunchOptions, defaults: UserDefaults) {
        self.options = options
        prefs = Prefs(defaults: defaults)
        if prefs.v.rememberLastTab, let t = Tab(rawValue: prefs.v.lastTab), visibleTabs.contains(t) { notch.tab = t }
        tickClock()
    }

    private func tickClock() {
        clock = Date()
        let next = 60 - Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 60) + 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + next) { [weak self] in MainActor.assumeIsolated { self?.tickClock() } }
    }

    func handleDrop(_ payload: DropPayload, zone: DropZone) {
        guard !payload.isEmpty else { return }
        dropHandlers[zone]?(payload)
        commands.closeNotch()
    }

    /// Springs a compact card out of the notch. A newer alert replaces an older one.
    func present(_ alert: NotchAlert) {
        withAnimation(notch.reduceMotion ? Theme.fade : Theme.openSpring) { notch.alert = alert }
        alertClear?.cancel()
        guard let t = alert.autoDismiss else { return }
        let id = alert.id
        let w = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { if self?.notch.alert?.id == id { self?.dismissAlert() } }
        }
        alertClear = w
        DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: w)
    }

    func dismissAlert() {
        alertClear?.cancel()
        withAnimation(notch.reduceMotion ? Theme.fade : Theme.closeSpring) { notch.alert = nil }
    }

    var visibleTabs: [Tab] {
        let hidden = Set(prefs.v.hiddenTabs)
        let ordered = prefs.v.tabOrder.compactMap(Tab.init(rawValue:)) + Tab.allCases.filter { !prefs.v.tabOrder.contains($0.rawValue) }
        let shown = ordered.filter { Tab.available.contains($0) && ($0 == .home || !hidden.contains($0.rawValue)) }
        return shown.isEmpty ? [.home] : shown
    }

    func select(_ tab: Tab) {
        notch.tab = tab
        if prefs.v.lastTab != tab.rawValue { prefs.v.lastTab = tab.rawValue }
    }

    /// Brief message in the closed notch.
    func flash(_ icon: String, _ text: String, tint: Color = Theme.blossom, seconds: Double = 1.8) {
        let h = NotchHUD(icon: icon, text: text, tint: tint)
        notch.hud = h
        hudClear?.cancel()
        let w = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { if self?.notch.hud?.id == h.id { self?.notch.hud = nil } }
        }
        hudClear = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }

    /// Priority: HUD, then features in order of urgency, then the chosen idle style.
    var liveActivity: LiveActivity {
        if let h = notch.hud { return .hud(h) }
        for entry in liveProviders {
            if let a = entry.provider() { return a }
        }
        switch prefs.v.closedStyle {
        case "date": return .date
        default: break
        }
        if prefs.v.idleMark != "none" { return .mark(prefs.v.idleMark) }
        return .none
    }

    /// Features register closures that return a live activity while they have something to show.
    /// Higher priority wins: timers 100, charging 90, music 50, meetings 40.
    @ObservationIgnored private(set) var liveProviders: [(priority: Int, provider: @MainActor () -> LiveActivity?)] = []

    func addLive(priority: Int, _ provider: @escaping @MainActor () -> LiveActivity?) {
        liveProviders.append((priority, provider))
        liveProviders.sort { $0.priority > $1.priority }
    }

    var closedSize: CGSize {
        let g = notch.geo
        let wing = liveActivity.wing
        return CGSize(width: g.notchW + (wing > 0 ? 2 * (wing + 6) : 0), height: g.notchH)
    }

    var openSize: CGSize {
        if prompter?.live == true { return prompterSize }
        if notch.tab == .web && notch.mode == .open { return CGSize(width: max(prefs.v.openWidth, prefs.v.webWidth), height: max(prefs.v.openHeight, prefs.v.webHeight)) }
        return CGSize(width: prefs.v.openWidth, height: prefs.v.openHeight)
    }

    var prompterSize: CGSize { CGSize(width: prefs.v.prompterWidth, height: notch.geo.notchH + prefs.v.prompterHeight) }

    /// Largest thing the panel ever shows, so the transparent window is created big enough once.
    var maxPanelSize: CGSize {
        CGSize(width: max(prefs.v.openWidth, prefs.v.prompterWidth, prefs.v.webWidth, NotchController.alertSize.width),
               height: max(prefs.v.openHeight, notch.geo.notchH + prefs.v.prompterHeight, prefs.v.webHeight, NotchController.alertSize.height))
    }
}

/// Things views can ask the app shell to do.
struct Commands {
    var openSettings: @MainActor (String?) -> Void = { _ in }
    var openNotch: @MainActor (Tab?) -> Void = { _ in }
    var closeNotch: @MainActor () -> Void = {}
}
