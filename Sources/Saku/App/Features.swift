import AppKit
import Observation

/// Creates the feature models and hooks them into the notch (live activities, drops, alerts).
/// Each feature branch adds its line here.
@MainActor
enum Features {
    static func install(_ app: AppModel) {
        Sound.muted = app.options.mute
        installMusic(app)
        installTimers(app)
        installTray(app)
        installAirDrop(app)
        installClipboard(app)
        installNotes(app)
        installPrompter(app)
        installCalendar(app)
        installBattery(app)
        app.monitor = SystemMonitor()
        SelfTest.suites.append(("system", SystemChecks.run))
        installTrackers(app)
        installWeb(app)
        Secrets.inMemory = app.options.qa
        app.translate = TranslateModel(prefs: app.prefs)
        app.ai = AIModel(app: app)
        app.mirror = MirrorModel(prefs: app.prefs)
        app.launcher = LauncherModel()
        app.shortcuts = ShortcutsModel(prefs: app.prefs)
        // Focus hooks: run a chosen Shortcut when focus starts or ends (Do Not Disturb, music, lights...).
        app.timers.onPhaseStart.append { [weak app] phase in
            guard let app, phase == .focus, !app.prefs.v.focusStartShortcut.isEmpty else { return }
            app.shortcuts.run(app.prefs.v.focusStartShortcut)
        }
        app.timers.onPhaseEnd.append { [weak app] phase in
            guard let app, phase == .focus, !app.prefs.v.focusEndShortcut.isEmpty else { return }
            app.shortcuts.run(app.prefs.v.focusEndShortcut)
        }
        installHotkeys(app)
        app.tools = ToolsModel()
        app.colors = ColorPickerModel()
        app.weather = WeatherModel(prefs: app.prefs, live: !app.options.qa)
        SelfTest.suites.append(("weather", WeatherChecks.run))
        SelfTest.suites.append(("ocr", OCRChecks.run))
        app.eyeBreaks = EyeBreaks(app: app)
        if !app.options.qa { app.eyeBreaks.start() }
        SelfTest.suites.append(("eye breaks", EyeBreakChecks.run))
        SelfTest.suites.append(("focus hooks", FocusHookChecks.run))
        SelfTest.suites.append(("calculator", CalculatorChecks.run))
        Render.scenes += CalculatorChecks.scenes
        SelfTest.suites.append(("apps", AppsChecks.run))
        Render.scenes += AppsChecks.scenes
        // The camera never keeps running behind a closed notch.
        observe(app, { _ = $0.notch.mode }) { if $0.notch.mode == .closed { $0.mirror.stop() } }
        SelfTest.suites.append(("mirror", MirrorChecks.run))
        Render.scenes += MirrorChecks.scenes
        SelfTest.suites.append(("ai", AIChecks.run))
        Render.scenes += AIChecks.scenes
        SelfTest.suites.append(("translate", TranslateChecks.run))
        Render.scenes += TranslateChecks.scenes
        SelfTest.suites.append(("finder", FinderChecks.run))
        Render.scenes += FinderChecks.scenes
        LiveTest.steps.append(("all features", FinderChecks.live))
    }

    static func installWeb(_ app: AppModel) {
        app.web = WebModel(prefs: app.prefs)
        app.bookmarks = BookmarksModel()
        SelfTest.suites.append(("web", WebChecks.run))
        Render.scenes += WebChecks.scenes
        LiveTest.steps.append(("web", WebChecks.live))
    }

    static func installTrackers(_ app: AppModel) {
        app.trackers = TrackersModel(app: app)
        app.trackers.scheduleWaterReminder()
        observe(app, { _ = $0.prefs.v.waterReminder }) { $0.trackers.scheduleWaterReminder() }
        SelfTest.suites.append(("trackers", TrackerChecks.run))
        Render.scenes += TrackerChecks.scenes
    }

    static func installBattery(_ app: AppModel) {
        app.battery = BatteryModel(app: app, live: !app.options.mock)
        if app.options.mock {
            app.battery.apply(BatteryInfo(present: true, level: 76, charging: false, onAC: false, minutesToEmpty: 312,
                                          health: 88, cycles: 113, temperature: 31.5))
        }
        app.addLive(priority: 90) { [weak app] in
            guard let app, app.prefs.v.batteryInNotch != "always" else { return nil }
            return app.battery.liveActivity()
        }
        app.addLive(priority: 5) { [weak app] in
            guard let app, app.prefs.v.batteryInNotch == "always", app.prefs.v.closedStyle == "auto" else { return nil }
            return app.battery.liveActivity()
        }
        SelfTest.suites.append(("battery", BatteryChecks.run))
        Render.scenes += BatteryChecks.scenes
    }

    static func installCalendar(_ app: AppModel) {
        // QA runs start "already set up" so a demo Google account doesn't flash "Connected" into every test and picture.
        if app.options.qa { app.prefs.v.googleAutoPicked = true }
        let source: CalendarSource = app.options.mock ? DemoCalendarSource(now: Date()) : EventKitSource()
        app.calendar = CalendarModel(app: app, source: source)
        app.addLive(priority: 40) { [weak app] in
            guard let app, let m = app.calendar, app.prefs.v.meetingHeadsUp, app.prefs.v.closedStyle == "auto" else { return nil }
            let now = app.options.mock ? m.now : app.clock
            guard let e = CalendarModel.nextMeeting(m.upcoming, now: now, lead: app.prefs.v.meetingLead) else { return nil }
            return .meeting(text: CalendarModel.countdownText(to: e.start, now: now))
        }
        let t = Timer(timeInterval: 600, repeats: true) { [weak app] _ in MainActor.assumeIsolated { app?.calendar.reload() } }
        RunLoop.main.add(t, forMode: .common)
        // Accounts added while Saku runs (Google in System Settings) show up without a restart.
        observe(app, { _ = ($0.notch.mode, $0.notch.tab) }) { a in
            if a.notch.mode == .open && a.notch.tab == .calendar { a.calendar.refreshSources() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak app] _ in
            MainActor.assumeIsolated { app?.calendar.refreshSources() }
        }
        SelfTest.suites.append(("calendar", CalendarChecks.run))
        Render.scenes += CalendarChecks.scenes
    }

    static func installPrompter(_ app: AppModel) {
        app.prompter = PrompterModel(app: app)
        app.scrollHandler = { [weak app] dy in
            guard let m = app?.prompter, m.live else { return false }
            m.nudge(-dy)
            return true
        }
        SelfTest.suites.append(("prompter", PrompterChecks.run))
        Render.scenes += PrompterChecks.scenes
        LiveTest.steps.append(("prompter", PrompterChecks.live))
    }

    static func installNotes(_ app: AppModel) {
        app.notes = NotesModel()
        SelfTest.suites.append(("notes", NotesChecks.run))
        Render.scenes += NotesChecks.scenes
    }

    static func installClipboard(_ app: AppModel) {
        // QA never reads or writes the real clipboard: it gets a private pasteboard and no polling.
        let pb = app.options.qa ? NSPasteboard(name: .init("local.saku.qa.\(getpid())")) : .general
        app.clipboard = ClipboardModel(prefs: app.prefs, pasteboard: pb, watch: !app.options.qa || app.options.soak != nil)
        SelfTest.suites.append(("clipboard", ClipboardChecks.run))
        Render.scenes += ClipboardChecks.scenes
    }

    static func installAirDrop(_ app: AppModel) {
        app.dropHandlers[.airdrop] = { payload in
            if !AirDrop.send(payload) { app.flash("exclamationmark.triangle.fill", tr("AirDrop takes files only"), tint: Theme.butter) }
        }
        SelfTest.suites.append(("airdrop", AirDropChecks.run))
    }

    static func installTray(_ app: AppModel) {
        app.tray = TrayModel(prefs: app.prefs)
        app.dropHandlers[.tray] = { [weak app] payload in
            guard let app else { return }
            let n = app.tray.add(payload)
            guard n > 0 else { return }
            if app.prefs.v.trayOpenAfterDrop {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { MainActor.assumeIsolated { app.commands.openNotch(.tray) } }
            } else {
                app.flash("tray.and.arrow.down.fill", tr("Added %d to Tray", n))
            }
        }
        SelfTest.suites.append(("tray", TrayChecks.run))
        Render.scenes += TrayChecks.scenes
    }

    static func installTimers(_ app: AppModel) {
        app.timers = TimersModel(app: app)
        app.addLive(priority: 100) { [weak app] in
            app?.timers.liveDisplay().map { .timer($0) }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak app] _ in
            MainActor.assumeIsolated { app?.timers.check() }
        }
        SelfTest.suites.append(("timers", TimerChecks.run))
        Render.scenes += TimerChecks.scenes
    }

    static func installMusic(_ app: AppModel) {
        app.music = MusicModel(prefs: app.prefs, mock: app.options.mock)
        app.addLive(priority: 50) { [weak app] in
            guard let app, let m = app.music, m.track != nil, app.prefs.v.musicLiveActivity else { return nil }
            let style = app.prefs.v.closedStyle
            guard style == "auto" || style == "waveform" else { return nil }
            guard m.playing || style == "waveform" || !app.prefs.v.musicHideWhenPaused || m.recentlyActive else { return nil }
            return .music(artwork: m.artwork, playing: m.playing, tint: app.prefs.v.musicAlbumTint ? m.tint : Theme.blossom)
        }
        SelfTest.suites.append(("music", MusicChecks.run))
        LiveTest.steps.append(("browser music", BrowserMusicLive.run))
        Render.scenes += MusicChecks.scenes
    }

    static func installHotkeys(_ app: AppModel) {
        let h = HotkeyCenter(prefs: app.prefs)
        app.hotkeys = h
        h.perform = { [weak app] a in
            guard let app else { return }
            switch a {
            case .toggle: app.commands.toggleNotch(nil, false)
            case .features:
                if app.notch.mode == .open && app.notch.finder { app.commands.closeNotch(); return }
                if app.notch.mode != .open { app.commands.toggleNotch(nil, true) }
                app.notch.finder = true
                app.notch.focusSearch = true
            case .pomodoro:
                app.timers.pomoToggle()
                app.flash(app.timers.pomo.running ? "play.fill" : "pause.fill",
                          app.timers.pomo.running ? tr("Focus started") : tr("Focus paused"), tint: Theme.butter)
            case .prompterPlay:
                if app.prompter.live { app.prompter.togglePlay() } else { app.prompter.start() }
            case .prompterFaster: app.prompter.setSpeed(app.prefs.v.prompterSpeed + 10)
            case .prompterSlower: app.prompter.setSpeed(app.prefs.v.prompterSpeed - 10)
            case .prompterBack: app.prompter.back()
            case .pin:
                if app.notch.mode != .open { app.commands.toggleNotch(nil, false) }
                app.notch.pinned.toggle()
            default:
                guard let t = a.tab, Tab.available.contains(t) else { return }
                app.commands.toggleNotch(t, [.clipboard, .apps, .ai, .tools].contains(t))
            }
        }
        if !app.options.qa { h.apply() }
        observe(app, { _ = $0.prompter.live }) { $0.hotkeys.reading = $0.prompter.live }
        SelfTest.suites.append(("keyboard", KeyboardChecks.run))
    }

    /// Calls `action` every time something read in `track` changes (Observation, re-armed after each change).
    static func observe(_ app: AppModel, _ track: @escaping @MainActor (AppModel) -> Void, _ action: @escaping @MainActor (AppModel) -> Void) {
        withObservationTracking { track(app) } onChange: { [weak app] in
            DispatchQueue.main.async {
                guard let app else { return }
                action(app)
                observe(app, track, action)
            }
        }
    }

    static func shutdown(_ app: AppModel) {
        app.hotkeys?.unregisterAll()
        app.notes?.saveNow()
        app.trackers?.saveNow()
        app.prompter?.stopVoice()
        app.prompter?.saveNow()
        if let clip = app.clipboard {
            if app.prefs.v.clipboardClearOnQuit { clip.clearHistory() }
            clip.saveNow()
            if app.options.qa { clip.pasteboard.releaseGlobally() }
        }
    }
}
