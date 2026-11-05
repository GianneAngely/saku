import AVFoundation
import AppKit

@MainActor
enum MirrorChecks {
    static func run(_ app: AppModel) {
        func check(_ ok: Bool, _ name: String) { SelfTest.check(ok, name) }
        let m = app.mirror!
        check(!m.running, "the camera is off by default")
        m.refreshAccess()
        check([MirrorModel.Access.unknown, .granted, .denied].contains(m.access), "camera access is read without asking")
        check(MirrorEffect.allCases.allSatisfy { e in e == .natural || !e.filters.isEmpty }, "every look has its filter")
        app.notch.mode = .open
        app.notch.mode = .closed
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        check(!m.running, "closing the notch stops the camera")
    }

    static let scenes: [Render.Scene] = [
        Render.Scene(name: "open-mirror", settle: 0.4) { app in
            app.notch.mode = .open
            app.notch.tab = .camera
        },
    ]
}
