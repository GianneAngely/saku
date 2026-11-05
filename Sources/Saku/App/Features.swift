import AppKit

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
    }

    static func installClipboard(_ app: AppModel) {
        // QA never reads or writes the real clipboard: it gets a private pasteboard and no polling.
        let pb = app.options.qa ? NSPasteboard(name: .init("local.saku.qa.\(getpid())")) : .general
        app.clipboard = ClipboardModel(prefs: app.prefs, pasteboard: pb, watch: !app.options.qa)
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
        Render.scenes += MusicChecks.scenes
    }

    static func shutdown(_ app: AppModel) {
        if let clip = app.clipboard {
            if app.prefs.v.clipboardClearOnQuit { clip.clearHistory() }
            clip.saveNow()
            if app.options.qa { clip.pasteboard.releaseGlobally() }
        }
    }
}
