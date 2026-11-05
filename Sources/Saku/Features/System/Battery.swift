import AppKit
import IOKit
import IOKit.ps
import Observation
import SwiftUI

struct BatteryInfo: Equatable {
    var present = false
    var level = 0                   // percent
    var charging = false
    var charged = false
    var onAC = false
    var minutesToFull: Int?
    var minutesToEmpty: Int?
    var lowPower = false
    var health: Int?                // percent of design capacity
    var cycles: Int?
    var temperature: Double?        // °C

    /// From one IOPSCopyPowerSourcesInfo description.
    static func parse(_ d: [String: Any]) -> BatteryInfo {
        var b = BatteryInfo()
        b.present = (d[kIOPSIsPresentKey] as? Bool) ?? false
        let cur = (d[kIOPSCurrentCapacityKey] as? Int) ?? 0
        let max = (d[kIOPSMaxCapacityKey] as? Int) ?? 100
        b.level = max > 0 ? Int((Double(cur) / Double(max) * 100).rounded()) : cur
        b.charging = (d[kIOPSIsChargingKey] as? Bool) ?? false
        b.charged = (d[kIOPSIsChargedKey] as? Bool) ?? false
        b.onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        if let t = d[kIOPSTimeToFullChargeKey] as? Int, t > 0 { b.minutesToFull = t }
        if let t = d[kIOPSTimeToEmptyKey] as? Int, t > 0 { b.minutesToEmpty = t }
        return b
    }

    /// Health, cycles and temperature from the AppleSmartBattery registry entry.
    mutating func addRegistry(_ r: [String: Any]) {
        if let raw = r["AppleRawMaxCapacity"] as? Int, let design = r["DesignCapacity"] as? Int, design > 0 {
            health = Swift.min(100, Int((Double(raw) / Double(design) * 100).rounded()))
        }
        cycles = r["CycleCount"] as? Int
        if let t = r["Temperature"] as? Int { temperature = Double(t) / 100 }
    }

    var symbol: String {
        if onAC && charging { return "battery.100percent.bolt" }
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    var tint: Color { level <= 20 && !onAC ? Theme.coral : lowPower ? Theme.butter : Theme.mint }

    var status: String {
        if charged || (onAC && level >= 100) { return tr("Fully charged") }
        if charging, let m = minutesToFull { return tr("Charging · %@ to full", Self.duration(m)) }
        if charging { return tr("Charging") }
        if onAC { return tr("On power adapter, not charging") }
        if let m = minutesToEmpty { return tr("%@ left", Self.duration(m)) }
        return tr("On battery")
    }

    static func duration(_ minutes: Int) -> String {
        minutes >= 60 ? tr("%dh %dm", minutes / 60, minutes % 60) : tr("%d min", minutes)
    }
}

@MainActor @Observable
final class BatteryModel {
    private(set) var info = BatteryInfo()
    /// True for a few seconds after the cable goes in (closed-notch charging flash).
    private(set) var flashing = false

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var flashWork: DispatchWorkItem?
    @ObservationIgnored private var warnedAt: Int?
    @ObservationIgnored private var lpmToken: NSObjectProtocol?

    init(app: AppModel, live: Bool) {
        self.app = app
        guard live else { return }
        refresh()
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let s = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<BatteryModel>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { me.refresh() }
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), s, .defaultMode)
            source = s
        }
        lpmToken = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        var b = BatteryInfo()
        let snap = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(snap).takeRetainedValue() as Array
        for ps in list {
            if let d = IOPSGetPowerSourceDescription(snap, ps)?.takeUnretainedValue() as? [String: Any],
               (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType {
                b = BatteryInfo.parse(d)
            }
        }
        b.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any] { b.addRegistry(dict) }
            IOObjectRelease(service)
        }
        apply(b)
    }

    /// New reading: flashes on plug-in, warns once when the level drops to the threshold.
    func apply(_ b: BatteryInfo) {
        let pluggedIn = b.onAC && !info.onAC && info.present
        info = b
        if pluggedIn { flash() }
        if b.onAC { warnedAt = nil }
        let threshold = app.prefs.v.batteryLowAlert
        if b.present, !b.onAC, threshold > 0, b.level <= threshold, warnedAt == nil {
            warnedAt = b.level
            app.present(NotchAlert(title: tr("Battery low"), subtitle: tr("%d%% left. Time to plug in.", b.level),
                                   icon: "battery.25percent", tint: Theme.coral, autoDismiss: 20))
        }
    }

    func clearFlash() {
        flashWork?.cancel()
        flashing = false
    }

    private func flash() {
        flashing = true
        flashWork?.cancel()
        let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.flashing = false } }
        flashWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: w)
    }

    func liveActivity() -> LiveActivity? {
        guard info.present else { return nil }
        switch app.prefs.v.batteryInNotch {
        case "always": return .charging(level: info.level, charging: info.charging)
        case "plug": return flashing ? .charging(level: info.level, charging: info.charging || info.onAC) : nil
        default: return nil
        }
    }
}

struct BatteryCard: View {
    let app: AppModel

    var body: some View {
        let b = app.battery.info
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: b.symbol).font(.system(size: 30, weight: .regular)).foregroundStyle(b.tint)
                        .symbolRenderingMode(.hierarchical)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(b.level)%").font(Theme.mono(24, .heavy)).foregroundStyle(Theme.text)
                        Text(b.status).font(Theme.font(11, .medium)).foregroundStyle(Theme.text2).lineLimit(1)
                        if b.lowPower {
                            Label(tr("Low Power Mode"), systemImage: "leaf.fill").font(Theme.font(10, .semibold)).foregroundStyle(Theme.butter)
                        }
                    }
                }
                ProgressTrack(value: Double(b.level) / 100, tint: b.tint, height: 5)
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    if let h = b.health { Stat(label: tr("Health"), value: "\(h)%") }
                    if let c = b.cycles { Stat(label: tr("Cycles"), value: "\(c)") }
                    if let t = b.temperature { Stat(label: tr("Temp"), value: String(format: "%.0f°C", t)) }
                }
            }
        }
    }
}

struct Stat: View {
    var label: String
    var value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(Theme.mono(12, .bold)).foregroundStyle(Theme.text)
            Text(label).font(Theme.font(9.5, .semibold)).foregroundStyle(Theme.text3)
        }
    }
}

/// System tab: battery now, network and CPU/memory from the system monitor branch.
struct SystemView: View {
    let app: AppModel

    var body: some View {
        HStack(spacing: 10) {
            BatteryCard(app: app).frame(width: 200)
            SystemExtras.view(app: app)
        }
        .onAppear { if !Render.active { app.monitor?.setVisible(true) } }
        .onDisappear { if !Render.active { app.monitor?.setVisible(false) } }
    }
}

@MainActor
enum SystemExtras {
    @ViewBuilder static func view(app: AppModel) -> some View {
        NetworkCard(app: app)
        CPUMemoryCard(app: app).frame(width: 190)
    }
}

struct SystemPane: View {
    let app: AppModel
    var body: some View {
        @Bindable var prefs = app.prefs
        Form {
            Section(tr("Battery")) {
                Picker(tr("Battery in the closed notch"), selection: $prefs.v.batteryInNotch) {
                    Text(tr("When the cable goes in")).tag("plug")
                    Text(tr("Always")).tag("always")
                    Text(tr("Never")).tag("never")
                }
                Picker(tr("Low battery alert"), selection: $prefs.v.batteryLowAlert) {
                    Text(tr("Off")).tag(0)
                    ForEach([10, 15, 20, 30], id: \.self) { Text("\($0)%").tag($0) }
                }
            }
            SystemPaneExtras.view(app: app)
        }
        .formStyle(.grouped)
    }
}

@MainActor
enum SystemPaneExtras {
    @ViewBuilder static func view(app: AppModel) -> some View {
        EmptyView()
    }
}
