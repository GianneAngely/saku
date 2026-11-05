import AppKit

@MainActor
enum SystemChecks {
    static func run(_ app: AppModel) {
        func check(_ ok: Bool, _ name: String) { SelfTest.check(ok, name) }
        let net = SystemCounters.network()
        check(net.rx > 0, "network counters read")
        let cpu = SystemCounters.cpuTicks()
        check(cpu.total > cpu.busy && cpu.busy > 0, "cpu ticks read")
        let mem = SystemCounters.memory()
        check(mem.total > 4e9 && mem.used > 1e9 && mem.used < mem.total, "memory read")
        check((SystemCounters.diskFree() ?? 0) > 0, "free disk read")
        check(SystemCounters.rate(1_234_567) == "1.2 MB/s" && SystemCounters.bytes(999) == "999 B" && SystemCounters.bytes(45_000_000_000) == "45 GB", "byte formatting")
        check(SystemCounters.bars(-45) == 4 && SystemCounters.bars(-70) == 2 && SystemCounters.bars(nil) == 0, "wifi bars")

        let m = app.monitor!
        check(!m.running, "the monitor is idle while hidden")
        m.setVisible(true)
        check(m.running && m.history.count == 1, "showing the tab starts sampling")
        m.sample(at: Date().addingTimeInterval(1))
        check(m.now.cpu >= 0 && m.now.cpu <= 1 && m.now.memTotal > 0, "a sample has sane values")
        m.setVisible(false)
        check(!m.running, "hiding the tab stops sampling")
        for i in 0..<70 { m.sample(at: Date().addingTimeInterval(Double(i + 2))) }
        check(m.history.count == SystemMonitor.historyLength, "history keeps the last minute")
    }
}
