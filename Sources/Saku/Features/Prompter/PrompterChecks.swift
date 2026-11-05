import AppKit
import SwiftUI

@MainActor
enum PrompterChecks {
    static let story = """
    Good morning everyone. Today I want to show you a tiny app that lives in the notch of my MacBook.
    It keeps my files, my clipboard and my timers in one pocket, right under the camera.
    The best part is the teleprompter, because I can read my notes and still look at all of you.
    Thank you for listening, and see you next week.
    """

    static func run(_ app: AppModel) {
        func check(_ ok: Bool, _ name: String) { SelfTest.check(ok, name) }

        // Layout: every word has a line, lines go down, the text wraps inside the column.
        let l = PrompterLayout.make(text: story, size: 26, width: 520, spacing: 6)
        let wordCount = story.split { $0.isWhitespace || $0.isNewline }.count
        check(l.words.count == wordCount && l.wordLines.count == wordCount, "every word is placed")
        check(l.lines.count >= 6, "long sentences wrap", )
        check(zip(l.lines, l.lines.dropFirst()).allSatisfy { $0.y < $1.y }, "lines go down the page")
        check(l.y(ofWord: 0) == 0 && l.y(ofWord: wordCount - 1) > l.y(ofWord: 10), "word positions")
        check(l.height > CGFloat(l.lines.count) * 26, "height covers all lines")
        let wide = PrompterLayout.make(text: story, size: 26, width: 900, spacing: 6)
        check(wide.lines.count < l.lines.count, "a wider column needs fewer lines")
        check(PrompterLayout.make(text: "", size: 26, width: 500, spacing: 6).words.isEmpty, "empty script")

        // Speech matching.
        let words = l.words
        check(ScriptMatcher.normalize("Morning,") == "morning" && ScriptMatcher.normalize("Café") == "cafe", "normalize")
        check(ScriptMatcher.distance("kitten", "sitting") == 3 && ScriptMatcher.distance("", "abc") == 3, "edit distance")
        let i1 = ScriptMatcher.locate(script: words, current: 0, heard: ["good", "morning", "everyone"])
        check(i1 == 2, "finds the start")
        let i2 = ScriptMatcher.locate(script: words, current: 2, heard: ["today", "i", "want", "to", "show", "you"])
        check(i2 == 8, "follows along")
        let i3 = ScriptMatcher.locate(script: words, current: 8, heard: ["a", "tiny", "app", "that", "lifts", "in", "the", "notch"])
        check(i3 == 16, "tolerates a misheard word")
        let i4 = ScriptMatcher.locate(script: words, current: 16, heard: ["banana", "spaceship"])
        check(i4 == nil, "ignores words that are not in the script")
        let teleIndex = words.firstIndex(of: "teleprompter")!
        let i5 = ScriptMatcher.locate(script: words, current: 18, heard: ["the", "best", "part", "is", "the", "teleprompter"])
        check(i5 == teleIndex, "jumps ahead when you skip a sentence")

        // Playback engine.
        let m = app.prompter!
        app.prefs.v.prompterCountdown = 0
        app.prefs.v.prompterVoice = false
        let s = m.add(title: "Demo", text: story)
        m.selected = s.id
        m.start()
        check(m.live && m.playing && app.keepOpenReasons.contains("prompter"), "start shows the stage and plays")
        check(app.openSize == app.prompterSize, "the notch takes the prompter size")
        let t0 = Date()
        let o1 = m.offset(at: t0.addingTimeInterval(2))
        check(o1 > 0 && abs(o1 - m.offset(at: t0) - 2 * m.pointsPerSecond) < 2, "scrolls at the chosen speed")
        let expected = Double(wordCount) / 140 * 60
        check(abs(Double(m.maxOffset / m.pointsPerSecond) - expected) < expected * 0.12, "reading time matches words per minute")
        m.pause(now: t0.addingTimeInterval(3))
        let paused = m.offset(at: t0.addingTimeInterval(3))
        check(!m.playing && abs(m.offset(at: t0.addingTimeInterval(60)) - paused) < 0.01, "pause holds the text")
        m.nudge(40)
        check(abs(m.offset(at: Date()) - (paused + 40)) < 0.5, "trackpad scroll moves the text")
        m.nudge(-10_000)
        check(m.offset(at: Date()) == 0, "cannot scroll above the start")
        m.nudge(100_000)
        check(m.offset(at: Date()) == m.maxOffset, "cannot scroll past the end")
        m.restart()
        m.togglePlay()
        let before = m.offset(at: Date())
        m.setSpeed(280)
        check(abs(m.offset(at: Date()) - before) < 3 && app.prefs.v.prompterSpeed == 280, "speed change keeps the place")
        m.back(seconds: 5)
        check(m.offset(at: Date()) < 1, "back 5 seconds stops at the top")
        app.prefs.v.prompterSpeed = 140

        // Voice: heard words move the stage to their line.
        m.heard(["the", "best", "part", "is", "the", "teleprompter"])
        check(m.spokenWord == teleIndex, "voice moves the reading position")
        check(abs(m.voiceOffset - m.layout.y(ofWord: teleIndex)) < 0.5, "voice offset is the word's line")

        m.exit()
        check(!m.live && !app.keepOpenReasons.contains("prompter"), "exit")
        check(app.openSize.width == app.prefs.v.openWidth, "the notch returns to its normal size")

        // Library.
        var edited = s
        edited.text = "Short one."
        m.update(edited)
        check(m.current?.words == 2, "script edit")
        m.delete(s.id)
        check(!m.scripts.contains { $0.id == s.id }, "script delete")
        m.saveNow()
        check(JSONStore<[Script]>("scripts.json").load()?.count == m.scripts.count, "scripts are saved")
        app.prefs.v.prompterCountdown = 3

        // Language detection for speech.
        let id = m.add(title: "ID", text: "Halo semuanya, terima kasih sudah datang. Hari ini saya mau menunjukkan aplikasi kecil di notch MacBook saya.")
        m.selected = id.id
        check(m.speechLocale.identifier == "id-ID", "Indonesian script listens in Indonesian")
        m.delete(id.id)
    }

    /// Short live run: the panel goes into prompter mode, hides from screen sharing, and comes back.
    static func live(_ app: AppModel, _ c: NotchController) async {
        app.prefs.v.prompterCountdown = 0
        app.prefs.v.hideFromScreenSharing = false
        let m = app.prompter!
        m.selected = m.scripts.first?.id
        m.start()
        try? await Task.sleep(for: .seconds(0.4))
        LiveTest.expect(app.notch.mode == .open && m.live, "prompter opens the notch")
        LiveTest.expect(c.panel.sharingType == .none, "prompter is hidden from screen sharing")
        let r = c.interactiveRect
        LiveTest.expect(abs(r.width - app.prefs.v.prompterWidth) < 0.5, "panel has the prompter width")
        c.pointerOverride = LiveTest.away
        c.pointer(at: LiveTest.away)
        try? await Task.sleep(for: .seconds(app.prefs.v.closeDelay + 0.3))
        LiveTest.expect(app.notch.mode == .open, "prompter stays open when the mouse leaves")
        m.exit()
        try? await Task.sleep(for: .seconds(0.3))
        LiveTest.expect(c.panel.sharingType == .readOnly, "screen sharing visibility returns after reading")
        c.close()
        app.prefs.v.prompterCountdown = 3
    }

    static let scenes: [Render.Scene] = [
        Render.Scene(name: "open-prompter", settle: 0.5) { app in
            let m = app.prompter!
            let s = m.add(title: "Weekly demo", text: story)
            m.selected = s.id
            app.notch.mode = .open
            app.notch.tab = .prompter
        },
        Render.Scene(name: "prompter-reading", settle: 0.5) { app in
            stage(app, at: 0.32)
        },
        Render.Scene(name: "prompter-countdown", settle: 0.3) { app in
            app.prefs.v.prompterCountdown = 3
            let m = app.prompter!
            let s = m.add(title: "Weekly demo", text: story)
            m.selected = s.id
            m.start()
            app.notch.mode = .open
        },
        Render.Scene(name: "prompter-mirror", settle: 0.5) { app in
            app.prefs.v.prompterMirror = true
            stage(app, at: 0.2)
        },
    ]

    static func stage(_ app: AppModel, at fraction: CGFloat) {
        app.prefs.v.prompterCountdown = 0
        let m = app.prompter!
        if m.live { m.exit() }
        let s = m.add(title: "Weekly demo", text: story)
        m.selected = s.id
        m.start()
        m.pause()
        m.nudge(m.maxOffset * fraction)
        app.notch.mode = .open
    }
}
