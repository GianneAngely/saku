import SwiftUI

struct StopwatchView: View {
    let app: AppModel

    var body: some View {
        let t = app.timers!
        let sw = t.stopwatch
        HStack(spacing: 14) {
            VStack(spacing: 12) {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !sw.running || !app.notch.isOpen)) { ctx in
                    let e = sw.elapsed(at: ctx.date)
                    VStack(spacing: 2) {
                        Text(Stopwatch.text(e))
                            .font(Theme.mono(42, .heavy))
                            .foregroundStyle(sw.running ? Theme.text : Theme.text2)
                        Text(sw.laps.isEmpty ? tr("Lap %d", 1) : tr("Lap %d", sw.laps.count + 1) + "  " + Stopwatch.text(e - (sw.laps.last ?? 0)))
                            .font(Theme.mono(12, .semibold)).foregroundStyle(sw.laps.isEmpty ? Theme.text3 : Theme.sky)
                    }
                }
                HStack(spacing: 6) {
                    PillButton(title: sw.running ? tr("Pause") : (sw.started ? tr("Resume") : tr("Start")),
                               icon: sw.running ? "pause.fill" : "play.fill", primary: true, tint: Theme.sky) { t.swToggle() }
                    PillButton(title: tr("Lap"), icon: "flag.fill") { t.swLap() }.disabled(!sw.running)
                    PillButton(title: tr("Reset"), icon: "arrow.counterclockwise") { t.swReset() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Card(padding: 10) {
                if sw.laps.isEmpty {
                    EmptyState(icon: "flag.fill", title: tr("No laps yet"), subtitle: tr("Press Lap while it runs."), tint: Theme.sky)
                } else {
                    LapList(sw: sw)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct LapList: View {
    let sw: Stopwatch

    var body: some View {
        let splits = sw.splits
        let best = splits.count > 1 ? splits.min() : nil
        let worst = splits.count > 1 ? splits.max() : nil
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 4) {
                ForEach(Array(splits.enumerated().reversed()), id: \.offset) { i, split in
                    HStack {
                        Text(tr("Lap %d", i + 1)).font(Theme.font(11.5, .semibold)).foregroundStyle(Theme.text2)
                        Spacer()
                        Text(Stopwatch.text(split)).font(Theme.mono(11.5, .semibold))
                            .foregroundStyle(split == best ? Theme.mint : split == worst ? Theme.coral : Theme.text)
                        Text(Stopwatch.text(sw.laps[i])).font(Theme.mono(10.5, .medium)).foregroundStyle(Theme.text3)
                            .frame(width: 66, alignment: .trailing)
                    }
                    .frame(height: 20)
                }
            }
        }
    }
}
