import SwiftUI

struct CountdownView: View {
    let app: AppModel

    static let presets: [(String, Double)] = [("1m", 60), ("3m", 180), ("5m", 300), ("10m", 600), ("15m", 900),
                                              ("25m", 1500), ("30m", 1800), ("1h", 3600)]

    var body: some View {
        let t = app.timers!
        let cd = t.countdown
        TimelineView(.animation(minimumInterval: 1, paused: !cd.running)) { ctx in
            let left = cd.left(at: ctx.date)
            HStack(spacing: 18) {
                ZStack {
                    TimerRing(progress: cd.total > 0 ? 1 - left / cd.total : 0, tint: Theme.blossom, line: 8)
                    VStack(spacing: 1) {
                        Text(TimerDisplay.clock(left, roundUp: true)).font(Theme.mono(left >= 3600 ? 22 : 28, .heavy)).foregroundStyle(Theme.text)
                        Text(cd.label.isEmpty ? tr("Countdown") : cd.label).font(Theme.font(11, .semibold)).foregroundStyle(Theme.blossom).lineLimit(1)
                    }
                    .padding(.horizontal, 14)
                }
                .frame(width: 128, height: 128)
                .padding(.leading, 4)

                VStack(alignment: .leading, spacing: 8) {
                    NotchField(placeholder: tr("Label, e.g. Tea"), text: Binding(get: { t.countdown.label }, set: { t.countdown.label = $0 }), icon: "tag.fill")
                        .frame(maxWidth: 240)
                    HStack(spacing: 4) {
                        ForEach(Self.presets, id: \.0) { p in
                            let on = cd.total == p.1
                            Button { t.cdSet(p.1, start: true) } label: {
                                Text(p.0).font(Theme.font(11, .semibold))
                                    .foregroundStyle(on ? Color.black.opacity(0.85) : Theme.text2)
                                    .padding(.horizontal, 8).frame(height: 22)
                                    .background(Capsule().fill(on ? Theme.blossom : Color.white.opacity(0.07)))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack(spacing: 6) {
                        MinuteStepper(title: tr("Hours"), value: part(3600, 24), range: 0...23, unit: "h")
                        MinuteStepper(title: tr("Minutes"), value: part(60, 60), range: 0...59, unit: "m")
                        MinuteStepper(title: tr("Seconds"), value: part(1, 60), range: 0...59, step: 5, unit: "s")
                    }
                    HStack(spacing: 6) {
                        PillButton(title: cd.running ? tr("Pause") : (cd.started ? tr("Resume") : tr("Start")),
                                   icon: cd.running ? "pause.fill" : "play.fill", primary: true, tint: Theme.blossom) { t.cdToggle() }
                        PillButton(title: tr("Reset"), icon: "arrow.counterclockwise") { t.cdReset() }
                        if cd.started {
                            PillButton(title: tr("+1 min"), icon: "plus") { t.cdAdd(60) }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// One unit (hours, minutes or seconds) of the countdown length as a stepper value.
    private func part(_ unit: Double, _ wrap: Double) -> Binding<Double> {
        let t = app.timers!
        return Binding(
            get: { (t.countdown.total / unit).rounded(.down).truncatingRemainder(dividingBy: wrap) },
            set: { new in
                let old = (t.countdown.total / unit).rounded(.down).truncatingRemainder(dividingBy: wrap)
                t.cdSet(max(1, t.countdown.total + (new - old) * unit))
            })
    }
}
