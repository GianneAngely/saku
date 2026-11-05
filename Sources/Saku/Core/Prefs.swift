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
    var idleMark = "none"                   // none, blossom, mascot (a picture in the data folder)
    var dateColor = "#F7F2F6"
    var timeColor = "#FF7EB6"
    var use24Hour = true

    // Music
    var musicLiveActivity = true
    var musicHideWhenPaused = true
    var musicAlbumTint = true
    var musicCoverBackground = false
    var musicPreferredPlayer = "auto"       // auto, spotify, music, browser
    var musicOnHome = true
    var musicBrowser = false

    // Timers
    var pomoFocus = 25.0                    // minutes
    var pomoShort = 5.0
    var pomoLong = 15.0
    var pomoLongEvery = 4
    var pomoAutoStart = false
    var timerSound = true
    var timerVolume = 0.7
    var timerAlert = true
    var focusStartShortcut = ""             // Apple Shortcut to run when a focus session starts
    var focusEndShortcut = ""               // ...and when it ends

    // Tray
    var trayCopyFiles = false
    var trayOpenAfterDrop = false
    var airdropZone = true

    // Clipboard
    var clipboardEnabled = true
    var clipboardLimit = 200
    var clipboardPreview = true
    var clipboardClearOnQuit = false
    var clipboardPasteDirect = false
    var clipboardPaused = false
    var clipboardIgnoreApps: [String] = ["com.1password.1password", "com.agilebits.onepassword7", "com.apple.keychainaccess",
                                         "com.bitwarden.desktop", "com.apple.Passwords"]

    // Notes
    var notesFontSize = 12.5
    var notesWordCount = true

    // Teleprompter
    var prompterSpeed = 140.0               // words per minute
    var prompterFontSize = 26.0
    var prompterLineSpacing = 6.0
    var prompterWidth = 620.0
    var prompterHeight = 190.0
    var prompterMirror = false
    var prompterCountdown = 3
    var prompterFocusLine = true
    var prompterVoice = false
    var prompterLanguage = "auto"           // auto, en-US, id-ID

    // Calendar
    var calendarMonthView = true
    var calendarHideEnded = false
    var calendarOnHome = true
    var meetingHeadsUp = true
    var meetingLead = 10.0                  // minutes
    var calendarIDs: [String] = []          // empty = all
    var reminderListIDs: [String] = []
    var newEventCalendarID = ""             // empty = the system's default calendar
    var newEventAlert = 10.0                // minutes before, -1 = no alert
    var reminderTarget = "reminders"        // reminders (Apple Reminders) or calendar (an event with an alert)
    var reminderCalendarID = ""
    var reminderAlert = 0.0                 // minutes before the due time
    var googleHintDismissed = false
    var googleAutoPicked = false            // the first Google calendar was set as home for new events once

    // To-do
    var todoInNotch = true                  // tasks due today show beside the camera
    var todoShowCompleted = false

    // Battery and system
    var batteryInNotch = "plug"             // plug, always, never
    var batteryLowAlert = 15                // percent, 0 = off

    // Water
    var waterGoal = 2000.0                  // ml
    var waterSip = 250.0                    // ml per drink
    var waterUnit = "ml"                    // ml, oz, cups
    var waterReminder = 0.0                 // minutes between reminders, 0 = off

    // Web
    var webSearchEngine = "google"
    var webMobile = true
    var webZoom = 0.9
    var webWidth = 720.0
    var webHeight = 420.0

    // Translate
    var translateProvider = "apple"         // apple, deepl, google, ai
    var translateTo = "id"
    var translatePrompt = "Translate this into {{to}}:\n\n{{text}}"

    // AI assistant
    var aiProvider = "apple"                // apple, claude, gemini
    var aiSystemPrompt = "You are Saku, a friendly assistant that lives in the Mac's notch. Keep answers short and clear. Use plain text, with short lists when they help."
    var claudeModel = "claude-opus-5-5"
    var claudeEffort = "low"
    var geminiModel = "gemini-flash-latest"

    // Mirror
    var mirrorAutoStart = true
    var mirrorFlip = true
    var mirrorRingLight = false
    var mirrorEffect = "natural"

    // Shortcuts
    var shortcutsShown: [String] = []      // empty = all

    // Keyboard
    var hotkeys: [String: HotkeySpec] = [:]     // action -> keys; missing = default
    var hotkeysCleared: [String] = []           // actions with no shortcut on purpose

    // Tools
    var colorFormat = "hex"                 // hex, rgb, hsl, swiftui
    var weatherCity: City? = nil
    var weatherOnHome = true
    var weatherFahrenheit = false
    var eyeBreakEvery = 0.0                 // minutes of screen time, 0 = off
    var eyeBreakSkipFocus = true

    // Tabs
    var tabOrder: [String] = Tab.allCases.map(\.rawValue)
    var hiddenTabs: [String] = ["camera", "apps", "tools", "translate", "web"]   // all still in All features
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
