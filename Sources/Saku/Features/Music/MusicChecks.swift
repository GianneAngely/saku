import AppKit
import SwiftUI

/// Self-test suite and render scenes for music (demo player only; nothing ever plays).
@MainActor
enum MusicChecks {
    static func run(_ app: AppModel) {
        func check(_ ok: Bool, _ name: String) { SelfTest.check(ok, name) }

        // Spotify notification payload.
        let sp = SpotifyPlayer.parse(["Player State": "Playing", "Name": "Song", "Artist": "Band", "Album": "LP",
                                      "Duration": NSNumber(value: 201_000), "Playback Position": NSNumber(value: 12.5),
                                      "Track ID": "spotify:track:abc"])
        check(sp?.track?.title == "Song" && sp?.track?.duration == 201 && sp?.position == 12.5 && sp?.playing == true, "spotify payload")
        check(sp?.track?.id == "spotify:track:abc", "spotify track id kept for artwork")
        let stopped = SpotifyPlayer.parse(["Player State": "Stopped"])
        check(stopped?.track == nil && stopped?.playing == false, "spotify stopped clears the track")
        check(SpotifyPlayer.parse(["Name": "x"]) == nil, "spotify payload without state is ignored")

        // Music notification payload (no position in it).
        let am = AppleMusicPlayer.parse(["Player State": "Paused", "Name": "Tune", "Artist": "A", "Album": "B",
                                         "Total Time": NSNumber(value: 180_000), "PersistentID": NSNumber(value: 42)])
        check(am?.track?.duration == 180 && am?.playing == false && am?.position == -1 && am?.track?.id == "42", "music payload")

        // AppleScript quoting.
        check(AppleScript.quote("a \"b\" \\c") == "\"a \\\"b\\\" \\\\c\"", "applescript quoting")

        // Demo player drives the model.
        guard let m = app.music, let mock = m.active as? MockPlayer else { check(false, "demo player active"); return }
        check(m.track?.title == "Sakura Breeze" && m.playing, "demo track loaded")
        let p0 = m.position(at: Date())
        check(abs(m.position(at: Date().addingTimeInterval(10)) - (p0 + 10)) < 0.5, "position counts up while playing")
        m.playPause()
        check(!m.playing && mock.log.last == "playpause", "pause reaches the player")
        let frozen = m.position(at: Date())
        check(abs(m.position(at: Date().addingTimeInterval(30)) - frozen) < 0.01, "position holds while paused")
        m.next()
        check(m.track?.title == "Neon Tanuki" && m.position(at: Date()) < 1, "next track")
        m.seek(to: 60)
        check(abs(m.position(at: Date()) - 60) < 0.5 && mock.log.last == "seek 60", "seek")
        check(m.position(at: Date().addingTimeInterval(100_000)) <= (m.track?.duration ?? 0), "position never passes the end")
        m.playPause()
        check(m.playing, "play again")

        // Live activity follows the settings.
        app.prefs.v.closedStyle = "auto"
        app.prefs.v.musicLiveActivity = true
        if case .music = app.liveActivity {} else { check(false, "music shows in the closed notch") }
        app.prefs.v.musicLiveActivity = false
        if case .music = app.liveActivity { check(false, "music live activity can be turned off") }
        app.prefs.v.musicLiveActivity = true
        app.prefs.v.closedStyle = "date"
        check(app.liveActivity == .date, "a fixed closed style wins over music")
        app.prefs.v.closedStyle = "auto"

        // Cover colour: the demo cover is pink/purple, so the tint must be warm and bright.
        let c = NSColor(ArtworkColor.tint(of: MockPlayer.demoArtwork())).usingColorSpace(.sRGB)!
        check(c.brightnessComponent >= 0.8 && c.saturationComponent >= 0.4, "cover tint is bright and saturated")
        let grey = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { r in NSColor.gray.setFill(); r.fill(); return true }
        check(NSColor(ArtworkColor.tint(of: grey)).usingColorSpace(.sRGB)!.saturationComponent < 0.1, "grey cover gives soft white")

        check(SeekBar.time(65) == "1:05" && SeekBar.time(3725) == "1:02:05", "time format")
    }

    static let scenes: [Render.Scene] = [
        Render.Scene(name: "closed-music", settle: 0.5) { _ in },
        Render.Scene(name: "open-home-music", settle: 0.5) { $0.notch.mode = .open; $0.notch.tab = .home },
        Render.Scene(name: "open-home-music-cover", settle: 0.5) {
            $0.notch.mode = .open
            $0.prefs.v.musicCoverBackground = true
        },
        Render.Scene(name: "open-home-music-paused", settle: 0.5) {
            $0.notch.mode = .open
            if $0.music.playing { $0.music.playPause() }
        },
    ]
}
