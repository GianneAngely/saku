import Foundation
import Observation

/// Every user setting. Plain Codable struct: new fields get their default automatically, because saved JSON
/// is laid over a freshly encoded default value before decoding (see Prefs.load).
struct PrefsData: Codable, Equatable {
    // General
    var showInDock = false
    var showMenuBarIcon = true
    var rememberLastTab = true
    var lastTab = "home"
    var language = "system"                 // system, en, id
    var hideInFullscreen = true
    var hideWhileMirroring = false
    var notchlessScreens = "transparent"    // transparent, visible, hidden
    var hapticFeedback = true
    var hideFromScreenSharing = false
    var onboarded = false

    // Appearance
    var openWidth = 660.0
    var openHeight = 236.0
    var cornerRadius = 24.0
    var notchWidthOffset = 0.0
    var notchHeightOffset = 0.0
    var hoverDelay = 0.12
    var closeDelay = 0.25
    var glassPanel = false
    var closedStyle = "auto"                // auto, waveform, date, pomodoro, countdown, stopwatch, none
    var idleMark = "none"                   // none, blossom, mascot
    var dateColor = "#F7F2F6"
    var timeColor = "#FF7EB6"
    var use24Hour = true

    // Tabs
    var tabOrder: [String] = Tab.allCases.map(\.rawValue)
    var hiddenTabs: [String] = ["camera", "apps", "system", "tools", "translate", "trackers", "web"]
}

@MainActor @Observable
final class Prefs {
    var v: PrefsData { didSet { if v != oldValue { save() } } }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key = "prefs.v1"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        v = Prefs.load(from: defaults.data(forKey: key))
        Lang.shared.code = v.language
    }

    static func load(from data: Data?) -> PrefsData {
        let enc = JSONEncoder(), dec = JSONDecoder()
        guard let data,
              let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let baseData = try? enc.encode(PrefsData()),
              var base = try? JSONSerialization.jsonObject(with: baseData) as? [String: Any] else { return PrefsData() }
        for (k, value) in saved where base[k] != nil { base[k] = value }
        guard let merged = try? JSONSerialization.data(withJSONObject: base),
              let out = try? dec.decode(PrefsData.self, from: merged) else { return PrefsData() }
        return out
    }

    private func save() {
        if let data = try? JSONEncoder().encode(v) { defaults.set(data, forKey: key) }
        Lang.shared.code = v.language
    }

    func restoreDefaults() {
        var fresh = PrefsData()
        fresh.onboarded = v.onboarded
        v = fresh
    }
}
