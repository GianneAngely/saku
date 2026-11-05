import AppKit
import NaturalLanguage
import Observation
import SwiftUI

struct Script: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var text: String
    var updated = Date()

    var words: Int { text.split { $0.isWhitespace || $0.isNewline }.count }
}

/// Line breaks and word positions of a script, computed with TextKit so the stage draws exactly these lines
/// and voice follow can turn "word 42" into a y position.
struct PrompterLayout: Equatable {
    struct Line: Equatable {
        var text: String
        var y: CGFloat
        var height: CGFloat
        var firstWord: Int          // index of the first word on this line (or of the next word for empty lines)
    }

    var lines: [Line] = []
    var wordLines: [Int] = []       // line index of every word
    var words: [String] = []        // normalized words, for matching speech
    var height: CGFloat = 0

    static func font(size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .semibold)
        return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }

    static func make(text: String, size: CGFloat, width: CGFloat, spacing: CGFloat) -> PrompterLayout {
        let font = font(size: size)
        let para = NSMutableParagraphStyle()
        para.lineSpacing = spacing
        para.alignment = .center
        let storage = NSTextStorage(string: text, attributes: [.font: font, .paragraphStyle: para])
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: max(40, width), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)

        let ns = text as NSString
        // Word ranges (same rule as ScriptMatcher: whitespace separated).
        var wordRanges: [NSRange] = []
        var words: [String] = []
        let scanner = ns
        var i = 0
        while i < scanner.length {
            while i < scanner.length, let u = UnicodeScalar(scanner.character(at: i)), CharacterSet.whitespacesAndNewlines.contains(u) { i += 1 }
            let start = i
            while i < scanner.length, let u = UnicodeScalar(scanner.character(at: i)), !CharacterSet.whitespacesAndNewlines.contains(u) { i += 1 }
            if i > start {
                wordRanges.append(NSRange(location: start, length: i - start))
                words.append(ScriptMatcher.normalize(ns.substring(with: NSRange(location: start, length: i - start))))
            }
        }

        var out = PrompterLayout()
        out.words = words
        var w = 0
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { rect, _, _, glyphs, _ in
            let chars = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            let lineText = ns.substring(with: chars).trimmingCharacters(in: .newlines)
            let first = w
            while w < wordRanges.count, NSMaxRange(wordRanges[w]) <= NSMaxRange(chars) {
                out.wordLines.append(out.lines.count)
                w += 1
            }
            out.lines.append(Line(text: lineText, y: rect.minY, height: rect.height, firstWord: first))
        }
        while out.wordLines.count < words.count { out.wordLines.append(max(0, out.lines.count - 1)) }
        out.height = manager.usedRect(for: container).height
        return out
    }

    /// y (top of the line) of a word.
    func y(ofWord i: Int) -> CGFloat {
        guard !wordLines.isEmpty else { return 0 }
        let l = wordLines[max(0, min(wordLines.count - 1, i))]
        return lines[l].y
    }
}

/// Finds where in the script the speaker is, from the last few recognised words.
enum ScriptMatcher {
    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    static func similar(_ a: String, _ b: String) -> Double {
        if a.isEmpty || b.isEmpty { return 0 }
        if a == b { return 1 }
        if a.count >= 4 && b.count >= 4 && (a.hasPrefix(b) || b.hasPrefix(a)) { return 0.75 }
        if min(a.count, b.count) >= 4 && distance(a, b) <= 1 { return 0.7 }
        if min(a.count, b.count) >= 7 && distance(a, b) <= 2 { return 0.6 }
        return 0
    }

    static func distance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var prev = Array(0...y.count)
        for i in 1...x.count {
            var cur = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[y.count]
    }

    /// Index of the script word the speaker just said, or nil when the tail does not match well enough.
    /// Looks a little back (re-reading) and further ahead (skipping), prefers staying close.
    static func locate(script: [String], current: Int, heard rawHeard: [String], lookBack: Int = 8, lookAhead: Int = 45) -> Int? {
        let heard = rawHeard.map(normalize).filter { !$0.isEmpty }
        guard !script.isEmpty, !heard.isEmpty else { return nil }
        let tail = Array(heard.suffix(5))
        var best: (Int, Double)?
        let lo = max(0, current - lookBack), hi = min(script.count - 1, current + lookAhead)
        guard lo <= hi else { return nil }
        for j in lo...hi {
            var score = 0.0, matched = 0
            for k in 0..<tail.count {
                let si = j - k
                guard si >= 0 else { break }
                let s = similar(tail[tail.count - 1 - k], script[si])
                if s > 0 { matched += 1 }
                score += s * (k == 0 ? 1.4 : 1)
            }
            score -= 0.012 * Double(abs(j - current))
            let needed = tail.count >= 3 ? 2 : tail.count
            if matched >= needed, score > (best?.1 ?? 0.9) { best = (j, score) }
        }
        return best?.0
    }
}

@MainActor @Observable
final class PrompterModel {
    private(set) var scripts: [Script] = []
    var selected: UUID?

    /// The reading stage is showing in the notch.
    private(set) var live = false
    private(set) var playing = false
    private(set) var countdownEnd: Date?
    private(set) var finished = false
    /// Voice follow: the stage follows the spoken word instead of the clock.
    private(set) var voiceState: VoiceFollower.State = .off
    private(set) var spokenWord = 0
    /// Animated offset while following the voice.
    var voiceOffset: CGFloat = 0

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let store = JSONStore<[Script]>("scripts.json")
    @ObservationIgnored private let saver = Debouncer(0.5)
    @ObservationIgnored private var base: CGFloat = 0
    @ObservationIgnored private var playStart: Date?
    @ObservationIgnored private var endWork: DispatchWorkItem?
    @ObservationIgnored private var countWork: DispatchWorkItem?
    @ObservationIgnored private var cache: (key: String, layout: PrompterLayout)?
    @ObservationIgnored var voice: VoiceFollower?

    /// Distance from the top of the text window to the reading line (just under the camera).
    static let readingLine: CGFloat = 16

    init(app: AppModel) {
        self.app = app
        scripts = store.load() ?? []
        if scripts.isEmpty { scripts = [Self.sample] }
        selected = scripts.first?.id
    }

    static var sample: Script {
        Lang.shared.isIndonesian ? Script(title: "Naskah sambutan", text: welcomeID) : Script(title: "Welcome script", text: welcomeEN)
    }

    static let welcomeEN = """
    Hi! This is Saku's teleprompter. Your words scroll right under the camera, so your eyes stay on the lens and people feel like you are looking at them.

    Press play and read at your own pace. Use plus and minus to change the speed, or scroll with the trackpad to jump around.

    Turn on Voice follow and the script moves with you as you speak. Pause, and it waits for you.

    Nobody in a call can see this script. It is hidden from screen sharing and screenshots.
    """

    static let welcomeID = """
    Hai! Ini teleprompter Saku. Kata-katamu bergulir tepat di bawah kamera, jadi matamu tetap ke lensa dan orang merasa kamu sedang menatap mereka.

    Tekan putar dan baca sesuai tempomu. Pakai plus dan minus untuk mengubah kecepatan, atau gulir dengan trackpad untuk lompat.

    Nyalakan Ikuti suara dan naskah bergerak mengikuti ucapanmu. Berhenti sebentar, dan naskah ikut menunggu.

    Tidak ada orang di panggilan yang bisa melihat naskah ini. Naskah tersembunyi dari berbagi layar dan tangkapan layar.
    """

    var current: Script? { scripts.first { $0.id == selected } }

    // MARK: Library

    @discardableResult
    func add(title: String = "", text: String = "") -> Script {
        let s = Script(title: title.isEmpty ? tr("New script") : title, text: text)
        scripts.insert(s, at: 0)
        selected = s.id
        changed()
        return s
    }

    func update(_ s: Script) {
        guard let i = scripts.firstIndex(where: { $0.id == s.id }), scripts[i] != s else { return }
        var n = s
        n.updated = Date()
        scripts[i] = n
        changed()
    }

    func delete(_ id: UUID) {
        scripts.removeAll { $0.id == id }
        if scripts.isEmpty { scripts = [Self.sample] }
        if selected == id { selected = scripts.first?.id }
        changed()
    }

    private func changed() { saver.run { [weak self] in self?.saveNow() } }
    func saveNow() { store.save(scripts) }

    // MARK: Layout

    var p: PrefsData { app.prefs.v }

    /// Width of the text column on the stage.
    var columnWidth: CGFloat { CGFloat(p.prompterWidth) - 56 }

    var layout: PrompterLayout {
        let text = current?.text ?? ""
        let key = "\(text.hashValue)|\(p.prompterFontSize)|\(columnWidth)|\(p.prompterLineSpacing)"
        if let c = cache, c.key == key { return c.layout }
        let l = PrompterLayout.make(text: text, size: p.prompterFontSize, width: columnWidth, spacing: p.prompterLineSpacing)
        cache = (key, l)
        return l
    }

    /// Scroll speed that reads the script at the chosen words per minute.
    var pointsPerSecond: CGFloat {
        let l = layout
        guard !l.words.isEmpty else { return 30 }
        return CGFloat(p.prompterSpeed / 60) * (l.height / CGFloat(l.words.count))
    }

    var maxOffset: CGFloat { max(0, layout.height - (layout.lines.last?.height ?? 0)) }

    func offset(at now: Date) -> CGFloat {
        if voiceState == .listening { return voiceOffset }
        guard playing, let s = playStart else { return base }
        return min(maxOffset, base + CGFloat(now.timeIntervalSince(s)) * pointsPerSecond)
    }

    func elapsed(at now: Date) -> Double { Double(offset(at: now) / max(1, pointsPerSecond)) }
    func remaining(at now: Date) -> Double { Double((maxOffset - offset(at: now)) / max(1, pointsPerSecond)) }

    // MARK: Playback

    /// Shows the stage and starts after the countdown.
    func start() {
        guard current != nil else { return }
        live = true
        finished = false
        base = 0
        voiceOffset = 0
        spokenWord = 0
        app.keepOpenReasons.insert("prompter")
        app.notch.tab = .prompter
        app.commands.openNotch(.prompter)
        if p.prompterVoice { startVoice() }
        countdown()
    }

    private func countdown() {
        countWork?.cancel()
        let n = max(0, p.prompterCountdown)
        guard n > 0 else { play(); return }
        countdownEnd = Date().addingTimeInterval(Double(n))
        let w = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.countdownEnd = nil
                self?.play()
            }
        }
        countWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(n), execute: w)
    }

    func togglePlay() {
        if countdownEnd != nil { countWork?.cancel(); countdownEnd = nil; return }
        if playing { pause() } else {
            if finished { base = 0; voiceOffset = 0; spokenWord = 0; finished = false }
            play()
        }
    }

    private func play(now: Date = Date()) {
        guard live else { return }
        playing = true
        playStart = now
        scheduleEnd()
    }

    func pause(now: Date = Date()) {
        base = offset(at: now)
        playing = false
        playStart = nil
        endWork?.cancel()
    }

    /// Moves the text by `points` (trackpad scroll, back 5 s). Keeps playing if it was.
    func nudge(_ points: CGFloat, now: Date = Date()) {
        let o = min(maxOffset, max(0, offset(at: now) + points))
        if voiceState == .listening {
            voiceOffset = o
            spokenWord = layout.lines.firstIndex { $0.y >= o }.map { layout.lines[$0].firstWord } ?? spokenWord
            return
        }
        base = o
        if playing { playStart = now; scheduleEnd() }
        finished = false
    }

    func back(seconds: Double = 5) { nudge(-CGFloat(seconds) * pointsPerSecond) }

    func setSpeed(_ wpm: Double, now: Date = Date()) {
        let o = offset(at: now)
        app.prefs.v.prompterSpeed = min(400, max(40, wpm))
        base = o
        if playing { playStart = now; scheduleEnd() }
    }

    func restart() {
        base = 0
        voiceOffset = 0
        spokenWord = 0
        finished = false
        if playing { playStart = Date(); scheduleEnd() }
    }

    func exit() {
        pause()
        countWork?.cancel()
        countdownEnd = nil
        stopVoice()
        live = false
        app.keepOpenReasons.remove("prompter")
    }

    private func scheduleEnd() {
        endWork?.cancel()
        guard playing, voiceState != .listening else { return }
        let left = Double((maxOffset - offset(at: Date())) / max(1, pointsPerSecond))
        let w = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.playing else { return }
                self.pause()
                self.base = self.maxOffset
                self.finished = true
            }
        }
        endWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.05, left), execute: w)
    }

    // MARK: Voice follow

    func toggleVoice() {
        app.prefs.v.prompterVoice.toggle()
        if app.prefs.v.prompterVoice, live { startVoice() } else { stopVoice() }
    }

    func startVoice() {
        if voice == nil { voice = VoiceFollower() }
        voice?.onState = { [weak self] s in self?.voiceChanged(s) }
        voice?.onWords = { [weak self] w in self?.heard(w) }
        voiceOffset = offset(at: Date())
        voice?.start(locale: speechLocale)
    }

    func stopVoice() {
        voice?.stop()
        voiceState = .off
    }

    private func voiceChanged(_ s: VoiceFollower.State) {
        let wasListening = voiceState == .listening
        voiceState = s
        if s == .listening && !wasListening {
            pause()
            voiceOffset = base
        } else if s != .listening && wasListening {
            base = voiceOffset
        }
    }

    /// Feeds recognised words; moves the stage to the matching line.
    func heard(_ words: [String]) {
        let l = layout
        guard let i = ScriptMatcher.locate(script: l.words, current: spokenWord, heard: words) else { return }
        spokenWord = i
        let target = min(maxOffset, max(0, l.y(ofWord: i)))
        withAnimation(.easeOut(duration: 0.55)) { voiceOffset = target }
        if i >= l.words.count - 1 { finished = true }
    }

    /// Script language for speech: chosen in settings, or detected from the text.
    var speechLocale: Locale {
        switch p.prompterLanguage {
        case "auto":
            let r = NLLanguageRecognizer()
            r.processString(current?.text ?? "")
            return r.dominantLanguage == .indonesian ? Locale(identifier: "id-ID") : Locale(identifier: "en-US")
        default:
            return Locale(identifier: p.prompterLanguage)
        }
    }
}
