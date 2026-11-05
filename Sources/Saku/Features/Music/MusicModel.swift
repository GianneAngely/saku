import AppKit
import CoreImage
import Observation
import SwiftUI

/// Now playing across Spotify and Music: picks the active player, keeps artwork, colour and position.
@MainActor @Observable
final class MusicModel {
    private(set) var current: PlayerKind?
    private(set) var track: Track?
    private(set) var playing = false
    private(set) var position = 0.0
    private(set) var positionDate = Date()
    private(set) var artwork: NSImage?
    /// Pre-blurred, darkened cover for the card background (cheaper than a live blur filter).
    private(set) var backdrop: NSImage?
    private(set) var tint: Color = Theme.blossom
    /// True for a few seconds after pausing, so the live activity can tuck away gently.
    private(set) var recentlyActive = false
    /// A running player Saku may not script yet (Automation permission not asked or denied).
    private(set) var blocked: [PlayerKind: AppleScript.Permission] = [:]

    @ObservationIgnored let players: [MusicPlayer]
    @ObservationIgnored private let prefs: Prefs
    @ObservationIgnored private var states: [PlayerKind: PlayerState] = [:]
    @ObservationIgnored private var lastPlayed: [PlayerKind: Date] = [:]
    @ObservationIgnored private var artworkTrackID: String?
    @ObservationIgnored private var hideWork: DispatchWorkItem?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(prefs: Prefs, mock: Bool) {
        self.prefs = prefs
        players = mock ? [MockPlayer()] : [SpotifyPlayer(), AppleMusicPlayer(), BrowserPlayer(prefs: prefs)]
        for p in players {
            p.onChange = { [weak self] s in self?.receive(s) }
        }
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] n in
                let id = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                MainActor.assumeIsolated { self?.appChanged(bundleID: id, launched: name == NSWorkspace.didLaunchApplicationNotification) }
            })
        }
        refreshAllowed()
    }

    func player(_ kind: PlayerKind?) -> MusicPlayer? { players.first { $0.kind == kind } }
    var active: MusicPlayer? { player(current) }

    /// Reads every running player that Saku is already allowed to script. Never shows a permission prompt.
    func refreshAllowed() {
        for p in players where p.isRunning {
            let perm = p.permission
            if perm == .granted {
                blocked[p.kind] = nil
                p.refresh { [weak self] s in if let s { self?.receive(s) } }
            } else {
                blocked[p.kind] = perm
            }
        }
    }

    /// Asks macOS for the Automation permission (shows the prompt once), then reads the player.
    func connect(_ kind: PlayerKind) {
        guard let p = player(kind) else { return }
        p.refresh { [weak self] s in
            guard let self else { return }
            self.blocked[kind] = p.permission == .granted ? nil : p.permission
            if let s { self.receive(s) }
        }
    }

    private func appChanged(bundleID: String?, launched: Bool) {
        guard let kind = PlayerKind.allCases.first(where: { $0.bundleID == bundleID && $0.bundleID != nil }) else { return }
        if !launched {
            states[kind] = nil
            blocked[kind] = nil
            if current == kind { choose() }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in MainActor.assumeIsolated { self?.refreshAllowed() } }
        }
    }

    func receive(_ incoming: PlayerState) {
        var s = incoming
        if s.position < 0 {   // Music notifications carry no position: keep counting, then ask the app if allowed
            if let old = states[s.kind], old.track?.id == s.track?.id {
                s.position = old.playing ? old.position + Date().timeIntervalSince(stateDates[s.kind] ?? Date()) : old.position
            } else {
                s.position = 0
            }
            if let p = player(s.kind), p.permission == .granted {
                p.refresh { [weak self] fresh in
                    if let fresh, fresh.track?.id == s.track?.id, fresh.position >= 0 { self?.receive(fresh) }
                }
            }
        }
        states[s.kind] = s
        stateDates[s.kind] = Date()
        if s.playing { lastPlayed[s.kind] = Date() }
        choose()
    }

    @ObservationIgnored private var stateDates: [PlayerKind: Date] = [:]

    /// Preferred player if it has a track; otherwise whatever plays (latest first); otherwise the latest paused one.
    private func choose() {
        let withTrack = states.values.filter { $0.track != nil }
        var pick: PlayerState?
        if let pref = PlayerKind(rawValue: prefs.v.musicPreferredPlayer), let s = states[pref], s.track != nil { pick = s }
        if pick == nil {
            pick = withTrack.filter(\.playing).max { (lastPlayed[$0.kind] ?? .distantPast) < (lastPlayed[$1.kind] ?? .distantPast) }
        }
        if pick == nil {
            pick = withTrack.max { (lastPlayed[$0.kind] ?? .distantPast) < (lastPlayed[$1.kind] ?? .distantPast) }
        }
        apply(pick)
    }

    private func apply(_ s: PlayerState?) {
        let changed = s?.track?.id != track?.id || s?.kind != current
        current = s?.kind
        track = s?.track
        playing = s?.playing ?? false
        position = s?.position ?? 0
        positionDate = stateDates[s?.kind ?? .mock] ?? Date()
        if changed {
            artwork = nil
            backdrop = nil
            if let t = s?.track, let kind = s?.kind { loadArtwork(t, kind: kind) } else { tint = Theme.blossom }
        }
        hideWork?.cancel()
        if playing {
            recentlyActive = true
        } else if recentlyActive {
            let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.recentlyActive = false } }
            hideWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: w)
        }
    }

    // MARK: Position

    func position(at date: Date) -> Double {
        guard let t = track else { return 0 }
        let p = playing ? position + date.timeIntervalSince(positionDate) : position
        return t.duration > 0 ? min(t.duration, max(0, p)) : max(0, p)
    }

    // MARK: Controls

    func playPause() {
        guard let p = active else { return }
        position = position(at: Date())
        positionDate = Date()
        playing.toggle()   // optimistic; the player's notification confirms
        p.playPause()
    }

    func next() { active?.next() }
    func previous() { active?.previous() }

    func seek(to seconds: Double) {
        guard let p = active else { return }
        position = seconds
        positionDate = Date()
        p.seek(to: seconds)
    }

    func openPlayer() { (active ?? player(.spotify))?.open() }

    // MARK: Artwork

    private func loadArtwork(_ t: Track, kind: PlayerKind) {
        artworkTrackID = t.id
        let finish: @MainActor (NSImage?) -> Void = { [weak self] img in
            guard let self, self.artworkTrackID == t.id else { return }
            self.artwork = img
            self.backdrop = img.flatMap(ArtworkColor.backdrop(of:))
            self.tint = img.map { ArtworkColor.tint(of: $0) } ?? Theme.blossom
        }
        guard let p = player(kind) else { finish(nil); return }
        switch kind {
        case .spotify:
            ArtworkLookup.spotify(trackID: t.id) { img in
                if let img { finish(img) } else if p.permission == .granted { p.artwork(for: t, finish) } else { finish(nil) }
            }
        case .music:
            if p.permission == .granted {
                p.artwork(for: t) { img in
                    if let img { finish(img) } else { ArtworkLookup.itunes(artist: t.artist, title: t.title, done: finish) }
                }
            } else {
                ArtworkLookup.itunes(artist: t.artist, title: t.title, done: finish)
            }
        default:
            p.artwork(for: t, finish)
        }
    }
}

/// Album covers without any login: Spotify's public oEmbed thumbnail and the iTunes Search API.
@MainActor
enum ArtworkLookup {
    static func spotify(trackID: String, done: @escaping @MainActor (NSImage?) -> Void) {
        guard trackID.hasPrefix("spotify:track:"),
              let url = URL(string: "https://open.spotify.com/oembed?url=\(trackID)") else { done(nil); return }
        json(url) { obj in
            guard let s = obj?["thumbnail_url"] as? String, let u = URL(string: s) else { done(nil); return }
            image(u, done: done)
        }
    }

    static func itunes(artist: String, title: String, done: @escaping @MainActor (NSImage?) -> Void) {
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [.init(name: "term", value: "\(artist) \(title)"), .init(name: "entity", value: "song"), .init(name: "limit", value: "1")]
        guard !title.isEmpty, let url = c.url else { done(nil); return }
        json(url) { obj in
            guard let r = (obj?["results"] as? [[String: Any]])?.first, let s = r["artworkUrl100"] as? String,
                  let u = URL(string: s.replacingOccurrences(of: "100x100bb", with: "600x600bb")) else { done(nil); return }
            image(u, done: done)
        }
    }

    private static func json(_ url: URL, done: @escaping @MainActor ([String: Any]?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let obj = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            nonisolated(unsafe) let o = obj
            DispatchQueue.main.async { MainActor.assumeIsolated { done(o) } }
        }.resume()
    }

    private static func image(_ url: URL, done: @escaping @MainActor (NSImage?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let img = data.flatMap(NSImage.init(data:))
            nonisolated(unsafe) let i = img
            DispatchQueue.main.async { MainActor.assumeIsolated { done(i) } }
        }.resume()
    }
}

/// A bright accent taken from a cover: saturated pixels count more, then it is lifted so it glows on black.
enum ArtworkColor {
    /// Small, heavily blurred and darkened copy of the cover.
    static func backdrop(of image: NSImage) -> NSImage? {
        guard let tiff = image.tiffRepresentation, let ci = CIImage(data: tiff) else { return nil }
        let small = ci.transformed(by: CGAffineTransform(scaleX: 96 / max(1, ci.extent.width), y: 96 / max(1, ci.extent.height)))
        let blurred = small.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 9])
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.4, kCIInputBrightnessKey: -0.3])
            .cropped(to: small.extent)
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(blurred, from: small.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: 96, height: 96))
    }

    static func tint(of image: NSImage) -> Color {
        let n = 24
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return Theme.blossom }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: n, height: n))
        NSGraphicsContext.restoreGraphicsState()
        var r = 0.0, g = 0.0, b = 0.0, wsum = 0.0
        for y in 0..<n {
            for x in 0..<n {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let sat = c.saturationComponent, bri = c.brightnessComponent
                let w = 0.05 + sat * sat * bri
                r += c.redComponent * w; g += c.greenComponent * w; b += c.blueComponent * w; wsum += w
            }
        }
        guard wsum > 0 else { return Theme.blossom }
        let avg = NSColor(srgbRed: r / wsum, green: g / wsum, blue: b / wsum, alpha: 1)
        let h = avg.hueComponent
        let s = max(0.42, min(0.85, avg.saturationComponent * 1.25))
        let v = max(0.82, avg.brightnessComponent)
        if avg.saturationComponent < 0.08 { return Color(hex: 0xE8E2EA) }   // grey covers: soft white bars
        return Color(nsColor: NSColor(hue: h, saturation: s, brightness: v, alpha: 1))
    }
}
