import AppKit

/// Creates the feature models and hooks them into the notch (live activities, drops, alerts).
/// Each feature branch adds its line here.
@MainActor
enum Features {
    static func install(_ app: AppModel) {
        Sound.muted = app.options.mute
        installMusic(app)
        installTimers(app)
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
    }
}
