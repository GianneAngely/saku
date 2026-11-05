import AppKit
import SwiftUI

enum PlayerKind: String, Codable, CaseIterable {
    case spotify, music, browser, mock

    var title: String {
        switch self {
        case .spotify: "Spotify"
        case .music: "Music"
        case .browser: tr("Browser")
        case .mock: "Demo"
        }
    }

    var bundleID: String? {
        switch self {
        case .spotify: "com.spotify.client"
        case .music: "com.apple.Music"
        default: nil
        }
    }

    var tint: Color {
        switch self {
        case .spotify: Color(hex: 0x1ED760)
        case .music: Color(hex: 0xFF4E6B)
        case .browser: Theme.sky
        case .mock: Theme.blossom
        }
    }
}

struct Track: Equatable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var duration: Double        // seconds, 0 when unknown (live streams)
    var artworkURL: URL? = nil
}

/// One snapshot of a player.
struct PlayerState: Equatable {
    var kind: PlayerKind
    var track: Track?
    var playing: Bool
    var position: Double
}

/// A player Saku can read and control. Every call is safe when the player is not running: nothing launches it.
@MainActor
protocol MusicPlayer: AnyObject {
    var kind: PlayerKind { get }
    var isRunning: Bool { get }
    /// Pushes state changes (from system notifications) without polling.
    var onChange: ((PlayerState) -> Void)? { get set }
    func refresh(_ done: @escaping @MainActor (PlayerState?) -> Void)
    func playPause()
    func next()
    func previous()
    func seek(to seconds: Double)
    func artwork(for track: Track, _ done: @escaping @MainActor (NSImage?) -> Void)
    func open()
}

extension MusicPlayer {
    var permission: AppleScript.Permission {
        guard let id = kind.bundleID else { return .granted }
        return AppleScript.permission(bundleID: id)
    }
}

// MARK: - Spotify

/// Spotify desktop app. Track changes arrive as distributed notifications (no permission needed);
/// artwork, position and controls go through AppleScript (Automation permission, asked on first use).
@MainActor
final class SpotifyPlayer: MusicPlayer {
    let kind = PlayerKind.spotify
    var onChange: ((PlayerState) -> Void)?
    private var token: NSObjectProtocol?

    init() {
        token = DistributedNotificationCenter.default().addObserver(
            forName: .init("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] n in
            let info = n.userInfo ?? [:]
            MainActor.assumeIsolated {
                if let s = SpotifyPlayer.parse(info) { self?.onChange?(s) }
            }
        }
    }

    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty }

    /// userInfo of com.spotify.client.PlaybackStateChanged.
    nonisolated static func parse(_ info: [AnyHashable: Any]) -> PlayerState? {
        guard let stateText = info["Player State"] as? String else { return nil }
        let playing = stateText == "Playing"
        guard stateText != "Stopped", let name = info["Name"] as? String else {
            return PlayerState(kind: .spotify, track: nil, playing: false, position: 0)
        }
        let durationMS = (info["Duration"] as? NSNumber)?.doubleValue ?? 0
        let track = Track(id: info["Track ID"] as? String ?? name, title: name, artist: info["Artist"] as? String ?? "",
                          album: info["Album"] as? String ?? "", duration: durationMS / 1000)
        let pos = (info["Playback Position"] as? NSNumber)?.doubleValue ?? 0
        return PlayerState(kind: .spotify, track: track, playing: playing, position: pos)
    }

    private func tell(_ body: String, done: (@MainActor (NSAppleEventDescriptor?) -> Void)? = nil) {
        guard isRunning else { done?(nil); return }
        AppleScript.run("if application \"Spotify\" is running then\ntell application \"Spotify\"\n\(body)\nend tell\nend if", done: done)
    }

    func refresh(_ done: @escaping @MainActor (PlayerState?) -> Void) {
        tell("""
        set s to player state as string
        if s is "stopped" then return {"", "", "", 0, 0, s, "", ""}
        set t to current track
        return {name of t, artist of t, album of t, duration of t, player position, s, artwork url of t, id of t}
        """) { d in
            guard let items = d?.items, items.count >= 8 else { done(nil); return }
            let state = items[5].stringValue ?? "stopped"
            guard state != "stopped", let name = items[0].stringValue, !name.isEmpty else {
                done(PlayerState(kind: .spotify, track: nil, playing: false, position: 0))
                return
            }
            let track = Track(id: items[7].stringValue ?? name, title: name, artist: items[1].stringValue ?? "",
                              album: items[2].stringValue ?? "", duration: Double(items[3].int32Value) / 1000,
                              artworkURL: items[6].stringValue.flatMap(URL.init(string:)))
            done(PlayerState(kind: .spotify, track: track, playing: state == "playing", position: items[4].doubleValue))
        }
    }

    func playPause() { tell("playpause") }
    func next() { tell("next track") }
    func previous() { tell("previous track") }
    func seek(to seconds: Double) { tell("set player position to \(max(0, seconds))") }
    func open() { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Spotify.app"), configuration: .init()) }

    func artwork(for track: Track, _ done: @escaping @MainActor (NSImage?) -> Void) {
        let fetch: @MainActor (URL?) -> Void = { url in
            guard let url else { done(nil); return }
            URLSession.shared.dataTask(with: url) { data, _, _ in
                let img = data.flatMap(NSImage.init(data:))
                nonisolated(unsafe) let i = img
                DispatchQueue.main.async { MainActor.assumeIsolated { done(i) } }
            }.resume()
        }
        if let u = track.artworkURL { fetch(u); return }
        tell("return artwork url of current track") { d in fetch(d?.stringValue.flatMap(URL.init(string:))) }
    }
}

// MARK: - Apple Music

/// The Music app. Same idea: com.apple.Music.playerInfo notifications plus AppleScript.
@MainActor
final class AppleMusicPlayer: MusicPlayer {
    let kind = PlayerKind.music
    var onChange: ((PlayerState) -> Void)?
    private var token: NSObjectProtocol?

    init() {
        token = DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] n in
            let info = n.userInfo ?? [:]
            MainActor.assumeIsolated {
                if let s = AppleMusicPlayer.parse(info) { self?.onChange?(s) }
            }
        }
    }

    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty }

    nonisolated static func parse(_ info: [AnyHashable: Any]) -> PlayerState? {
        guard let stateText = info["Player State"] as? String else { return nil }
        guard stateText != "Stopped", let name = info["Name"] as? String ?? info["Display Line 0"] as? String else {
            return PlayerState(kind: .music, track: nil, playing: false, position: 0)
        }
        let total = (info["Total Time"] as? NSNumber)?.doubleValue ?? 0
        let id = (info["PersistentID"] as? NSNumber)?.stringValue ?? info["Persistent ID"] as? String ?? name
        let track = Track(id: id, title: name, artist: info["Artist"] as? String ?? "",
                          album: info["Album"] as? String ?? "", duration: total / 1000)
        return PlayerState(kind: .music, track: track, playing: stateText == "Playing", position: -1)
    }

    private func tell(_ body: String, done: (@MainActor (NSAppleEventDescriptor?) -> Void)? = nil) {
        guard isRunning else { done?(nil); return }
        AppleScript.run("if application \"Music\" is running then\ntell application \"Music\"\n\(body)\nend tell\nend if", done: done)
    }

    func refresh(_ done: @escaping @MainActor (PlayerState?) -> Void) {
        tell("""
        set s to player state as string
        if s is "stopped" then return {"", "", "", 0, 0, s, ""}
        set t to current track
        return {name of t, artist of t, album of t, duration of t, player position, s, persistent ID of t}
        """) { d in
            guard let items = d?.items, items.count >= 7 else { done(nil); return }
            let state = items[5].stringValue ?? "stopped"
            guard state != "stopped", let name = items[0].stringValue, !name.isEmpty else {
                done(PlayerState(kind: .music, track: nil, playing: false, position: 0))
                return
            }
            let track = Track(id: items[6].stringValue ?? name, title: name, artist: items[1].stringValue ?? "",
                              album: items[2].stringValue ?? "", duration: items[3].doubleValue)
            done(PlayerState(kind: .music, track: track, playing: state == "playing", position: items[4].doubleValue))
        }
    }

    func playPause() { tell("playpause") }
    func next() { tell("next track") }
    func previous() { tell("previous track") }
    func seek(to seconds: Double) { tell("set player position to \(max(0, seconds))") }
    func open() { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Music.app"), configuration: .init()) }

    func artwork(for track: Track, _ done: @escaping @MainActor (NSImage?) -> Void) {
        tell("""
        try
        return raw data of artwork 1 of current track
        on error
        return ""
        end try
        """) { d in
            guard let data = d?.data, data.count > 100 else { done(nil); return }
            done(NSImage(data: data))
        }
    }
}

// MARK: - Demo player (QA and previews; never makes a sound)

@MainActor
final class MockPlayer: MusicPlayer {
    let kind = PlayerKind.mock
    var onChange: ((PlayerState) -> Void)?
    var state = PlayerState(kind: .mock, track: Track(id: "demo-1", title: "Sakura Breeze", artist: "Pocket Radio",
                                                      album: "Pixel Dreams", duration: 214), playing: true, position: 84)
    private(set) var log: [String] = []
    let isRunning = true

    func refresh(_ done: @escaping @MainActor (PlayerState?) -> Void) { done(state) }

    func playPause() {
        log.append("playpause")
        state.playing.toggle()
        onChange?(state)
    }

    func next() {
        log.append("next")
        state.track = Track(id: "demo-2", title: "Neon Tanuki", artist: "Pocket Radio", album: "Pixel Dreams", duration: 188)
        state.position = 0
        onChange?(state)
    }

    func previous() {
        log.append("previous")
        state.position = 0
        onChange?(state)
    }

    func seek(to seconds: Double) {
        log.append("seek \(Int(seconds))")
        state.position = seconds
        onChange?(state)
    }

    func open() { log.append("open") }

    func artwork(for track: Track, _ done: @escaping @MainActor (NSImage?) -> Void) { done(Self.demoArtwork()) }

    /// Gradient square with a blossom: stands in for a real album cover.
    static func demoArtwork() -> NSImage {
        NSImage(size: NSSize(width: 300, height: 300), flipped: true) { r in
            let g = NSGradient(colors: [NSColor(red: 1, green: 0.62, blue: 0.78, alpha: 1), NSColor(red: 0.42, green: 0.25, blue: 0.62, alpha: 1)])
            g?.draw(in: r, angle: 60)
            NSColor(white: 1, alpha: 0.9).setFill()
            for i in 0..<5 {
                let a = CGFloat(i) * 2 * .pi / 5 - .pi / 2
                let c = CGPoint(x: r.midX + cos(a) * 46, y: r.midY + sin(a) * 46)
                NSBezierPath(ovalIn: CGRect(x: c.x - 40, y: c.y - 40, width: 80, height: 80)).fill()
            }
            NSColor(red: 1, green: 0.84, blue: 0.42, alpha: 1).setFill()
            NSBezierPath(ovalIn: CGRect(x: r.midX - 22, y: r.midY - 22, width: 44, height: 44)).fill()
            return true
        }
    }
}
