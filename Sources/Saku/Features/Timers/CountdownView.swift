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
            TimerColumns {
                VStack(spacing: 8) {
                    NotchField(placeholder: tr("Label, e.g. Tea"), text: Binding(get: { t.countdown.label }, set: { t.countdown.label = $0 }), icon: "tag.fill")
                        .frame(maxWidth: 190)
                    Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                        ForEach(0..<2, id: \.self) { row in
                            GridRow {
                                ForEach(Self.presets[(row * 4)..<(row * 4 + 4)], id: \.0) { p in
                                    presetChip(p, on: cd.total == p.1) { t.cdSet(p.1, start: true) }
                                }
                            }
                        }
                    }
                }
            } center: {
                ZStack {
                    TimerRing(progress: cd.total > 0 ? 1 - left / cd.total : 0, tint: Theme.blossom, line: 8)
                    VStack(spacing: 1) {
                        Text(TimerDisplay.clock(left, roundUp: true)).font(Theme.mono(left >= 3600 ? 23 : 29, .heavy)).foregroundStyle(Theme.text)
                        Text(cd.label.isEmpty ? tr("Countdown") : cd.label).font(Theme.font(11, .semibold)).foregroundStyle(Theme.blossom).lineLimit(1)
                    }
                    .padding(.horizontal, 14)
                }
                .frame(width: 132, height: 132)
            } trailing: {
                VStack(spacing: 8) {
                    PillButton(title: cd.running ? tr("Pause") : (cd.started ? tr("Resume") : tr("Start")),
                               icon: cd.running ? "pause.fill" : "play.fill", primary: true, tint: Theme.blossom, minWidth: 150) { t.cdToggle() }
                    HStack(spacing: 6) {
                        PillButton(title: tr("Reset"), icon: "arrow.counterclockwise", compact: true) { t.cdReset() }
                        PillButton(title: tr("+1 min"), icon: "plus", compact: true) { t.cdAdd(60) }
                            .disabled(!cd.started).opacity(cd.started ? 1 : 0.45)
                    }
                    StepperGroup {
                        MinuteStepper(title: "", value: part(3600, 24), range: 0...23, unit: "h")
                        MinuteStepper(title: "", value: part(60, 60), range: 0...59, unit: "m")
                        MinuteStepper(title: "", value: part(1, 60), range: 0...59, step: 5, unit: "s")
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private func presetChip(_ p: (String, Double), on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(p.0).font(Theme.font(11, .semibold))
                .foregroundStyle(on ? Color.black.opacity(0.85) : Theme.text2)
                .frame(width: 42, height: 22)
                .background(Capsule().fill(on ? Theme.blossom : Color.white.opacity(0.07)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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
