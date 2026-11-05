import AppKit
import Darwin

/// `Saku --soak SECONDS`: runs the closed notch with every feature idle (music demo playing in the wings,
/// clipboard polling a private pasteboard), then prints CPU time and memory. Measures the cost of just sitting there.
@MainActor
enum Soak {
    static func cpuSeconds() -> Double {
        var u = rusage()
        getrusage(RUSAGE_SELF, &u)
        return Double(u.ru_utime.tv_sec) + Double(u.ru_utime.tv_usec) / 1e6 + Double(u.ru_stime.tv_sec) + Double(u.ru_stime.tv_usec) / 1e6
    }

    static func residentMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return r == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    static func run(app: AppModel, controller: NotchController, seconds: Double) {
        app.prefs.v.musicLiveActivity = false
        app.prefs.v.closedStyle = "auto"
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))       // settle after launch
            let c0 = cpuSeconds(), t0 = Date()
            try? await Task.sleep(for: .seconds(seconds))
            let idle = (cpuSeconds() - c0) / Date().timeIntervalSince(t0) * 100
            // Same again with music bars animating in the closed notch.
            app.prefs.v.musicLiveActivity = true
            try? await Task.sleep(for: .seconds(1))
            let c1 = cpuSeconds(), t1 = Date()
            try? await Task.sleep(for: .seconds(seconds))
            let music = (cpuSeconds() - c1) / Date().timeIntervalSince(t1) * 100
            print(String(format: "soak: idle %.2f%% CPU, with music bars %.2f%% CPU, memory %.0f MB", idle, music, residentMB()))
            controller.stop()
            QA.cleanUp()
            exit(0)
        }
    }
}
