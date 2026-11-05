import AppKit
import SwiftUI

/// Prompter tab while not reading: scripts, editor and the start button.
struct PrompterTab: View {
    let app: AppModel

    var body: some View {
        let m = app.prompter!
        HStack(spacing: 10) {
            VStack(spacing: 6) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(m.scripts) { s in
                            ScriptRow(script: s, on: s.id == m.selected, wpm: app.prefs.v.prompterSpeed)
                                .onTapGesture { m.selected = s.id }
                                .contextMenu { Button(tr("Delete"), role: .destructive) { m.delete(s.id) } }
                        }
                    }
                }
                PillButton(title: tr("New script"), icon: "plus", compact: true) { m.add() }
            }
            .frame(width: 160)

            if let s = m.current {
                ScriptEditor(app: app, script: s).id(s.id)
            }

            PrompterControls(app: app).frame(width: 168)
        }
    }
}

struct ScriptRow: View {
    let script: Script
    let on: Bool
    let wpm: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(script.title).font(Theme.font(11.5, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
            Text(tr("%d words · %@", script.words, TimerDisplay.clock(Double(script.words) / max(1, wpm) * 60, roundUp: true)))
                .font(Theme.font(10)).foregroundStyle(Theme.text3)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? Theme.cardHi : .clear))
        .contentShape(Rectangle())
    }
}

struct ScriptEditor: View {
    let app: AppModel
    @State var script: Script

    var body: some View {
        Card(padding: 8) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("", text: $script.title, prompt: Text(tr("Title")).foregroundStyle(Theme.text3))
                    .textFieldStyle(.plain).font(Theme.font(12.5, .semibold)).foregroundStyle(Theme.text)
                TextEditor(text: $script.text)
                    .font(Theme.font(12)).foregroundStyle(Theme.text)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
            }
        }
        .onChange(of: script) { _, s in app.prompter.update(s) }
    }
}

struct PrompterControls: View {
    let app: AppModel

    var body: some View {
        let m = app.prompter!
        let p = app.prefs
        VStack(alignment: .leading, spacing: 7) {
            let words = m.current?.words ?? 0
            Text(tr("About %@ at %d wpm", TimerDisplay.clock(Double(words) / max(1, p.v.prompterSpeed) * 60, roundUp: true), Int(p.v.prompterSpeed)))
                .font(Theme.font(11, .semibold)).foregroundStyle(Theme.text2).lineLimit(2)
            HStack(spacing: 6) {
                MinuteStepper(title: tr("Speed"), value: Binding(get: { p.v.prompterSpeed }, set: { p.v.prompterSpeed = $0 }), range: 40...400, step: 10, unit: "")
                MinuteStepper(title: tr("Size"), value: Binding(get: { p.v.prompterFontSize }, set: { p.v.prompterFontSize = $0 }), range: 16...56, step: 2, unit: "")
            }
            ToggleChip(title: tr("Mirror"), icon: "arrow.left.and.right.righttriangle.left.righttriangle.right", on: p.v.prompterMirror) { p.v.prompterMirror.toggle() }
            ToggleChip(title: tr("Voice follow"), icon: "waveform", on: p.v.prompterVoice) { p.v.prompterVoice.toggle() }
            Spacer(minLength: 0)
            Button { m.start() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill").font(.system(size: 11, weight: .bold))
                    Text(tr("Start reading")).font(Theme.font(12.5, .bold))
                }
                .foregroundStyle(Color.black.opacity(0.85))
                .frame(maxWidth: .infinity).frame(height: 30)
                .background(Capsule().fill(Theme.blossom))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled((m.current?.words ?? 0) == 0)
        }
    }
}

struct ToggleChip: View {
    var title: String
    var icon: String
    var on: Bool
    var tint: Color = Theme.blossom
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(on ? tint : Theme.text3)
                Text(title).font(Theme.font(11, .semibold)).foregroundStyle(on ? Theme.text : Theme.text2)
                Spacer(minLength: 2)
                Capsule().fill(on ? tint : Color.white.opacity(0.15)).frame(width: 22, height: 13)
                    .overlay(alignment: on ? .trailing : .leading) { Circle().fill(.white).frame(width: 9, height: 9).padding(2) }
            }
            .padding(.horizontal, 9).frame(height: 24)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stage

/// The reading view: lines scroll up to a reading line just under the camera.
struct PrompterStage: View {
    let app: AppModel
    @State private var hovering = false

    var body: some View {
        let m = app.prompter!
        let p = app.prefs.v
        let l = m.layout
        let viewport = CGFloat(p.prompterHeight)
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !m.playing && m.countdownEnd == nil)) { ctx in
            let off = m.offset(at: ctx.date)
            VStack(spacing: 0) {
                StageTopBar(app: app, now: ctx.date).frame(height: app.notch.geo.notchH)
                ZStack(alignment: .top) {
                    StageLines(layout: l, offset: off, viewport: viewport, fontSize: p.prompterFontSize, focus: p.prompterFocusLine)
                        .frame(width: m.columnWidth, height: viewport, alignment: .top)
                        .scaleEffect(x: p.prompterMirror ? -1 : 1, y: 1)
                        .mask(LinearGradient(stops: [.init(color: .black.opacity(0.25), location: 0), .init(color: .black, location: 0.14),
                                                     .init(color: .black, location: 0.62), .init(color: .clear, location: 1)],
                                             startPoint: .top, endPoint: .bottom))
                    ReadingMarks(y: PrompterModel.readingLine + (l.lines.first?.height ?? 30) / 2, width: m.columnWidth + 30)
                    if let end = m.countdownEnd {
                        let n = Int(ceil(end.timeIntervalSince(ctx.date)))
                        Text("\(max(1, n))").font(Theme.mono(64, .heavy)).foregroundStyle(Theme.blossom)
                            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black.opacity(0.65))
                    }
                    if m.finished {
                        VStack(spacing: 6) {
                            Text(tr("The end")).font(Theme.font(18, .heavy)).foregroundStyle(Theme.text)
                            HStack(spacing: 6) {
                                PillButton(title: tr("Read again"), icon: "arrow.counterclockwise", primary: true) { m.restart(); if !m.playing { m.togglePlay() } }
                                PillButton(title: tr("Close"), icon: "xmark") { m.exit() }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black.opacity(0.7))
                    }
                }
                .frame(height: viewport)
                .overlay(alignment: .bottom) {
                    StageControls(app: app).opacity(hovering || !m.playing ? 1 : 0.35).padding(.bottom, 8)
                }
            }
        }
        .frame(width: CGFloat(p.prompterWidth))
        .onHover { hovering = $0 }
    }
}

struct StageLines: View {
    let layout: PrompterLayout
    let offset: CGFloat
    let viewport: CGFloat
    let fontSize: Double
    let focus: Bool

    var body: some View {
        let top = offset - PrompterModel.readingLine
        let current = layout.lines.lastIndex { $0.y <= offset + 1 } ?? 0
        ZStack(alignment: .top) {
            ForEach(Array(layout.lines.enumerated()), id: \.offset) { i, line in
                if line.y + line.height >= top - 20 && line.y <= top + viewport + 20 {
                    Text(line.text)
                        .font(Font(PrompterLayout.font(size: fontSize)))
                        .foregroundStyle(Theme.text)
                        .opacity(focus ? (i == current ? 1 : i < current ? 0.32 : (i - current <= 2 ? 0.82 : 0.6)) : 1)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(maxWidth: .infinity)
                        .offset(y: line.y - top)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Two small pink arrows marking the reading line.
struct ReadingMarks: View {
    let y: CGFloat
    let width: CGFloat

    var body: some View {
        HStack {
            Image(systemName: "arrowtriangle.right.fill")
            Spacer()
            Image(systemName: "arrowtriangle.left.fill")
        }
        .font(.system(size: 8))
        .foregroundStyle(Theme.blossom.opacity(0.85))
        .frame(width: width)
        .offset(y: y - 5)
    }
}

struct StageTopBar: View {
    let app: AppModel
    let now: Date

    var body: some View {
        let m = app.prompter!
        HStack(spacing: 6) {
            Circle().fill(m.playing ? Theme.coral : Theme.text3).frame(width: 6, height: 6)
            Text(m.current?.title ?? "").font(Theme.font(11, .semibold)).foregroundStyle(Theme.text2).lineLimit(1)
            Spacer()
            Color.clear.frame(width: app.notch.geo.notchW + 10)
            Spacer()
            if m.voiceState == .listening {
                Label(tr("Listening"), systemImage: "waveform").font(Theme.font(10.5, .semibold)).foregroundStyle(Theme.blossom)
            } else if m.voiceState == .denied {
                Label(tr("Mic not allowed"), systemImage: "mic.slash.fill").font(Theme.font(10.5, .semibold)).foregroundStyle(Theme.coral)
            }
            Text("\(TimerDisplay.clock(m.elapsed(at: now), roundUp: false)) / -\(TimerDisplay.clock(m.remaining(at: now), roundUp: true))")
                .font(Theme.mono(11, .semibold)).foregroundStyle(Theme.text2)
        }
        .padding(.horizontal, 18)
    }
}

struct StageControls: View {
    let app: AppModel

    var body: some View {
        let m = app.prompter!
        let p = app.prefs
        HStack(spacing: 2) {
            IconButton(symbol: "gobackward.5", size: 11, tint: Theme.text, hit: 26, help: tr("Back 5 seconds")) { m.back() }
            Button { m.togglePlay() } label: {
                Image(systemName: m.playing || m.countdownEnd != nil ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Color.black.opacity(0.85))
                    .frame(width: 30, height: 30).background(Circle().fill(Theme.blossom)).contentShape(Circle())
            }
            .buttonStyle(.plain)
            IconButton(symbol: "minus", size: 10, tint: Theme.text, hit: 24, help: tr("Slower")) { m.setSpeed(p.v.prompterSpeed - 10) }
            Text("\(Int(p.v.prompterSpeed))").font(Theme.mono(11, .bold)).foregroundStyle(Theme.text).frame(width: 30)
            IconButton(symbol: "plus", size: 10, tint: Theme.text, hit: 24, help: tr("Faster")) { m.setSpeed(p.v.prompterSpeed + 10) }
            IconButton(symbol: "textformat.size.smaller", size: 11, tint: Theme.text2, hit: 24, help: tr("Smaller text")) { p.v.prompterFontSize = max(16, p.v.prompterFontSize - 2) }
            IconButton(symbol: "textformat.size.larger", size: 11, tint: Theme.text2, hit: 24, help: tr("Larger text")) { p.v.prompterFontSize = min(56, p.v.prompterFontSize + 2) }
            IconButton(symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", size: 11,
                       tint: p.v.prompterMirror ? Theme.blossom : Theme.text2, hit: 24, help: tr("Mirror")) { p.v.prompterMirror.toggle() }
            IconButton(symbol: m.voiceState == .listening ? "waveform.circle.fill" : "waveform", size: 12,
                       tint: p.v.prompterVoice ? Theme.blossom : Theme.text2, hit: 24, help: tr("Voice follow")) { m.toggleVoice() }
            IconButton(symbol: "arrow.counterclockwise", size: 11, tint: Theme.text2, hit: 24, help: tr("Start over")) { m.restart() }
            IconButton(symbol: "xmark", size: 10, tint: Theme.text2, hit: 24, help: tr("Stop reading")) { m.exit() }
        }
        .padding(.horizontal, 6)
        .background(Capsule().fill(Color(hex: 0x1A1620).opacity(0.95)))
        .overlay(Capsule().strokeBorder(Theme.stroke))
    }
}

struct PrompterPane: View {
    let app: AppModel

    var body: some View {
        @Bindable var prefs = app.prefs
        Form {
            Section(tr("Reading")) {
                SliderRow(title: tr("Speed"), value: $prefs.v.prompterSpeed, range: 40...400, step: 10) { "\(Int($0)) wpm" }
                SliderRow(title: tr("Text size"), value: $prefs.v.prompterFontSize, range: 16...56) { "\(Int($0)) pt" }
                SliderRow(title: tr("Line spacing"), value: $prefs.v.prompterLineSpacing, range: 0...24) { "\(Int($0)) pt" }
                Stepper(value: $prefs.v.prompterCountdown, in: 0...10) { LabeledContent(tr("Countdown before start"), value: tr("%d s", prefs.v.prompterCountdown)) }
                Toggle(tr("Highlight the line you are reading"), isOn: $prefs.v.prompterFocusLine)
                Toggle(tr("Mirror text (for beam-splitter glass)"), isOn: $prefs.v.prompterMirror)
            }
            Section(tr("Window")) {
                SliderRow(title: tr("Width"), value: $prefs.v.prompterWidth, range: 420...900, step: 10) { "\(Int($0)) pt" }
                SliderRow(title: tr("Height"), value: $prefs.v.prompterHeight, range: 120...420, step: 10) { "\(Int($0)) pt" }
            }
            Section {
                Toggle(tr("Voice follow"), isOn: $prefs.v.prompterVoice)
                Picker(tr("Script language"), selection: $prefs.v.prompterLanguage) {
                    Text(tr("Detect from the script")).tag("auto")
                    Text("English").tag("en-US")
                    Text("Bahasa Indonesia").tag("id-ID")
                }
            } header: {
                Text(tr("Voice follow"))
            } footer: {
                Text(tr("The script moves as you speak and waits when you pause. Speech is recognised on this Mac when the language supports it. macOS asks for Microphone and Speech Recognition the first time."))
            }
            Section {
                Label(tr("The teleprompter is always hidden from screen sharing, recordings and screenshots."), systemImage: "eye.slash.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
