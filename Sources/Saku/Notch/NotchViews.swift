import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Notch silhouette: flush with the top edge, rounded bottom corners, outward "ears" at the top corners so the
/// open panel melts into the bezel. The rect includes the ears (content width + 2 * ear).
struct NotchShape: Shape {
    var radius: Double
    var ear: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(radius, ear) }
        set { radius = newValue.first; ear = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        let left = r.minX + ear, right = r.maxX - ear, top = r.minY, bottom = r.maxY
        let rad = max(0, min(radius, (right - left) / 2, bottom - top - ear))
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: top))
        p.addQuadCurve(to: CGPoint(x: left, y: top + ear), control: CGPoint(x: left, y: top))
        p.addLine(to: CGPoint(x: left, y: bottom - rad))
        p.addArc(tangent1End: CGPoint(x: left, y: bottom), tangent2End: CGPoint(x: left + rad, y: bottom), radius: rad)
        p.addLine(to: CGPoint(x: right - rad, y: bottom))
        p.addArc(tangent1End: CGPoint(x: right, y: bottom), tangent2End: CGPoint(x: right, y: bottom - rad), radius: rad)
        p.addLine(to: CGPoint(x: right, y: top + ear))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: top), control: CGPoint(x: right, y: top))
        p.closeSubpath()
        return p
    }
}

struct NotchRootView: View {
    let app: AppModel
    let controller: NotchController?

    var body: some View {
        let s = app.notch
        let open = s.isOpen
        let alert = !open && s.alert != nil
        let live = app.liveActivity
        let size = open ? app.openSize : alert ? NotchController.alertSize : app.closedSize
        let radius = open ? app.prefs.v.cornerRadius : alert ? 26 : 10
        let ear = open || alert ? 10.0 : (live == .none ? 0 : 5)
        let shape = NotchShape(radius: radius, ear: ear)
        let invisible = !open && !alert && live == .none && s.transparentClosed

        ZStack(alignment: .top) {
            Group {
                if app.prefs.v.glassPanel && open {
                    Color.clear.glassEffect(.regular.tint(Color.black.opacity(0.55)), in: shape)
                } else {
                    shape.fill(Color.black)
                }
            }
            .frame(width: size.width + 2 * ear, height: size.height)
            .shadow(color: .black.opacity(open || alert ? 0.5 : 0), radius: 16, y: 6)
            .opacity(invisible ? 0 : 1)

            ZStack(alignment: .top) {
                if open {
                    OpenPanel(app: app)
                        .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.08)),
                                                removal: .opacity.animation(.easeOut(duration: 0.08))))
                } else if let a = s.alert {
                    AlertCard(app: app, alert: a)
                        .id(a.id)
                        .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.1)),
                                                removal: .opacity.animation(.easeOut(duration: 0.1))))
                } else {
                    ClosedWings(app: app, live: live)
                        .transition(.opacity.animation(.easeOut(duration: 0.15)))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(Rectangle())
        }
        .frame(width: size.width + 2 * ear, height: size.height)
        .modifier(LiveClip(shape: shape))
        .background(alignment: .top) {
            shape.fill(Color.black.opacity(open || alert ? 0.001 : 0))   // keeps hit testing inside the shape
                .frame(width: size.width + 2 * ear, height: size.height)
        }
        .animation(open ? Theme.openSpring : Theme.closeSpring, value: size)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }
}

/// Clips the content to the notch while it springs open. Offscreen renders skip it: the content already sits
/// inside the shape at rest, and AppKit's layer snapshot (cacheDisplay) drops SF Symbol tints inside masked layers.
struct LiveClip<S: Shape>: ViewModifier {
    let shape: S
    func body(content: Content) -> some View {
        if Render.active { content } else { content.clipShape(shape) }
    }
}

// MARK: - Closed notch

struct ClosedWings: View {
    let app: AppModel
    let live: LiveActivity

    var body: some View {
        let g = app.notch.geo
        let wing = live.wing + 6
        HStack(spacing: 0) {
            left.frame(width: wing)
            Color.clear.frame(width: g.notchW)
            right.frame(width: wing)
        }
        .frame(height: g.notchH)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder private var left: some View {
        switch live {
        case .none: EmptyView()
        case .mark(let m):
            if m == "mascot" && AppResources.mascot != nil {
                MascotTile(size: 20)
            } else if let mark = AppResources.mark {
                Image(nsImage: mark).resizable().interpolation(.high).frame(width: 19, height: 19)
            } else {
                BlossomMark(size: 15)
            }
        case .date:
            Text(dateText).font(Theme.font(12, .semibold)).foregroundStyle(Color(hexString: app.prefs.v.dateColor) ?? Theme.text)
        case .hud(let h):
            Image(systemName: h.icon).font(.system(size: 12, weight: .bold)).foregroundStyle(h.tint)
        case .music(let art, _, let tint):
            AlbumArt(image: art, size: 22, radius: 6, tint: tint)
        case .timer(let d):
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                TimerRing(progress: d.progress(at: ctx.date), tint: d.tint, icon: d.running ? d.icon : "pause.fill", line: 2.5)
                    .frame(width: 19, height: 19)
            }
        case .charging(_, let charging):
            Image(systemName: charging ? "bolt.fill" : "powerplug.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.mint)
        case .meeting:
            Image(systemName: "calendar").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.blossom)
        }
    }

    @ViewBuilder private var right: some View {
        switch live {
        case .none, .mark: EmptyView()
        case .date:
            Text(timeText).font(Theme.mono(12, .semibold)).foregroundStyle(Color(hexString: app.prefs.v.timeColor) ?? Theme.blossom)
        case .hud(let h):
            Text(h.text).font(Theme.font(11.5, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
        case .music(_, let playing, let tint):
            MusicBars(playing: playing, tint: tint, paused: app.notch.hidden).frame(width: 22, height: 14)
        case .timer(let d):
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(d.text(at: ctx.date)).font(Theme.mono(12.5, .bold)).foregroundStyle(d.running ? d.tint : Theme.text2)
            }
        case .charging(let level, _):
            Text("\(level)%").font(Theme.mono(12, .bold)).foregroundStyle(Theme.mint)
        case .meeting(let text):
            Text(text).font(Theme.font(11.5, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
        }
    }

    private var dateText: String {
        let f = DateFormatter()
        f.locale = Lang.shared.isIndonesian ? Locale(identifier: "id_ID") : Locale(identifier: "en_US")
        f.setLocalizedDateFormatFromTemplate("EEEd")
        return f.string(from: app.clock)
    }

    private var timeText: String {
        let f = DateFormatter()
        f.dateFormat = app.prefs.v.use24Hour ? "HH:mm" : "h:mm"
        return f.string(from: app.clock)
    }
}

/// Progress ring with a small symbol in the middle.
struct TimerRing: View {
    var progress: Double
    var tint: Color
    var icon: String? = nil
    var line: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.22), lineWidth: line)
            Circle().trim(from: 0, to: max(0.001, progress))
                .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let icon {
                GeometryReader { g in
                    Image(systemName: icon).font(.system(size: g.size.width * 0.42, weight: .bold)).foregroundStyle(tint)
                        .frame(width: g.size.width, height: g.size.height)
                }
            }
        }
    }
}

/// Saku's blossom mark: five round petals.
struct BlossomMark: View {
    var size: CGFloat = 14
    var color: Color = Theme.blossom

    var body: some View {
        ZStack {
            ForEach(0..<5) { i in
                Ellipse().fill(color)
                    .frame(width: size * 0.42, height: size * 0.56)
                    .offset(y: -size * 0.26)
                    .rotationEffect(.degrees(Double(i) * 72))
            }
            Circle().fill(Theme.butter).frame(width: size * 0.22, height: size * 0.22)
        }
        .frame(width: size, height: size)
    }
}

/// Album cover with a soft placeholder.
struct AlbumArt: View {
    var image: NSImage?
    var size: CGFloat
    var radius: CGFloat
    var tint: Color = Theme.blossom

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [tint.opacity(0.55), Theme.cardHi], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note").font(.system(size: size * 0.4, weight: .bold)).foregroundStyle(Color.white.opacity(0.8))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Four bouncing bars. Animates at 24 fps only while playing; still bars when paused.
/// Four bouncing bars. The bounce runs as Core Animation in the window server, so playing music costs the app
/// almost no CPU; paused (or hidden) shows still, short bars.
struct MusicBars: View {
    var playing: Bool
    var tint: Color
    var paused = false

    var body: some View {
        if Render.active {
            StillBars(tint: tint, levels: playing ? [0.55, 0.9, 0.4, 0.75] : [0.22, 0.22, 0.22, 0.22])
        } else {
            BarsLayer(playing: playing && !paused, color: NSColor(tint))
        }
    }
}

/// Same bars drawn once (offscreen pictures, where layer animations don't show).
struct StillBars: View {
    var tint: Color
    var levels: [Double]

    var body: some View {
        Canvas { c, size in
            let n = levels.count, gap = 2.5
            let w = (size.width - gap * Double(n - 1)) / Double(n)
            for (i, level) in levels.enumerated() {
                let h = max(3, size.height * level)
                let r = CGRect(x: Double(i) * (w + gap), y: (size.height - h) / 2, width: w, height: h)
                c.fill(Path(roundedRect: r, cornerRadius: w / 2), with: .color(tint))
            }
        }
    }
}

struct BarsLayer: NSViewRepresentable {
    var playing: Bool
    var color: NSColor

    func makeNSView(context: Context) -> BarsView { BarsView() }

    func updateNSView(_ v: BarsView, context: Context) {
        v.color = color
        v.playing = playing
    }

    final class BarsView: NSView {
        private var bars: [CALayer] = []
        var color: NSColor = .systemPink { didSet { if color != oldValue { bars.forEach { $0.backgroundColor = color.cgColor } } } }
        var playing = false { didSet { if playing != oldValue { restart() } } }

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            for _ in 0..<4 {
                let b = CALayer()
                b.backgroundColor = color.cgColor
                layer?.addSublayer(b)
                bars.append(b)
            }
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            let gap = 2.5, n = Double(bars.count)
            let w = (bounds.width - gap * (n - 1)) / n
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (i, b) in bars.enumerated() {
                b.bounds = CGRect(x: 0, y: 0, width: w, height: bounds.height)
                b.position = CGPoint(x: Double(i) * (w + gap) + w / 2, y: bounds.midY)
                b.cornerRadius = w / 2
                if !playing { b.transform = CATransform3DMakeScale(1, 0.22, 1) }
            }
            CATransaction.commit()
            restart()
        }

        private func restart() {
            let durations = [0.62, 0.48, 0.71, 0.55]
            let shapes: [[Double]] = [[0.3, 1, 0.45, 0.85, 0.3], [0.8, 0.35, 1, 0.5, 0.8], [0.45, 0.75, 0.3, 1, 0.45], [1, 0.4, 0.7, 0.35, 1]]
            for (i, b) in bars.enumerated() {
                b.removeAllAnimations()
                if playing {
                    let a = CAKeyframeAnimation(keyPath: "transform.scale.y")
                    a.values = shapes[i]
                    a.duration = durations[i] * 1.6
                    a.repeatCount = .infinity
                    a.calculationMode = .cubic
                    a.isRemovedOnCompletion = false
                    b.transform = CATransform3DIdentity
                    b.add(a, forKey: "bounce")
                } else {
                    CATransaction.begin()
                    CATransaction.setAnimationDuration(0.25)
                    b.transform = CATransform3DMakeScale(1, 0.22, 1)
                    CATransaction.commit()
                }
            }
        }
    }
}

// MARK: - Open notch

struct OpenPanel: View {
    let app: AppModel

    var body: some View {
        if app.prompter?.live == true {
            PrompterStage(app: app)
                .frame(width: app.openSize.width, height: app.openSize.height)
        } else {
            panel
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            TabBar(app: app).zIndex(1)
            Group {
                if app.notch.mode == .drop {
                    DropTargets(app: app)
                } else if app.notch.finder {
                    FeatureFinder(app: app)
                        .transition(.opacity.animation(Theme.fade))
                } else {
                    TabContent(app: app, tab: app.notch.tab)
                        .id(app.notch.tab)
                        .transition(.opacity.animation(Theme.fade))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
        .frame(width: app.openSize.width, height: app.openSize.height)
    }
}

struct TabBar: View {
    let app: AppModel

    /// How the visible tabs split around the camera; extra tabs go into a "more" menu when they don't fit.
    struct Layout: Equatable {
        var left: [Tab]
        var right: [Tab]
        var more: [Tab]
    }

    static let iconWidth = 27.0
    static let toolsWidth = 87.0       // All features, divider, pin and settings on the right

    static func layout(tabs: [Tab], panelWidth: Double, notchWidth: Double) -> Layout {
        let side = (panelWidth - notchWidth - 20 - 32) / 2
        let capL = max(1, Int(side / iconWidth))
        let capR = max(0, Int((side - toolsWidth) / iconWidth))
        if tabs.count <= capL + capR {
            let half = min(capL, (tabs.count + 1) / 2)
            return Layout(left: Array(tabs.prefix(half)), right: Array(tabs.dropFirst(half)), more: [])
        }
        return Layout(left: Array(tabs.prefix(capL)), right: Array(tabs.dropFirst(capL).prefix(capR)),
                      more: Array(tabs.dropFirst(capL + capR)))
    }

    var body: some View {
        let l = Self.layout(tabs: app.visibleTabs, panelWidth: app.openSize.width, notchWidth: app.notch.geo.notchW)
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(l.left) { TabIcon(app: app, tab: $0) }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            Color.clear.frame(width: app.notch.geo.notchW + 20)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                ForEach(l.right) { TabIcon(app: app, tab: $0) }
                FinderButton(app: app, lit: l.more.contains(app.notch.tab) && app.notch.mode == .open)
                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 14).padding(.horizontal, 5)
                IconButton(symbol: app.notch.pinned ? "pin.fill" : "pin", size: 11.5,
                           tint: app.notch.pinned ? Theme.blossom : Theme.text3, hit: 24, help: tr("Keep open")) {
                    app.notch.pinned.toggle()
                }
                IconButton(symbol: "gearshape.fill", size: 12, tint: Theme.text3, hit: 24, help: tr("Settings")) {
                    app.commands.openSettings(nil)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .frame(height: app.notch.geo.notchH)
    }
}

struct TabIcon: View {
    let app: AppModel
    let tab: Tab
    @State private var hovering = false

    var body: some View {
        let on = app.notch.tab == tab && app.notch.mode == .open && !app.notch.finder
        Button { withAnimation(Theme.fade) { app.select(tab) } } label: {
            Image(systemName: tab.icon)
                .font(.system(size: 12.5, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(on ? Theme.blossom : hovering ? Theme.text : Theme.text3)
                .frame(width: TabBar.iconWidth, height: 24)
                .background(Capsule().fill(Color.white.opacity(on ? 0.11 : hovering ? 0.06 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .overlay(alignment: .bottom) { if hovering { TabLabel(text: tab.title) } }
        .zIndex(hovering ? 2 : 0)
    }
}

/// Shown while something is dragged near the notch.
struct DropTargets: View {
    let app: AppModel

    var body: some View {
        HStack(spacing: 10) {
            if app.dropHandlers[.tray] != nil {
                DropTile(app: app, zone: .tray, icon: "tray.and.arrow.down.fill", title: tr("Keep in Tray"),
                         subtitle: tr("Files, links, text and images"), tint: Theme.blossom)
            }
            if app.dropHandlers[.airdrop] != nil && app.prefs.v.airdropZone {
                DropTile(app: app, zone: .airdrop, icon: "airplayaudio", title: tr("AirDrop"),
                         subtitle: tr("Share files with a nearby device"), tint: Theme.sky)
            }
        }
    }
}

struct DropTile: View {
    let app: AppModel
    let zone: DropZone
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: zone == .airdrop ? "dot.radiowaves.left.and.right" : icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(tint)
                .scaleEffect(targeted ? 1.15 : 1)
            Text(title).font(Theme.font(13, .bold)).foregroundStyle(Theme.text)
            Text(subtitle).font(Theme.font(10.5)).foregroundStyle(Theme.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tint.opacity(targeted ? 0.18 : 0.06)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(tint.opacity(targeted ? 0.9 : 0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
        .animation(Theme.fade, value: targeted)
        .onDrop(of: [.fileURL, .url, .plainText, .image], isTargeted: $targeted) { providers in
            DropReader.read(providers) { payload in app.handleDrop(payload, zone: zone) }
            return true
        }
        .onChange(of: targeted) { _, on in if on { app.notch.dropTarget = zone } else if app.notch.dropTarget == zone { app.notch.dropTarget = nil } }
    }
}

/// What came in with a drop.
struct DropPayload {
    var files: [URL] = []
    var links: [URL] = []
    var texts: [String] = []
    var images: [Data] = []
    var isEmpty: Bool { files.isEmpty && links.isEmpty && texts.isEmpty && images.isEmpty }
}

enum DropReader {
    /// Loads every provider, then calls back once on the main thread.
    static func read(_ providers: [NSItemProvider], done: @escaping @MainActor (DropPayload) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        nonisolated(unsafe) var out = DropPayload()
        for p in providers {
            group.enter()
            if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { lock.withLock { out.files.append(url) } }
                    group.leave()
                }
            } else if p.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { lock.withLock { out.links.append(url) } }
                    group.leave()
                }
            } else if p.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    if let data { lock.withLock { out.images.append(data) } }
                    group.leave()
                }
            } else if p.canLoadObject(ofClass: String.self) {
                _ = p.loadObject(ofClass: String.self) { s, _ in
                    if let s { lock.withLock { out.texts.append(s) } }
                    group.leave()
                }
            } else {
                group.leave()
            }
        }
        group.notify(queue: .main) { MainActor.assumeIsolated { done(out) } }
    }
}

// MARK: - Alert card

/// Left side of an alert: your mascot picture when there is one, else Saku's clay sakura on a soft tile
/// (or the alert's own symbol if the picture is missing).
struct AlertBadge: View {
    let alert: NotchAlert
    var size: CGFloat = 70

    var body: some View {
        if AppResources.mascot != nil {
            MascotTile(size: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x3A2466), Color(hex: 0x5E2B6A)], startPoint: .top, endPoint: .bottom))
                .overlay {
                    if let mark = AppResources.mark {
                        Image(nsImage: mark).resizable().interpolation(.high).padding(size * 0.12)
                    } else {
                        Image(systemName: alert.icon).font(.system(size: size * 0.4, weight: .bold)).foregroundStyle(alert.tint)
                    }
                }
                .frame(width: size, height: size)
        }
    }
}

struct AlertCard: View {
    let app: AppModel
    let alert: NotchAlert
    @State private var pop = false

    var body: some View {
        HStack(spacing: 14) {
            AlertBadge(alert: alert)
                .scaleEffect(pop ? 1 : 0.6)
                .offset(y: pop ? 0 : 8)
                .animation(app.notch.reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.55).delay(0.12), value: pop)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: alert.icon).font(.system(size: 11, weight: .bold)).foregroundStyle(alert.tint)
                    Text(alert.title).font(Theme.font(15, .heavy)).foregroundStyle(Theme.text).lineLimit(1)
                }
                if !alert.subtitle.isEmpty {
                    Text(alert.subtitle).font(Theme.font(11.5, .medium)).foregroundStyle(Theme.text2).lineLimit(2)
                }
                if !alert.actions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(alert.actions) { a in
                            PillButton(title: a.title, primary: a.primary, tint: alert.tint, compact: true) {
                                app.dismissAlert()
                                a.run()
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .padding(.top, app.notch.geo.notchH - 6)
        .frame(width: NotchController.alertSize.width, height: NotchController.alertSize.height, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            IconButton(symbol: "xmark", size: 9, tint: Theme.text3, hit: 22) { app.dismissAlert() }
                .padding(.top, app.notch.geo.notchH - 4)
                .padding(.trailing, 12)
        }
        .onAppear { pop = true }
    }
}
