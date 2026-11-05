import AppKit
import SwiftUI

/// Music playing in a browser tab (YouTube, YouTube Music, SoundCloud, Spotify web...), in Chrome or Safari.
/// Needs "Allow JavaScript from Apple Events" turned on in that browser's Developer menu, and Automation permission.
/// Off by default; polls every 3 s only while turned on and the browser is open.
enum BrowserMusic {
    static var isAvailable: Bool { true }

    static let sites = ["youtube.com", "soundcloud.com", "open.spotify.com", "music.apple.com", "deezer.com", "tidal.com",
                        "music.amazon", "pandora.com", "mixcloud.com", "audiomack.com", "bandcamp.com", "nhaccuatui.com",
                        "joox.com", "anghami.com", "boomplay.com", "qobuz.com", "iheart.com", "gaana.com"]

    /// Reads the page's media element and Media Session metadata as JSON ("" when nothing plays here).
    static let probe = """
    (() => {
      const els = [...document.querySelectorAll('video, audio')];
      if (!els.length) return '';
      const el = els.find(e => !e.paused) || els.find(e => e.currentTime > 0) || els[0];
      const m = navigator.mediaSession && navigator.mediaSession.metadata;
      const art = m && m.artwork && m.artwork.length ? m.artwork[m.artwork.length - 1].src : '';
      return JSON.stringify({
        title: (m && m.title) || document.title,
        artist: (m && m.artist) || location.hostname.replace('www.', ''),
        album: (m && m.album) || '',
        artwork: art,
        playing: !el.paused,
        position: el.currentTime || 0,
        duration: isFinite(el.duration) ? el.duration : 0,
        host: location.hostname
      });
    })()
    """

    static let toggle = """
    (() => { const el = [...document.querySelectorAll('video, audio')].find(e => !e.paused) || document.querySelector('video, audio');
      if (!el) return 'no'; if (el.paused) { el.play(); } else { el.pause(); } return 'ok'; })()
    """

    static func clickFirst(_ selectors: [String], fallback: String) -> String {
        let list = selectors.map { "'" + $0.replacingOccurrences(of: "'", with: "\\'") + "'" }.joined(separator: ", ")
        return "(() => { for (const q of [\(list)]) { const b = document.querySelector(q); if (b) { b.click(); return 'ok'; } } \(fallback) })()"
    }

    static let next = clickFirst(["ytmusic-player-bar .next-button", ".ytp-next-button", ".skipControl__next",
                                  "[data-testid=\"control-button-skip-forward\"]", "button[aria-label*=\"Next\"]"], fallback: "return 'no';")
    static let previous = clickFirst(["ytmusic-player-bar .previous-button", ".ytp-prev-button", ".skipControl__previous",
                                      "[data-testid=\"control-button-skip-back\"]", "button[aria-label*=\"Previous\"]"],
                                     fallback: "const el = document.querySelector('video, audio'); if (el) { el.currentTime = 0; return 'ok'; } return 'no';")

    static func seek(_ s: Double) -> String {
        "(() => { const el = [...document.querySelectorAll('video, audio')].find(e => !e.paused) || document.querySelector('video, audio'); if (!el) return 'no'; el.currentTime = \(max(0, s)); return 'ok'; })()"
    }

    struct Found: Equatable {
        var browser: String          // "chrome" or "safari"
        var window: String
        var tab: String
        var state: PlayerState
        var artwork: URL?
    }

    /// "<window>|<tab>|<json>" from the AppleScript scan.
    static func parse(_ raw: String, browser: String) -> Found? {
        let parts = raw.split(separator: "|", maxSplits: 2).map(String.init)
        guard parts.count == 3, let data = parts[2].data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let title = o["title"] as? String else { return nil }
        let host = o["host"] as? String ?? ""
        let cleanTitle = title.replacingOccurrences(of: " - YouTube Music", with: "").replacingOccurrences(of: " - YouTube", with: "")
        let track = Track(id: host + "|" + cleanTitle, title: cleanTitle, artist: o["artist"] as? String ?? "", album: o["album"] as? String ?? "",
                          duration: o["duration"] as? Double ?? 0, artworkURL: (o["artwork"] as? String).flatMap(URL.init(string:)))
        let state = PlayerState(kind: .browser, track: track, playing: o["playing"] as? Bool ?? false, position: o["position"] as? Double ?? 0)
        return Found(browser: browser, window: parts[0], tab: parts[1], state: state, artwork: track.artworkURL)
    }

    static func siteCondition(_ v: String) -> String {
        sites.map { "\(v) contains \"\($0)\"" }.joined(separator: " or ")
    }

    static func chromeScan() -> String {
        """
        if application "Google Chrome" is running then
        tell application "Google Chrome"
        set out to ""
        repeat with w in windows
        repeat with t in tabs of w
        set u to URL of t
        if \(siteCondition("u")) then
        set r to execute t javascript \(AppleScript.quote(probe))
        if r is not missing value and r is not "" then
        set out to ((id of w) as text) & "|" & ((id of t) as text) & "|" & r
        if r contains "\\"playing\\":true" then return out
        end if
        end if
        end repeat
        end repeat
        return out
        end tell
        end if
        return ""
        """
    }

    static func safariScan() -> String {
        """
        if application "Safari" is running then
        tell application "Safari"
        set out to ""
        repeat with wi from 1 to count of windows
        repeat with ti from 1 to count of tabs of window wi
        set t to tab ti of window wi
        set u to URL of t
        if u is not missing value and (\(siteCondition("u"))) then
        set r to do JavaScript \(AppleScript.quote(probe)) in t
        if r is not missing value and r is not "" then
        set out to (wi as text) & "|" & (ti as text) & "|" & r
        if r contains "\\"playing\\":true" then return out
        end if
        end if
        end repeat
        end repeat
        return out
        end tell
        end if
        return ""
        """
    }

    static func run(_ js: String, in f: Found) -> String {
        if f.browser == "chrome" {
            return "tell application \"Google Chrome\" to execute (tab id \(f.tab) of window id \(f.window)) javascript \(AppleScript.quote(js))"
        }
        return "tell application \"Safari\" to do JavaScript \(AppleScript.quote(js)) in tab \(f.tab) of window \(f.window)"
    }
}

@MainActor
final class BrowserPlayer: MusicPlayer {
    let kind = PlayerKind.browser
    var onChange: ((PlayerState) -> Void)?
    private let prefs: Prefs
    private var timer: Timer?
    private var found: BrowserMusic.Found?
    private var last: PlayerState?

    init(prefs: Prefs) {
        self.prefs = prefs
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.poll() } }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private var browsersOpen: [String] {
        var b: [String] = []
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").isEmpty { b.append("chrome") }
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").isEmpty { b.append("safari") }
        return b
    }

    var isRunning: Bool { prefs.v.musicBrowser && !browsersOpen.isEmpty }

    private func poll() {
        guard isRunning else {
            if last?.track != nil { last = nil; onChange?(PlayerState(kind: .browser, track: nil, playing: false, position: 0)) }
            return
        }
        refresh { [weak self] s in
            guard let self, let s, s != self.last else { return }
            self.last = s
            self.onChange?(s)
        }
    }

    func refresh(_ done: @escaping @MainActor (PlayerState?) -> Void) {
        let open = browsersOpen
        guard prefs.v.musicBrowser, !open.isEmpty else { done(nil); return }
        let scan = open.contains("chrome") ? BrowserMusic.chromeScan() : BrowserMusic.safariScan()
        let browser = open.contains("chrome") ? "chrome" : "safari"
        AppleScript.run(scan) { [weak self] d in
            let raw = d?.stringValue ?? ""
            guard let f = BrowserMusic.parse(raw, browser: browser) else {
                self?.found = nil
                done(PlayerState(kind: .browser, track: nil, playing: false, position: 0))
                return
            }
            self?.found = f
            done(f.state)
        }
    }

    private func send(_ js: String) {
        guard let f = found else { return }
        AppleScript.run(BrowserMusic.run(js, in: f)) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { MainActor.assumeIsolated { self?.poll() } }
        }
    }

    func playPause() { send(BrowserMusic.toggle) }
    func next() { send(BrowserMusic.next) }
    func previous() { send(BrowserMusic.previous) }
    func seek(to seconds: Double) { send(BrowserMusic.seek(seconds)) }

    func open() {
        guard let f = found else { return }
        let script = f.browser == "chrome"
            ? "tell application \"Google Chrome\" to activate\ntell application \"Google Chrome\" to set index of window id \(f.window) to 1"
            : "tell application \"Safari\" to activate"
        AppleScript.run(script)
    }

    func artwork(for track: Track, _ done: @escaping @MainActor (NSImage?) -> Void) {
        guard let u = track.artworkURL, u.scheme?.hasPrefix("http") == true else { done(nil); return }
        URLSession.shared.dataTask(with: u) { data, _, _ in
            let img = data.flatMap(NSImage.init(data:))
            nonisolated(unsafe) let i = img
            DispatchQueue.main.async { MainActor.assumeIsolated { done(i) } }
        }.resume()
    }
}

struct BrowserMusicSection: View {
    let app: AppModel
    var body: some View {
        @Bindable var prefs = app.prefs
        Section {
            Toggle(tr("Show music playing in Chrome or Safari"), isOn: $prefs.v.musicBrowser)
            if prefs.v.musicBrowser {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("One-time setup in your browser:")).bold()
                    Text(tr("Chrome: View > Developer > Allow JavaScript from Apple Events"))
                    Text(tr("Safari: Settings > Advanced > Show features for web developers, then Develop > Allow JavaScript from Apple Events"))
                    Text(tr("macOS then asks once whether Saku may control the browser."))
                }
                .font(.callout).foregroundStyle(.secondary)
            }
        } header: {
            Text(tr("Browser music"))
        } footer: {
            Text(tr("Works with YouTube, YouTube Music, SoundCloud, Spotify web, Apple Music web, Deezer, Tidal and more. Saku only looks at tabs from music sites."))
        }
    }
}
