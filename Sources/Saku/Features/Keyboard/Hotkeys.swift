import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

/// A key plus modifiers, stored in settings. Carbon modifier bits (cmdKey, optionKey, controlKey, shiftKey).
struct HotkeySpec: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var mods: UInt32

    var display: String {
        var s = ""
        if mods & UInt32(controlKey) != 0 { s += "⌃" }
        if mods & UInt32(optionKey) != 0 { s += "⌥" }
        if mods & UInt32(shiftKey) != 0 { s += "⇧" }
        if mods & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    static func keyName(_ code: UInt32) -> String {
        switch Int(code) {
        case kVK_Space: return tr("Space")
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: break
        }
        let fkeys: [Int: String] = [kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
                                    kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13",
                                    kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19"]
        if let f = fkeys[Int(code)] { return f }
        return character(code).uppercased()
    }

    /// The character a key types on the current keyboard layout (so ⌃⌥V shows V on any layout).
    static func character(_ code: UInt32) -> String {
        guard let src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var dead: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let r = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &length, &chars)
        }
        guard r == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: chars, count: length)
    }

    /// From an NSEvent (settings recorder).
    init?(event: NSEvent) {
        let f = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var m: UInt32 = 0
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        let isF = (Int(kVK_F1)...Int(kVK_F20)).contains(Int(event.keyCode))
        guard m & UInt32(cmdKey | optionKey | controlKey) != 0 || isF else { return nil }   // needs a real modifier
        keyCode = UInt32(event.keyCode)
        mods = m
    }

    init(keyCode: Int, mods: Int) {
        self.keyCode = UInt32(keyCode)
        self.mods = UInt32(mods)
    }
}

/// Things a shortcut can do.
enum HotkeyAction: String, CaseIterable, Codable, Identifiable {
    case toggle, home, tray, clipboard, timers, notes, prompter, calendar, trackers, web, translate, ai, camera, apps, system, tools
    case features, pomodoro, prompterPlay, pin
    case prompterFaster, prompterSlower, prompterBack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggle: tr("Open or close Saku")
        case .features: tr("All features: find anything")
        case .pomodoro: tr("Start or pause the Pomodoro")
        case .prompterPlay: tr("Teleprompter: start, play or pause")
        case .pin: tr("Keep the notch open")
        case .prompterFaster: tr("Teleprompter: faster (while reading)")
        case .prompterSlower: tr("Teleprompter: slower (while reading)")
        case .prompterBack: tr("Teleprompter: back 5 seconds (while reading)")
        default: tr("Open %@", tab?.title ?? rawValue)
        }
    }

    var tab: Tab? { Tab(rawValue: rawValue) }

    /// Only registered while the teleprompter is reading, so the keys stay free the rest of the time.
    var readingOnly: Bool { [.prompterFaster, .prompterSlower, .prompterBack].contains(self) }

    /// Defaults chosen to stay clear of window managers like Rectangle (which use ⌃⌥ with arrows and U I J K D F G E T C).
    static let defaults: [String: HotkeySpec] = [
        "toggle": HotkeySpec(keyCode: kVK_Space, mods: controlKey | optionKey),
        "features": HotkeySpec(keyCode: kVK_ANSI_Slash, mods: controlKey | optionKey),
        "clipboard": HotkeySpec(keyCode: kVK_ANSI_V, mods: controlKey | optionKey),
        "tray": HotkeySpec(keyCode: kVK_ANSI_B, mods: controlKey | optionKey),
        "ai": HotkeySpec(keyCode: kVK_ANSI_A, mods: controlKey | optionKey),
        "apps": HotkeySpec(keyCode: kVK_ANSI_L, mods: controlKey | optionKey),
        "pomodoro": HotkeySpec(keyCode: kVK_ANSI_O, mods: controlKey | optionKey),
        "prompterPlay": HotkeySpec(keyCode: kVK_ANSI_P, mods: controlKey | optionKey),
        "prompterFaster": HotkeySpec(keyCode: kVK_ANSI_RightBracket, mods: controlKey | optionKey),
        "prompterSlower": HotkeySpec(keyCode: kVK_ANSI_LeftBracket, mods: controlKey | optionKey),
        "prompterBack": HotkeySpec(keyCode: kVK_ANSI_Semicolon, mods: controlKey | optionKey),
    ]
}

/// Global shortcuts through Carbon's RegisterEventHotKey: works from any app, needs no Accessibility permission.
@MainActor @Observable
final class HotkeyCenter {
    /// Actions whose key is already taken by another app (registration refused).
    private(set) var conflicts: Set<HotkeyAction> = []

    @ObservationIgnored private var refs: [HotkeyAction: EventHotKeyRef] = [:]
    @ObservationIgnored private var handler: EventHandlerRef?
    @ObservationIgnored var perform: (HotkeyAction) -> Void = { _ in }
    @ObservationIgnored private let prefs: Prefs
    @ObservationIgnored var reading = false { didSet { if reading != oldValue { apply() } } }

    nonisolated(unsafe) static weak var current: HotkeyCenter?

    init(prefs: Prefs) {
        self.prefs = prefs
        HotkeyCenter.current = self
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            let index = Int(id.id)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard index < HotkeyAction.allCases.count else { return }
                    HotkeyCenter.current?.perform(HotkeyAction.allCases[index])
                }
            }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    /// The binding for an action: what's saved, else the default (an explicit "none" clears it).
    func spec(_ a: HotkeyAction) -> HotkeySpec? {
        if prefs.v.hotkeysCleared.contains(a.rawValue) { return nil }
        return prefs.v.hotkeys[a.rawValue] ?? HotkeyAction.defaults[a.rawValue]
    }

    func set(_ a: HotkeyAction, _ s: HotkeySpec?) {
        if let s {
            prefs.v.hotkeys[a.rawValue] = s
            prefs.v.hotkeysCleared.removeAll { $0 == a.rawValue }
        } else {
            prefs.v.hotkeys[a.rawValue] = nil
            if !prefs.v.hotkeysCleared.contains(a.rawValue) { prefs.v.hotkeysCleared.append(a.rawValue) }
        }
        apply()
    }

    func resetAll() {
        prefs.v.hotkeys = [:]
        prefs.v.hotkeysCleared = []
        apply()
    }

    /// Unregisters everything and registers the current bindings again.
    func apply() {
        for (_, r) in refs { UnregisterEventHotKey(r) }
        refs = [:]
        var failed: Set<HotkeyAction> = []
        var used: Set<HotkeySpec> = []
        for (i, a) in HotkeyAction.allCases.enumerated() {
            guard let s = spec(a), !(a.readingOnly && !reading) else { continue }
            guard used.insert(s).inserted else { failed.insert(a); continue }   // same keys twice inside Saku
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x53414B55), id: UInt32(i))   // 'SAKU'
            let status = RegisterEventHotKey(s.keyCode, s.mods, id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs[a] = ref } else { failed.insert(a) }
        }
        conflicts = failed
    }

    func unregisterAll() {
        for (_, r) in refs { UnregisterEventHotKey(r) }
        refs = [:]
    }

    var registeredCount: Int { refs.count }
}
