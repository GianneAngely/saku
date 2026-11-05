import AppKit
import IOKit.ps

@MainActor
enum BatteryChecks {
    static func run(_ app: AppModel) {
        func check(_ ok: Bool, _ name: String) { SelfTest.check(ok, name) }
        var b = BatteryInfo.parse([kIOPSIsPresentKey: true, kIOPSCurrentCapacityKey: 45, kIOPSMaxCapacityKey: 100,
                                   kIOPSIsChargingKey: true, kIOPSPowerSourceStateKey: kIOPSACPowerValue, kIOPSTimeToFullChargeKey: 75])
        check(b.present && b.level == 45 && b.charging && b.onAC && b.minutesToFull == 75, "power source parsing")
        check(b.status == tr("Charging · %@ to full", tr("%dh %dm", 1, 15)), "charging status text")
        b.addRegistry(["AppleRawMaxCapacity": 5319, "DesignCapacity": 6075, "CycleCount": 113, "Temperature": 3218])
        check(b.health == 88 && b.cycles == 113 && b.temperature == 32.18, "health, cycles and temperature")
        let unplugged = BatteryInfo.parse([kIOPSIsPresentKey: true, kIOPSCurrentCapacityKey: 80, kIOPSMaxCapacityKey: 100,
                                           kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue, kIOPSTimeToEmptyKey: 200])
        check(!unplugged.onAC && unplugged.status == tr("%@ left", tr("%dh %dm", 3, 20)), "on battery status")
        check(BatteryInfo(present: true, level: 100, onAC: true).status == tr("Fully charged"), "full")

        // Plug-in flash and the low battery alert.
        let m = app.battery!
        app.prefs.v.batteryInNotch = "plug"
        app.prefs.v.closedStyle = "auto"
        m.apply(BatteryInfo(present: true, level: 50, onAC: false))
        check(m.liveActivity() == nil, "nothing while unplugged")
        m.apply(BatteryInfo(present: true, level: 50, charging: true, onAC: true))
        check(m.flashing && m.liveActivity() == .charging(level: 50, charging: true), "plugging in flashes the charge")
        if case .charging = app.liveActivity {} else { check(false, "charging flash wins in the closed notch") }
        app.prefs.v.batteryLowAlert = 15
        app.dismissAlert()
        m.apply(BatteryInfo(present: true, level: 16, onAC: false))
        check(app.notch.alert == nil, "no alert above the threshold")
        m.apply(BatteryInfo(present: true, level: 15, onAC: false))
        check(app.notch.alert?.title == tr("Battery low"), "low battery alert")
        app.dismissAlert()
        m.apply(BatteryInfo(present: true, level: 14, onAC: false))
        check(app.notch.alert == nil, "the alert shows once per discharge")
        app.prefs.v.batteryInNotch = "always"
        check(m.liveActivity() == .charging(level: 14, charging: false), "always show the battery")
        app.prefs.v.batteryInNotch = "plug"
        m.apply(BatteryInfo(present: true, level: 76, onAC: false, minutesToEmpty: 312, health: 88, cycles: 113, temperature: 31.5))
    }

    static let scenes: [Render.Scene] = [
        Render.Scene(name: "closed-charging", settle: 0.3) { app in
            app.prefs.v.musicLiveActivity = false
            app.prefs.v.meetingHeadsUp = false
            app.battery.apply(BatteryInfo(present: true, level: 64, onAC: false))
            app.battery.apply(BatteryInfo(present: true, level: 64, charging: true, onAC: true, minutesToFull: 72, health: 88, cycles: 113))
        },
        Render.Scene(name: "open-system", settle: 0.5) { app in
            app.monitor.fillDemo()
            app.battery.apply(BatteryInfo(present: true, level: 76, onAC: false, minutesToEmpty: 312, health: 88, cycles: 113, temperature: 31.5))
            app.notch.mode = .open
            app.notch.tab = .system
        },
    ]
}
