import AppKit
import Observation
import ServiceManagement
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case welcome, general, appearance, tabs, music, tray, clipboard, timers, notes, prompter, calendar, trackers,
         web, translate, ai, camera, apps, system, tools, keyboard, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome: tr("Welcome")
        case .general: tr("General")
        case .appearance: tr("Appearance")
        case .tabs: tr("Tabs")
        case .music: tr("Music")
        case .tray: tr("Tray & AirDrop")
        case .clipboard: tr("Clipboard")
        case .timers: tr("Timers")
        case .notes: tr("Notes")
        case .prompter: tr("Teleprompter")
        case .calendar: tr("Calendar")
        case .trackers: tr("Trackers")
        case .web: tr("Web")
        case .translate: tr("Translate")
        case .ai: tr("AI Assistant")
        case .camera: tr("Mirror")
        case .apps: tr("Apps & Shortcuts")
        case .system: tr("Battery & System")
        case .tools: tr("Tools")
        case .keyboard: tr("Keyboard")
        case .about: tr("About")
        }
    }

    var icon: String {
        switch self {
        case .welcome: "hand.wave.fill"
        case .general: "gearshape.fill"
        case .appearance: "paintbrush.fill"
        case .tabs: "square.split.2x1.fill"
        case .keyboard: "keyboard.fill"
        case .about: "info.circle.fill"
        case .music: "music.note"
        case .tray: "tray.full.fill"
        case .system: "battery.100percent.bolt"
        case .camera: "camera.fill"
        default: Tab(rawValue: rawValue)?.icon ?? "circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .welcome, .about: Theme.blossom
        case .general: Color(hex: 0x8E8E93)
        case .appearance: Color(hex: 0xBF5AF2)
        case .tabs: Color(hex: 0x5E5CE6)
        case .music: Color(hex: 0xFF375F)
        case .tray: Color(hex: 0x0A84FF)
        case .clipboard: Color(hex: 0x64D2FF)
        case .timers: Color(hex: 0xFF9F0A)
        case .notes: Color(hex: 0xFFD60A)
        case .prompter: Color(hex: 0xFF6482)
        case .calendar: Color(hex: 0xFF453A)
        case .trackers: Color(hex: 0x30D158)
        case .web: Color(hex: 0x0A84FF)
        case .translate: Color(hex: 0x5E5CE6)
        case .ai: Color(hex: 0xBF5AF2)
        case .camera: Color(hex: 0x636366)
        case .apps: Color(hex: 0x30B0C7)
        case .system: Color(hex: 0x30D158)
        case .tools: Color(hex: 0xFF9F0A)
        case .keyboard: Color(hex: 0x8E8E93)
        }
    }

    /// Panes whose feature has landed. Feature branches add themselves here.
    static let available: [SettingsPane] = [.general, .appearance, .tabs, .music, .tray, .clipboard, .timers, .notes, .about]
}

@MainActor @Observable
final class SettingsNav {
    var pane: SettingsPane = .general
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    let app: AppModel
    let nav = SettingsNav()
    private let onClose: () -> Void

    init(app: AppModel, onClose: @escaping () -> Void) {
        self.app = app
        self.onClose = onClose
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Saku"
        w.titlebarAppearsTransparent = true
        w.minSize = NSSize(width: 680, height: 460)
        w.isReleasedWhenClosed = false
        super.init(window: w)
        w.contentView = NSHostingView(rootView: SettingsView(app: app, nav: nav))
        w.delegate = self
        w.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(pane: String?) {
        if let pane, let p = SettingsPane(rawValue: pane) { nav.pane = p }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { onClose() }
}

struct SettingsView: View {
    let app: AppModel
    @Bindable var nav: SettingsNav

    var body: some View {
        NavigationSplitView {
            List(selection: $nav.pane) {
                ForEach(SettingsPane.available) { p in
                    Label {
                        Text(p.title)
                    } icon: {
                        PaneIcon(pane: p)
                    }
                    .tag(p)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            pane(nav.pane)
                .navigationTitle(nav.pane.title)
        }
    }

    @ViewBuilder private func pane(_ p: SettingsPane) -> some View {
        switch p {
        case .general: GeneralPane(app: app)
        case .appearance: AppearancePane(app: app)
        case .tabs: TabsPane(app: app)
        case .about: AboutPane(app: app)
        default: FeaturePanes.view(p, app: app)
        }
    }
}

struct PaneIcon: View {
    let pane: SettingsPane
    var body: some View {
        Image(systemName: pane.icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(pane.color.gradient))
    }
}

/// Settings panes that belong to features. Feature branches add their case here.
@MainActor
enum FeaturePanes {
    @ViewBuilder static func view(_ p: SettingsPane, app: AppModel) -> some View {
        switch p {
        case .music: MusicPane(app: app)
        case .timers: TimersPane(app: app)
        case .tray: TrayPane(app: app)
        case .clipboard: ClipboardPane(app: app)
        case .notes: NotesPane(app: app)
        default: Text(p.title).foregroundStyle(.secondary)
        }
    }
}

/// Open at login through ServiceManagement (needs the app bundle, not a bare binary).
@MainActor
enum LoginItem {
    static var enabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Saku: login item change failed: \(error.localizedDescription)")
        }
    }
}

/// Slider row with its value printed on the right.
struct SliderRow: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 1
    var format: (Double) -> String = { String(format: "%.0f", $0) }

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: step).frame(minWidth: 160)
                Text(format(value)).monospacedDigit().foregroundStyle(.secondary).frame(width: 54, alignment: .trailing)
            }
        } label: {
            Text(title)
        }
    }
}
