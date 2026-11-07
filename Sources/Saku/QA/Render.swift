import AppKit
import SwiftUI

/// `Saku --render DIR`: draws the notch in every scripted state into PNGs (2x), offscreen.
/// Nothing is shown on screen; the notch sits on a fake menu bar at its real measured position.
@MainActor
enum Render {
    struct Scene {
        var name: String
        var settle: Double = 0.25
        var setup: @MainActor (AppModel) -> Void
    }

    /// Feature branches append their scenes here (see Features.install).
    static var scenes: [Scene] = [
        Scene(name: "closed-plain") { _ in },
        Scene(name: "closed-date") { $0.prefs.v.closedStyle = "date" },
        Scene(name: "closed-blossom") { $0.prefs.v.idleMark = "blossom" },
        Scene(name: "closed-hud") { $0.notch.hud = NotchHUD(icon: "checkmark.circle.fill", text: "Copied", tint: Theme.mint) },
        Scene(name: "open-home") { $0.notch.mode = .open; $0.notch.tab = .home },
        Scene(name: "alert", settle: 0.9) {
            $0.notch.alert = NotchAlert(title: "Focus done!", subtitle: "Nice work. Take a 5 minute break.", icon: "timer",
                                        tint: Theme.butter, actions: [AlertAction(title: "Start break", primary: true), AlertAction(title: "Skip")])
        },
        Scene(name: "open-glass") { $0.notch.mode = .open; $0.prefs.v.glassPanel = true },
    ]

    /// True while drawing offscreen (see LiveClip).
    static var active = false

    static func run(app: AppModel, to dir: URL) {
        active = true
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        app.notch.geo = NotchGeo.detect()
        let g = app.notch.geo
        print(String(format: "notch %@: x %.1f..%.1f (%.0f x %.0f pt), screen %.0f x %.0f",
                     g.real ? "measured" : "FAKE", g.notchMinX, g.notchMaxX, g.notchW, g.notchH, g.screenFrame.width, g.screenFrame.height))
        let only = ProcessInfo.processInfo.environment["SAKU_RENDER_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
        var count = 0
        for scene in scenes where only == nil || only!.contains(where: { scene.name.hasPrefix($0) }) {
            reset(app)
            scene.setup(app)
            let height = app.maxPanelSize.height + NotchController.margin
            let size = CGSize(width: g.screenFrame.width, height: height)
            let view = Strip(app: app, height: height)
            if let rep = snapshot(view, size: size, settle: scene.settle) {
                save(rep, to: dir.appendingPathComponent("\(scene.name).png"))
                count += 1
            } else {
                print("FAILED to render \(scene.name)")
            }
        }
        // Settings panes as standalone images (the real window uses the same views).
        if only == nil || only!.contains(where: { "settings".hasPrefix($0) || $0.hasPrefix("settings") }) {
            reset(app)
            let demo = app.calendar?.source as? DemoCalendarSource
            let panes: [(String, AnyView, @MainActor () -> Void)] = [
                ("settings-welcome", AnyView(WelcomePane(app: app)), {}),
                ("settings-appearance", AnyView(AppearancePane(app: app)), {}),
                ("settings-keyboard", AnyView(KeyboardPane(app: app)), {}),
                ("settings-music", AnyView(MusicPane(app: app)), {}),
                ("settings-calendar", AnyView(CalendarPane(app: app)), {
                    app.prefs.v.newEventCalendarID = "google"
                    app.prefs.v.reminderTarget = "calendar"
                    app.prefs.v.reminderCalendarID = "google"
                    app.calendar.reload()
                }),
                ("settings-todo", AnyView(TodoPane(app: app)), {}),
                ("settings-calendar-ask", AnyView(CalendarPane(app: app)), {
                    demo?.eventAccess = .unknown
                    app.calendar.reload()
                }),
            ]
            for (name, v, setup) in panes {
                reset(app)
                setup()
                let size = CGSize(width: 620, height: 640)
                if let rep = snapshot(v.frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, .dark), size: size, settle: 0.6) {
                    save(rep, to: dir.appendingPathComponent("\(name).png"))
                    count += 1
                }
            }
        }
        print("rendered \(count) scenes to \(dir.path)")
        QA.cleanUp()
    }

    static func reset(_ app: AppModel) {
        let lang = ProcessInfo.processInfo.environment["SAKU_RENDER_LANG"] ?? "en"
        app.prefs.v = PrefsData()
        app.prefs.v.language = lang
        app.prefs.v.onboarded = true
        app.prefs.v.googleAutoPicked = true
        app.prefs.v.hiddenTabs = []
        app.notch.mode = .closed
        app.notch.alert = nil
        app.notch.hud = nil
        app.notch.pinned = false
        app.notch.hovering = false
        app.notch.tab = .home
        app.notch.dropTarget = nil
        app.clock = Self.fixedDate
        app.keepOpenReasons = []
        // Feature state from earlier scenes must not leak into the next picture.
        app.prefs.v.musicLiveActivity = false
        app.prefs.v.meetingHeadsUp = false
        if let t = app.timers {
            t.pomo = Pomodoro()
            t.countdown = Countdown()
            t.stopwatch = Stopwatch()
        }
        app.battery?.clearFlash()
        if app.prompter?.live == true { app.prompter.exit() }
        app.mirror?.stop()
        app.clipboard?.mode = 0
        if let m = app.music, !m.playing, m.track != nil { m.playPause() }
        // Demo calendar follows the same frozen clock as the date in the pictures.
        if let todo = app.todo {
            todo.auth.clientOverride = nil
            for k in ["google-tasks-access", "google-tasks-expiry", "google-tasks-refresh"] { Secrets.set(k, "") }
            todo.auth.refreshState()
            todo.now = { Self.fixedDate }
            todo.reset()
        }
        if let demo = app.calendar?.source as? DemoCalendarSource {
            demo.now = Self.fixedDate
            demo.eventAccess = .granted
            demo.clearSaved()
            app.calendar.composing = nil
            app.calendar.month = Calendar.current.startOfDay(for: Self.fixedDate)
            app.calendar.selectedDay = Calendar.current.startOfDay(for: Self.fixedDate)
            app.calendar.reload()
        }
    }

    /// Thursday 5 November 2026, 15:42, so every render shows the same clock.
    static let fixedDate: Date = {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour, c.minute) = (2026, 11, 5, 15, 42)
        return Calendar.current.date(from: c) ?? Date()
    }()

    /// Hosts the view in an offscreen window and draws it into a 2x bitmap.
    static func snapshot<V: View>(_ view: V, size: CGSize, scale: CGFloat = 2, settle: Double = 0.25) -> NSBitmapImageRep? {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(x: -30000, y: -30000, width: size.width, height: size.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(settle))
        host.layoutSubtreeIfNeeded()
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        window.contentView = nil
        window.close()
        return rep
    }

    static func save(_ rep: NSBitmapImageRep, to url: URL) {
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }

    /// Screen-wide strip: fake wallpaper + menu bar, the notch panel at its real spot.
    struct Strip: View {
        let app: AppModel
        let height: Double

        var body: some View {
            let g = app.notch.geo
            let canvasW = app.maxPanelSize.width + 2 * NotchController.margin
            ZStack(alignment: .topLeading) {
                Backdrop(geo: g, height: height)
                NotchRootView(app: app, controller: nil)
                    .frame(width: canvasW, height: height)
                    .offset(x: g.midX - canvasW / 2)
            }
            .frame(width: g.screenFrame.width, height: height, alignment: .topLeading)
            .clipped()
        }
    }

    /// Fake desktop: soft wallpaper, a light window, a dark menu bar and the hardware notch.
    struct Backdrop: View {
        let geo: NotchGeo
        let height: Double

        var body: some View {
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(hex: 0x2B1B3A), Color(hex: 0x5B2C5F), Color(hex: 0xC0608F)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(hex: 0xFFB3D1, alpha: 0.35), .clear], center: UnitPoint(x: 0.85, y: 1.2), startRadius: 10, endRadius: 700)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0xF6F1F4))
                        .shadow(color: .black.opacity(0.35), radius: 22, y: 10)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Circle().fill(Color(hex: 0xFF5F57)).frame(width: 12, height: 12)
                            Circle().fill(Color(hex: 0xFEBC2E)).frame(width: 12, height: 12)
                            Circle().fill(Color(hex: 0x28C840)).frame(width: 12, height: 12)
                        }
                        RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0xF4A6C8)).frame(width: 320, height: 24).padding(.top, 20)
                        ForEach([760.0, 640, 820, 540, 700], id: \.self) { w in
                            RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0xDCD3D9)).frame(width: w, height: 11)
                        }
                    }
                    .padding(16)
                }
                .frame(width: 1080, height: 520)
                .offset(x: 216, y: 70)
                Rectangle().fill(Color.black.opacity(0.32)).frame(width: geo.screenFrame.width, height: geo.notchH)
                HStack(spacing: 20) {
                    Image(systemName: "apple.logo").font(.system(size: 15, weight: .medium))
                    Text("Finder").fontWeight(.bold)
                    ForEach(["File", "Edit", "View", "Go", "Window", "Help"], id: \.self) { Text($0) }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .frame(height: geo.notchH)
                .offset(x: 20)
                HStack(spacing: 18) {
                    Image(systemName: "battery.75percent")
                    Image(systemName: "wifi")
                    Image(systemName: "magnifyingglass")
                    Image(systemName: "switch.2")
                    Text("Thu 5 Nov  15.42")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: geo.screenFrame.width - 18, height: geo.notchH, alignment: .trailing)
                NotchShape(radius: 10, ear: 0).fill(Color.black)
                    .frame(width: geo.notchW, height: geo.notchH)
                    .offset(x: geo.notchMinX)
            }
            .frame(width: geo.screenFrame.width, height: height, alignment: .topLeading)
        }
    }
}
