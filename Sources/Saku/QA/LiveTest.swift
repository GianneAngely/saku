import AppKit
import SwiftUI

/// `Saku --livetest`: a short real run of the notch panel (a few seconds on screen, silent).
/// The pointer is simulated through `pointerOverride`; the real mouse is never moved.
@MainActor
enum LiveTest {
    private static var results: [(String, Bool, String)] = []

    static func expect(_ ok: Bool, _ name: String, _ detail: String = "") {
        results.append((name, ok, detail))
    }

    /// Feature branches append steps here.
    static var steps: [(String, @MainActor (AppModel, NotchController) async -> Void)] = [
        ("panel", panel),
        ("hover", hover),
        ("alert", alert),
        ("keyboard", keyboard),
    ]

    static func run(app: AppModel, controller: NotchController) {
        Task { @MainActor in
            for (_, step) in steps { await step(app, controller) }
            controller.pointerOverride = nil
            let failed = results.filter { !$0.1 }
            for r in results { print("\(r.1 ? "PASS" : "FAIL") \(r.0)\(r.2.isEmpty ? "" : "  [\(r.2)]")") }
            print("livetest: \(results.count - failed.count) passed, \(failed.count) failed")
            controller.stop()
            QA.cleanUp()
            exit(failed.isEmpty ? 0 : 1)
        }
    }

    static func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

    static var away: CGPoint { CGPoint(x: NSScreen.screens[0].frame.midX, y: NSScreen.screens[0].frame.midY - 200) }

    static func panel(_ app: AppModel, _ c: NotchController) async {
        await wait(0.3)
        let p = c.panel!
        let g = app.notch.geo
        expect(p.isVisible, "panel visible")
        expect(p.level.rawValue == NSWindow.Level.statusBar.rawValue + 1, "panel above the menu bar")
        expect(p.collectionBehavior.contains(.canJoinAllSpaces) && p.collectionBehavior.contains(.fullScreenAuxiliary), "panel on all spaces")
        expect(abs(p.frame.midX - (g.screenFrame.minX + g.midX)) < 0.6, "panel centred on the notch", "\(p.frame.midX)")
        expect(abs(p.frame.maxY - g.screenFrame.maxY) < 0.6, "panel flush with the top edge")
        expect(p.ignoresMouseEvents, "clicks pass through while closed")
        expect(!p.canBecomeKey, "closed panel never takes the keyboard")
    }

    static func hover(_ app: AppModel, _ c: NotchController) async {
        let g = app.notch.geo
        let notchCentre = CGPoint(x: g.screenFrame.minX + g.midX, y: g.screenFrame.maxY - g.notchH / 2)
        c.pointerOverride = notchCentre
        c.pointer(at: notchCentre)
        expect(app.notch.mode == .closed, "does not open before the hover delay")
        expect(app.notch.hovering, "the pointer on the closed notch counts as hovering")
        await wait(app.prefs.v.hoverDelay + 0.2)
        expect(app.notch.mode == .open, "hover opens the notch")
        c.pointer(at: notchCentre)
        expect(!c.panel.ignoresMouseEvents, "open panel takes the mouse under the pointer")
        expect(c.panel.canBecomeKey, "open panel may take the keyboard")
        let open = c.interactiveRect
        expect(abs(open.width - app.prefs.v.openWidth) < 0.1 && abs(open.height - app.prefs.v.openHeight) < 0.1, "open size matches settings")

        // Top-row edge: the very first pixel row counts as inside.
        expect(c.hit(open, CGPoint(x: open.midX, y: open.maxY)), "top screen row is inside")

        // Leave: closes after the close delay.
        c.pointerOverride = away
        c.pointer(at: away)
        expect(c.panel.ignoresMouseEvents, "clicks pass through outside the panel")
        expect(app.notch.mode == .open, "stays open during the close delay")
        await wait(app.prefs.v.closeDelay + 0.25)
        expect(app.notch.mode == .closed, "leaving closes the notch")
        expect(!app.notch.hovering, "and the closed notch no longer counts as hovering")

        // Pinned: stays open.
        c.pointerOverride = notchCentre
        c.open()
        app.notch.pinned = true
        c.pointerOverride = away
        c.pointer(at: away)
        await wait(app.prefs.v.closeDelay + 0.25)
        expect(app.notch.mode == .open, "pinned notch stays open")
        app.notch.pinned = false
        c.pointer(at: away)
        await wait(app.prefs.v.closeDelay + 0.25)
        expect(app.notch.mode == .closed, "unpinned notch closes")

        // Moving past the side of the notch (menu bar) does not open it.
        let beside = CGPoint(x: notchCentre.x + g.notchW, y: notchCentre.y)
        c.pointerOverride = beside
        c.pointer(at: beside)
        await wait(app.prefs.v.hoverDelay + 0.2)
        expect(app.notch.mode == .closed, "menu bar beside the notch does not open it")

        // Quick pass over the notch shorter than the hover delay does not open it.
        app.prefs.v.hoverDelay = 0.3
        c.pointerOverride = notchCentre
        c.pointer(at: notchCentre)
        await wait(0.1)
        c.pointerOverride = away
        c.pointer(at: away)
        await wait(0.35)
        expect(app.notch.mode == .closed, "a quick pass does not open")
        app.prefs.v.hoverDelay = PrefsData().hoverDelay
    }

    /// A shortcut opens the notch without the pointer there; it stays until the pointer visits and leaves.
    static func keyboard(_ app: AppModel, _ c: NotchController) async {
        c.pointerOverride = away
        c.close()
        c.toggleFromKeyboard(.timers, typing: false)
        expect(app.notch.mode == .open && app.notch.tab == .timers, "shortcut opens the notch on a tab")
        c.pointer(at: away)
        await wait(app.prefs.v.closeDelay + 0.3)
        expect(app.notch.mode == .open, "stays open while the pointer is elsewhere")
        let g = app.notch.geo
        let inside = CGPoint(x: g.screenFrame.minX + g.midX, y: g.screenFrame.maxY - 60)
        c.pointerOverride = inside
        c.pointer(at: inside)
        c.pointerOverride = away
        c.pointer(at: away)
        await wait(app.prefs.v.closeDelay + 0.3)
        expect(app.notch.mode == .closed, "closes after the pointer visited and left")
        c.toggleFromKeyboard(.timers, typing: false)
        c.toggleFromKeyboard(.timers, typing: false)
        expect(app.notch.mode == .closed, "the same shortcut closes it again")
        c.toggleFromKeyboard(.clipboard, typing: true)
        await wait(0.3)
        expect(c.panel.isKeyWindow, "typing tabs take the keyboard")
        c.close()
        await wait(0.2)
        expect(!c.panel.isKeyWindow, "closing gives the keyboard back")
    }

    static func alert(_ app: AppModel, _ c: NotchController) async {
        c.pointerOverride = away
        var ran = false
        app.present(NotchAlert(title: "Test", subtitle: "Live test alert", actions: [AlertAction(title: "OK", primary: true) { ran = true }], autoDismiss: 0.6))
        await wait(0.2)
        expect(app.notch.alert != nil, "alert shows")
        expect(c.interactiveRect.size == NotchController.alertSize, "alert has its own size")
        await wait(0.7)
        expect(app.notch.alert == nil, "alert dismisses itself")
        expect(!ran, "auto-dismiss does not run the action")

        app.flash("checkmark", "Copied", seconds: 0.4)
        expect(app.liveActivity.wing > 0, "hud shows in the wings")
        await wait(0.6)
        expect(app.notch.hud == nil, "hud clears")
    }
}
