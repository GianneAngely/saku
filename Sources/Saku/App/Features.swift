import AppKit

/// Creates the feature models and hooks them into the notch (live activities, drops, alerts).
/// Each feature branch adds its line here.
@MainActor
enum Features {
    static func install(_ app: AppModel) {
        installMusic(app)
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
