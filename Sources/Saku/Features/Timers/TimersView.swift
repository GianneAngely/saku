import SwiftUI

struct TimersView: View {
    let app: AppModel

    var body: some View {
        let t = app.timers!
        VStack(spacing: 8) {
            if TimerMode.available.count > 1 {
                Segments(items: TimerMode.available.map { ($0, $0.title) },
                         selection: Binding(get: { t.mode }, set: { t.mode = $0 }), tint: t.mode.tint)
            }
            switch t.mode {
            case .pomodoro: PomodoroView(app: app)
            default: TimerModeExtras.view(t.mode, app: app)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Views for timer modes added by later feature branches.
@MainActor
enum TimerModeExtras {
    @ViewBuilder static func view(_ mode: TimerMode, app: AppModel) -> some View {
        switch mode {
        case .countdown: CountdownView(app: app)
        case .stopwatch: StopwatchView(app: app)
        default: EmptyView()
        }
    }
}

/// The ring sits in the middle of the panel, right under the camera, with equal columns on both sides.
struct TimerColumns<Leading: View, Center: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var center: Center
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            leading.frame(maxWidth: .infinity)
            center
            trailing.frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity)
    }
}

struct PomodoroView: View {
    let app: AppModel

    var body: some View {
        let t = app.timers!
        let pomo = t.pomo
        let prefs = app.prefs
        TimelineView(.animation(minimumInterval: 1, paused: !pomo.running)) { ctx in
            let left = pomo.left(at: ctx.date, prefs.v)
            let total = pomo.length(prefs.v)
            TimerColumns {
                VStack(spacing: 7) {
                    Text(pomo.phase == .focus ? tr("Focus %d of %d", pomo.round, max(1, prefs.v.pomoLongEvery)) : pomo.title)
                        .font(Theme.font(16, .bold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(nextHint).font(Theme.font(11.5)).foregroundStyle(Theme.text2)
                        .lineLimit(2).multilineTextAlignment(.center)
                    RoundDots(done: pomo.phase == .focus ? pomo.round - 1 : pomo.round, total: max(1, prefs.v.pomoLongEvery), tint: Theme.butter)
                        .padding(.top, 2)
                    TodayChip(count: pomo.today(TimersModel.dayKey(ctx.date)))
                        .padding(.top, 3)
                }
            } center: {
                ZStack {
                    TimerRing(progress: total > 0 ? 1 - left / total : 0, tint: pomo.tint, line: 8)
                    VStack(spacing: 1) {
                        Text(TimerDisplay.clock(left, roundUp: true)).font(Theme.mono(29, .heavy)).foregroundStyle(Theme.text)
                        Text(pomo.title).font(Theme.font(11, .semibold)).foregroundStyle(pomo.tint).lineLimit(1)
                    }
                    .padding(.horizontal, 14)
                }
                .frame(width: 132, height: 132)
            } trailing: {
                VStack(spacing: 8) {
                    PillButton(title: pomo.running ? tr("Pause") : (pomo.started ? tr("Resume") : tr("Start")),
                               icon: pomo.running ? "pause.fill" : "play.fill", primary: true, tint: pomo.tint, minWidth: 150) { t.pomoToggle() }
                    HStack(spacing: 6) {
                        PillButton(title: tr("Reset"), icon: "arrow.counterclockwise", compact: true) { t.pomoReset() }
                        PillButton(title: tr("Skip"), icon: "forward.end.fill", compact: true) { t.pomoSkip() }
                    }
                    StepperGroup {
                        MinuteStepper(title: tr("Focus"), value: Binding(get: { prefs.v.pomoFocus }, set: { prefs.v.pomoFocus = $0 }), range: 1...180)
                        MinuteStepper(title: tr("Break"), value: Binding(get: { prefs.v.pomoShort }, set: { prefs.v.pomoShort = $0 }), range: 1...60)
                        MinuteStepper(title: tr("Long"), value: Binding(get: { prefs.v.pomoLong }, set: { prefs.v.pomoLong = $0 }), range: 1...120)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private var nextHint: String {
        let p = app.prefs.v, pomo = app.timers.pomo
        switch pomo.phase {
        case .focus:
            let long = pomo.round >= max(1, p.pomoLongEvery)
            return long ? tr("Then a %d-minute long break", Int(p.pomoLong)) : tr("Then a %d-minute break", Int(p.pomoShort))
        case .short, .long:
            return tr("Then focus for %d minutes", Int(p.pomoFocus))
        }
    }
}

/// Finished focus sessions today, as a small flame chip.
struct TodayChip: View {
    var count: Int

    var body: some View {
        Label(tr("%d today", count), systemImage: "flame.fill")
            .font(Theme.font(11, .semibold))
            .foregroundStyle(count > 0 ? Theme.butter : Theme.text3)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(Capsule().fill((count > 0 ? Theme.butter : Color.white).opacity(count > 0 ? 0.13 : 0.06)))
    }
}

/// Steppers side by side when they fit, else stacked as compact rows.
struct StepperGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) { content }
            VStack(spacing: 4) { content }
        }
    }
}

/// "Focus 25m" with small minus and plus buttons. An empty title shows the value alone.
struct MinuteStepper: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 1
    var unit = "m"

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus") { value = max(range.lowerBound, value - step) }
            VStack(spacing: -1) {
                Text("\(Int(value))\(unit)").font(Theme.mono(11.5, .bold)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.8)
                if !title.isEmpty {
                    Text(title).font(Theme.font(9, .semibold)).foregroundStyle(Theme.text3).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .frame(width: 34)
            stepButton("plus") { value = min(range.upperBound, value + step) }
        }
        .padding(.horizontal, 2)
        .frame(height: 30)
        .background(Capsule().fill(Color.white.opacity(0.07)))
    }

    private func stepButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.text2)
                .frame(width: 18, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Small dots for the sessions in a cycle.
struct RoundDots: View {
    var done: Int
    var total: Int
    var tint: Color

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { i in
                Circle().fill(i < done ? tint : Color.white.opacity(0.14)).frame(width: 7, height: 7)
            }
        }
    }
}

struct TimersPane: View {
    let app: AppModel

    var body: some View {
        @Bindable var prefs = app.prefs
        Form {
            Section(tr("Pomodoro")) {
                Stepper(value: $prefs.v.pomoFocus, in: 1...180) { LabeledContent(tr("Focus"), value: tr("%d min", Int(prefs.v.pomoFocus))) }
                Stepper(value: $prefs.v.pomoShort, in: 1...60) { LabeledContent(tr("Short break"), value: tr("%d min", Int(prefs.v.pomoShort))) }
                Stepper(value: $prefs.v.pomoLong, in: 1...120) { LabeledContent(tr("Long break"), value: tr("%d min", Int(prefs.v.pomoLong))) }
                Stepper(value: $prefs.v.pomoLongEvery, in: 2...8) { LabeledContent(tr("Long break after"), value: tr("%d focus sessions", prefs.v.pomoLongEvery)) }
                Toggle(tr("Start the next session on its own"), isOn: $prefs.v.pomoAutoStart)
            }
            Section {
                Toggle(tr("Pop an alert out of the notch when time is up"), isOn: $prefs.v.timerAlert)
                Toggle(tr("Play a chime when time is up"), isOn: $prefs.v.timerSound)
                SliderRow(title: tr("Chime volume"), value: $prefs.v.timerVolume, range: 0.1...1, step: 0.05) { "\(Int($0 * 100))%" }
                    .disabled(!prefs.v.timerSound)
                HStack {
                    Spacer()
                    Button(tr("Play chime")) { Sound.play("timer-done", volume: prefs.v.timerVolume) }
                }
            } header: {
                Text(tr("When time is up"))
            } footer: {
                Text(tr("Running timers show in the closed notch while Appearance > Closed notch style is Auto, or pin one there."))
            }
            Section {
                Picker(tr("When focus starts, run"), selection: $prefs.v.focusStartShortcut) {
                    Text(tr("Nothing")).tag("")
                    ForEach(app.shortcuts.names, id: \.self) { Text($0).tag($0) }
                }
                Picker(tr("When focus ends, run"), selection: $prefs.v.focusEndShortcut) {
                    Text(tr("Nothing")).tag("")
                    ForEach(app.shortcuts.names, id: \.self) { Text($0).tag($0) }
                }
            } header: {
                Text(tr("Focus hooks"))
            } footer: {
                Text(tr("Pick a Shortcut that turns on Do Not Disturb, starts a playlist or dims the lights. Make one in the Shortcuts app first."))
            }
        }
        .formStyle(.grouped)
        .onAppear { app.shortcuts.reload() }
    }
}
