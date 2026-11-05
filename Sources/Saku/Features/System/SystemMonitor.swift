import AppKit
import CoreWLAN
import Darwin
import Observation
import SwiftUI

/// Counters read once per second while the System tab is on screen. Nothing runs while it is hidden.
struct SystemSample: Equatable {
    var down: Double = 0            // bytes per second
    var up: Double = 0
    var cpu: Double = 0             // 0...1
    var memUsed: Double = 0         // bytes
    var memTotal: Double = 0
    var rssi: Int?                  // dBm
    var txRate: Double?             // Mbps
    var diskFree: Double?           // bytes
}

enum SystemCounters {
    /// Total bytes in and out over physical interfaces (no loopback, no VPN tunnels).
    static func network() -> (rx: UInt64, tx: UInt64) {
        var rx: UInt64 = 0, tx: UInt64 = 0
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return (0, 0) }
        defer { freeifaddrs(addrs) }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let a = p {
            let name = String(cString: a.pointee.ifa_name)
            if a.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), name.hasPrefix("en"), let data = a.pointee.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                rx += UInt64(d.ifi_ibytes)
                tx += UInt64(d.ifi_obytes)
            }
            p = a.pointee.ifa_next
        }
        return (rx, tx)
    }

    /// CPU ticks (busy, total) since boot.
    static func cpuTicks() -> (busy: UInt64, total: UInt64) {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard r == KERN_SUCCESS else { return (0, 0) }
        let user = UInt64(info.cpu_ticks.0), sys = UInt64(info.cpu_ticks.1), idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return (user + sys + nice, user + sys + nice + idle)
    }

    /// Used memory the way Activity Monitor counts it: app memory + wired + compressed.
    static func memory() -> (used: Double, total: Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard r == KERN_SUCCESS else { return (0, total) }
        let page = Double(vm_kernel_page_size)
        let app = Double(stats.internal_page_count) - Double(stats.purgeable_count)
        let used = (app + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
        return (min(total, max(0, used)), total)
    }

    static func diskFree() -> Double? {
        let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return v?.volumeAvailableCapacityForImportantUsage.map(Double.init)
    }

    /// "12.3 MB/s", "840 KB/s", "0 B/s"
    static func rate(_ bytesPerSecond: Double) -> String { bytes(bytesPerSecond) + "/s" }

    /// Decimal like Finder; `binary` for memory like Activity Monitor (16 GB of RAM, not 17).
    static func bytes(_ b: Double, binary: Bool = false) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        let k = binary ? 1024.0 : 1000.0
        var v = max(0, b), i = 0
        while v >= k && i < units.count - 1 { v /= k; i += 1 }
        return i == 0 ? "\(Int(v)) \(units[i])" : String(format: v < 10 ? "%.1f %@" : "%.0f %@", v, units[i])
    }

    /// Wi-Fi bars (0...4) from signal strength.
    static func bars(_ rssi: Int?) -> Int {
        guard let r = rssi, r != 0 else { return 0 }
        switch r {
        case (-55)...: return 4
        case (-67)...: return 3
        case (-75)...: return 2
        default: return 1
        }
    }
}

@MainActor @Observable
final class SystemMonitor {
    private(set) var now = SystemSample()
    private(set) var history: [SystemSample] = []
    static let historyLength = 60

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var users = 0
    @ObservationIgnored private var lastNet: (rx: UInt64, tx: UInt64, at: Date)?
    @ObservationIgnored private var lastCPU: (busy: UInt64, total: UInt64)?

    var running: Bool { timer != nil }

    /// Views call this on appear / disappear; sampling runs while at least one is visible.
    func setVisible(_ on: Bool) {
        users = max(0, users + (on ? 1 : -1))
        if users > 0 && timer == nil {
            sample()
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.sample() } }
            t.tolerance = 0.2
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if users == 0 {
            timer?.invalidate()
            timer = nil
        }
    }

    func sample(at date: Date = Date()) {
        var s = SystemSample()
        let net = SystemCounters.network()
        if let l = lastNet, date > l.at, net.rx >= l.rx, net.tx >= l.tx {
            let dt = date.timeIntervalSince(l.at)
            s.down = Double(net.rx - l.rx) / dt
            s.up = Double(net.tx - l.tx) / dt
        }
        lastNet = (net.rx, net.tx, date)
        let cpu = SystemCounters.cpuTicks()
        if let l = lastCPU, cpu.total > l.total {
            s.cpu = Double(cpu.busy - l.busy) / Double(cpu.total - l.total)
        }
        lastCPU = cpu
        let mem = SystemCounters.memory()
        s.memUsed = mem.used
        s.memTotal = mem.total
        if let wifi = CWWiFiClient.shared().interface() {
            let r = wifi.rssiValue()
            s.rssi = r == 0 ? nil : r
            s.txRate = wifi.transmitRate()
        }
        s.diskFree = SystemCounters.diskFree()
        now = s
        history.append(s)
        if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
    }

    /// Demo history for renders.
    func fillDemo() {
        history = (0..<Self.historyLength).map { i in
            let t = Double(i)
            return SystemSample(down: 1_200_000 + 900_000 * sin(t / 5) + 600_000 * sin(t / 1.7), up: 180_000 + 120_000 * cos(t / 4),
                                cpu: 0.22 + 0.12 * sin(t / 6) + 0.05 * sin(t), memUsed: 11.2e9 + 0.3e9 * sin(t / 9), memTotal: 16e9,
                                rssi: -48, txRate: 866, diskFree: 182e9)
        }
        now = history.last!
    }
}

struct Sparkline: View {
    var values: [Double]
    var tint: Color
    var maxValue: Double? = nil

    var body: some View {
        Canvas { c, size in
            guard values.count > 1 else { return }
            let top = max(maxValue ?? (values.max() ?? 1), 1e-9)
            let step = size.width / CGFloat(SystemMonitor.historyLength - 1)
            let offset = CGFloat(SystemMonitor.historyLength - values.count) * step
            var line = Path()
            for (i, v) in values.enumerated() {
                let p = CGPoint(x: offset + CGFloat(i) * step, y: size.height - CGFloat(min(1, v / top)) * (size.height - 2) - 1)
                if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
            }
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: offset, y: size.height))
            fill.closeSubpath()
            c.fill(fill, with: .linearGradient(Gradient(colors: [tint.opacity(0.35), tint.opacity(0.02)]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            c.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
    }
}

struct NetworkCard: View {
    let app: AppModel

    var body: some View {
        let m = app.monitor!
        let s = m.now
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Caption(text: tr("Network"))
                    Spacer()
                    WifiBars(bars: SystemCounters.bars(s.rssi))
                    if let r = s.rssi { Text("\(r) dBm").font(Theme.mono(10, .medium)).foregroundStyle(Theme.text3) }
                }
                HStack(spacing: 14) {
                    Label(SystemCounters.rate(s.down), systemImage: "arrow.down").font(Theme.mono(13, .bold)).foregroundStyle(Theme.sky)
                    Label(SystemCounters.rate(s.up), systemImage: "arrow.up").font(Theme.mono(13, .bold)).foregroundStyle(Theme.lavender)
                }
                ZStack {
                    let peak = max(m.history.map(\.down).max() ?? 1, m.history.map(\.up).max() ?? 1)
                    Sparkline(values: m.history.map(\.down), tint: Theme.sky, maxValue: peak)
                    Sparkline(values: m.history.map(\.up), tint: Theme.lavender, maxValue: peak)
                }
                .frame(maxHeight: .infinity)
                if let tx = s.txRate, tx > 0 {
                    Text(tr("Wi-Fi link %d Mbps", Int(tx))).font(Theme.font(10)).foregroundStyle(Theme.text3)
                }
            }
        }
    }
}

struct WifiBars: View {
    var bars: Int
    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(0..<4) { i in
                RoundedRectangle(cornerRadius: 1).fill(i < bars ? Theme.sky : Color.white.opacity(0.15))
                    .frame(width: 3, height: 4 + CGFloat(i) * 2.5)
            }
        }
    }
}

struct CPUMemoryCard: View {
    let app: AppModel

    var body: some View {
        let m = app.monitor!
        let s = m.now
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Caption(text: "CPU")
                    Spacer()
                    Text("\(Int((s.cpu * 100).rounded()))%").font(Theme.mono(12, .bold)).foregroundStyle(Theme.butter)
                }
                Sparkline(values: m.history.map(\.cpu), tint: Theme.butter, maxValue: 1).frame(maxHeight: .infinity)
                HStack {
                    Caption(text: tr("Memory"))
                    Spacer()
                    Text("\(SystemCounters.bytes(s.memUsed, binary: true)) / \(SystemCounters.bytes(s.memTotal, binary: true))").font(Theme.mono(10.5, .semibold)).foregroundStyle(Theme.text2)
                }
                ProgressTrack(value: s.memTotal > 0 ? s.memUsed / s.memTotal : 0, tint: Theme.blossom, height: 5)
                if let free = s.diskFree {
                    HStack {
                        Caption(text: tr("Disk"))
                        Spacer()
                        Text(tr("%@ free", SystemCounters.bytes(free))).font(Theme.mono(10.5, .semibold)).foregroundStyle(Theme.text2)
                    }
                }
            }
        }
    }
}
