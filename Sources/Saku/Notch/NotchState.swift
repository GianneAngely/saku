import AppKit
import Observation
import SwiftUI

enum Tab: String, CaseIterable, Identifiable, Codable {
    case home, tray, clipboard, timers, notes, prompter, calendar, trackers, web, translate, ai, camera, apps, system, tools

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .tray: "tray.full.fill"
        case .clipboard: "list.clipboard.fill"
        case .timers: "timer"
        case .notes: "note.text"
        case .prompter: "text.line.first.and.arrowtriangle.forward"
        case .calendar: "calendar"
        case .trackers: "target"
        case .web: "globe"
        case .translate: "character.bubble.fill"
        case .ai: "sparkles"
        case .camera: "camera.fill"
        case .apps: "square.grid.2x2.fill"
        case .system: "gauge.with.dots.needle.67percent"
        case .tools: "wrench.and.screwdriver.fill"
        }
    }

    var title: String {
        switch self {
        case .home: tr("Home")
        case .tray: tr("Tray")
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
        case .apps: tr("Apps")
        case .system: tr("System")
        case .tools: tr("Tools")
        }
    }

    /// Tabs whose feature has landed. Feature branches add themselves here.
    static let available: [Tab] = [.home]
}

enum NotchMode: Equatable {
    case closed, open, drop
}

enum DropZone: Equatable {
    case tray, airdrop
}

/// A button on an alert card.
struct AlertAction: Identifiable {
    let id = UUID()
    var title: String
    var primary = false
    var run: @MainActor () -> Void = {}
}

/// Compact card that springs out of the notch (timer done, reminders). Mascot pops in like NotchPing.
struct NotchAlert: Identifiable {
    let id = UUID()
    var title: String
    var subtitle: String = ""
    var icon: String = "bell.fill"
    var tint: Color = Theme.blossom
    var actions: [AlertAction] = []
    var autoDismiss: TimeInterval? = 12
}

/// Short message in the closed-notch wings ("Added to Tray", "Copied").
struct NotchHUD: Equatable {
    var icon: String
    var text: String
    var tint: Color = Theme.blossom
    var id = UUID()
}

/// What the closed notch shows in its wings.
enum LiveActivity: Equatable {
    case none
    case mark(String)                                      // idle logo: "blossom" or "mascot"
    case date
    case hud(NotchHUD)
    case music(artwork: NSImage?, playing: Bool, tint: Color)
    case timer(icon: String, text: String, progress: Double, tint: Color)
    case charging(level: Int, charging: Bool)
    case meeting(text: String)

    /// Width of each wing (both sides use the larger one so the notch stays centred).
    var wing: Double {
        switch self {
        case .none: 0
        case .mark: 30
        case .date: 62
        case .hud(let h): min(150, Double(h.text.count) * 6.6 + 18)
        case .music: 36
        case .timer: 54
        case .charging: 50
        case .meeting: 64
        }
    }
}

@MainActor @Observable
final class NotchState {
    var mode: NotchMode = .closed
    var tab: Tab = .home
    var pinned = false
    var geo: NotchGeo = .fallback
    var hidden = false                 // full screen, mirroring or a notchless screen set to "hidden"
    var transparentClosed = false      // notchless screen set to "transparent"
    var alert: NotchAlert?
    var hud: NotchHUD?
    var dropTarget: DropZone?
    var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    var isOpen: Bool { mode != .closed }
}
