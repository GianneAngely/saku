import AppKit
import SwiftUI

/// Now-playing card on Home: cover, title, seek bar, controls.
struct MusicCard: View {
    let app: AppModel

    var body: some View {
        let m = app.music!
        let tint = app.prefs.v.musicAlbumTint ? m.tint : Theme.blossom
        let cover = app.prefs.v.musicCoverBackground ? m.backdrop : nil
        Card(padding: 12, fill: cover == nil ? Theme.card : Color.black.opacity(0.45)) {
            if let t = m.track {
                HStack(alignment: .top, spacing: 12) {
                    AlbumArt(image: m.artwork, size: 112, radius: 16, tint: tint)
                        .shadow(color: tint.opacity(m.playing ? 0.45 : 0.15), radius: 14, y: 4)
                        .onTapGesture { m.openPlayer() }
                        .help(tr("Open %@", m.current?.title ?? "Spotify"))
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(t.title).font(Theme.font(14, .bold)).foregroundStyle(Theme.text).lineLimit(1)
                            Spacer(minLength: 4)
                            if let k = m.current { SourceBadge(kind: k) }
                        }
                        Text([t.artist, t.album].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(Theme.font(11.5, .medium)).foregroundStyle(Theme.text2).lineLimit(1)
                        Spacer(minLength: 6)
                        SeekBar(m: m, tint: tint)
                        HStack(spacing: 4) {
                            IconButton(symbol: "backward.fill", size: 13, tint: Theme.text, hit: 30, help: tr("Previous")) { m.previous() }
                            Button { m.playPause() } label: {
                                Image(systemName: m.playing ? "pause.fill" : "play.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Color.black.opacity(0.85))
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(tint))
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help(m.playing ? tr("Pause") : tr("Play"))
                            IconButton(symbol: "forward.fill", size: 13, tint: Theme.text, hit: 30, help: tr("Next")) { m.next() }
                            Spacer(minLength: 0)
                            PermissionChip(app: app)
                            MusicBars(playing: m.playing, tint: tint, paused: !app.notch.isOpen).frame(width: 24, height: 16)
                        }
                        .padding(.top, 4)
                    }
                }
            } else {
                NothingPlaying(app: app)
            }
        }
        .background {
            if let cover {
                GeometryReader { g in
                    Image(nsImage: cover).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                        .frame(width: g.size.width, height: g.size.height)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}

struct SourceBadge: View {
    let kind: PlayerKind
    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(kind.tint).frame(width: 6, height: 6)
            Text(kind.title).font(Theme.font(10, .semibold)).foregroundStyle(Theme.text3)
        }
    }
}

/// Elapsed / remaining with a draggable bar. Ticks once a second, only while playing.
struct SeekBar: View {
    let m: MusicModel
    let tint: Color
    @State private var drag: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let duration = m.track?.duration ?? 0
            let pos = drag.map { $0 * duration } ?? m.position(at: ctx.date)
            VStack(spacing: 3) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(tint).frame(width: max(5, g.size.width * (duration > 0 ? pos / duration : 0)))
                    }
                    .frame(height: drag == nil ? 5 : 7)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in drag = min(1, max(0, v.location.x / g.size.width)) }
                        .onEnded { v in
                            let f = min(1, max(0, v.location.x / g.size.width))
                            if duration > 0 { m.seek(to: f * duration) }
                            drag = nil
                        })
                }
                .frame(height: 12)
                HStack {
                    Text(Self.time(pos)).font(Theme.mono(10, .medium)).foregroundStyle(Theme.text2)
                    Spacer()
                    Text(duration > 0 ? "-" + Self.time(max(0, duration - pos)) : tr("Live")).font(Theme.mono(10, .medium)).foregroundStyle(Theme.text2)
                }
            }
        }
    }

    static func time(_ s: Double) -> String {
        let t = Int(s.rounded(.down))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }
}

/// Shown when the active player still needs the Automation permission.
struct PermissionChip: View {
    let app: AppModel
    var body: some View {
        let m = app.music!
        if let k = m.current, let perm = m.blocked[k] {
            if perm == .denied {
                PillButton(title: tr("Allow in Settings"), icon: "lock.fill", compact: true) { Privacy.open("Privacy_Automation") }
                    .help(tr("Saku is not allowed to control %@. Turn it on in Privacy & Security > Automation.", k.title))
            } else {
                PillButton(title: tr("Enable controls"), icon: "hand.raised.fill", compact: true) { m.connect(k) }
                    .help(tr("macOS asks once whether Saku may control %@.", k.title))
            }
        }
    }
}

struct NothingPlaying: View {
    let app: AppModel
    var body: some View {
        let m = app.music!
        let running = m.players.filter { $0.isRunning && $0.kind != .mock }
        HStack(spacing: 14) {
            AlbumArt(image: nil, size: 92, radius: 16, tint: Theme.blossom).opacity(0.7)
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Nothing playing")).font(Theme.font(14, .bold)).foregroundStyle(Theme.text)
                Text(running.isEmpty ? tr("Play something in Spotify or Music and it shows up here.")
                                     : tr("%@ is open. Press play there, or let Saku connect.", running.map(\.kind.title).joined(separator: ", ")))
                    .font(Theme.font(11.5)).foregroundStyle(Theme.text2).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ForEach(m.players.filter { $0.kind == .spotify || $0.kind == .music }, id: \.kind) { p in
                        if p.isRunning, m.blocked[p.kind] != nil {
                            PillButton(title: tr("Connect %@", p.kind.title), icon: "link", primary: true, tint: p.kind.tint, compact: true) { m.connect(p.kind) }
                        } else {
                            PillButton(title: p.kind.title, icon: "arrow.up.forward.app", compact: true) { p.open() }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }
}

/// Opens a Privacy & Security pane in System Settings.
enum Privacy {
    static func open(_ anchor: String) {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") { NSWorkspace.shared.open(u) }
    }
}

struct MusicPane: View {
    let app: AppModel

    var body: some View {
        @Bindable var prefs = app.prefs
        let m = app.music!
        Form {
            Section {
                Toggle(tr("Show the music card on Home"), isOn: $prefs.v.musicOnHome)
                Toggle(tr("Show cover and bars in the closed notch"), isOn: $prefs.v.musicLiveActivity)
                Toggle(tr("Tuck the closed-notch music away when paused"), isOn: $prefs.v.musicHideWhenPaused)
                    .disabled(!prefs.v.musicLiveActivity)
                Toggle(tr("Colour the bars and buttons from the album cover"), isOn: $prefs.v.musicAlbumTint)
                Toggle(tr("Blurred album cover behind the card"), isOn: $prefs.v.musicCoverBackground)
                Picker(tr("Preferred player"), selection: $prefs.v.musicPreferredPlayer) {
                    Text(tr("Whichever is playing")).tag("auto")
                    Text("Spotify").tag("spotify")
                    Text("Music").tag("music")
                    if Tab.available.contains(.web) || BrowserMusic.isAvailable { Text(tr("Browser")).tag("browser") }
                }
            }
            Section {
                ForEach(m.players.filter { $0.kind == .spotify || $0.kind == .music }, id: \.kind) { p in
                    HStack {
                        Circle().fill(p.kind.tint).frame(width: 8, height: 8)
                        Text(p.kind.title)
                        Spacer()
                        switch p.isRunning ? p.permission : .notRunning {
                        case .granted: Text(tr("Connected")).foregroundStyle(.green)
                        case .denied: Button(tr("Open Privacy settings")) { Privacy.open("Privacy_Automation") }
                        case .notAsked: Button(tr("Connect")) { m.connect(p.kind) }
                        case .notRunning: Text(tr("Not running")).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(tr("Players"))
            } footer: {
                Text(tr("Saku reads Spotify and Music through macOS Automation. macOS asks once per app. Covers come from Spotify and the iTunes Store, no login needed."))
            }
            BrowserMusicSection(app: app)
        }
        .formStyle(.grouped)
    }
}
