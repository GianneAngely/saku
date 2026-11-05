import AppKit
import Observation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let options: LaunchOptions
    private(set) var app: AppModel!
    private(set) var notch: NotchController!
    private var status: StatusItemController?
    private var settings: SettingsWindowController?

    init(options: LaunchOptions) {
        self.options = options
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let dir = options.dataDir { Paths.dataDir = URL(fileURLWithPath: dir, isDirectory: true) }
        let defaults = options.qa ? (UserDefaults(suiteName: QA.suiteName) ?? .standard) : .standard
        if options.qa && options.dataDir == nil {
            Paths.dataDir = FileManager.default.temporaryDirectory.appendingPathComponent("saku-qa-\(getpid())", isDirectory: true)
        }
        app = AppModel(options: options, defaults: defaults)
        notch = NotchController(app: app)
        app.commands = Commands(
            openSettings: { [weak self] pane in self?.showSettings(pane) },
            openNotch: { [weak self] tab in self?.notch.open(tab) },
            toggleNotch: { [weak self] tab, typing in self?.notch.toggleFromKeyboard(tab, typing: typing) },
            closeNotch: { [weak self] in self?.notch.close() }
        )
        Features.install(app)

        if let dir = options.iconDir {
            IconArt.writeIconset(to: URL(fileURLWithPath: dir, isDirectory: true))
            QA.cleanUp()
            exit(0)
        }
        if let dir = options.renderDir {
            Render.run(app: app, to: URL(fileURLWithPath: dir, isDirectory: true))
            NSApp.terminate(nil)
            return
        }
        if options.selfTest {
            let ok = SelfTest.run(app: app)
            exit(ok ? 0 : 1)
        }

        notch.start()
        if options.liveTest {
            LiveTest.run(app: app, controller: notch)
            return
        }
        applyChrome()
        observeChrome()
        DistributedNotificationCenter.default().addObserver(forName: .init("local.saku.app.show"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showSettings(nil) }
        }
        if !app.prefs.v.onboarded { showSettings("welcome") }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(nil)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Features.shutdown(app)
    }

    /// Dock icon and menu bar icon follow the General settings.
    private func applyChrome() {
        let p = app.prefs.v
        let wantRegular = p.showInDock || (settings?.window?.isVisible ?? false)
        NSApp.setActivationPolicy(wantRegular ? .regular : .accessory)
        if p.showMenuBarIcon {
            if status == nil { status = StatusItemController(app: app, notch: notch) }
        } else {
            status?.remove()
            status = nil
        }
    }

    private func observeChrome() {
        withObservationTracking {
            _ = (app.prefs.v.showInDock, app.prefs.v.showMenuBarIcon)
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.applyChrome()
                self?.observeChrome()
            }
        }
    }

    func showSettings(_ pane: String?) {
        if settings == nil {
            settings = SettingsWindowController(app: app) { [weak self] in
                DispatchQueue.main.async { self?.applyChrome() }
            }
        }
        notch.close()
        NSApp.setActivationPolicy(.regular)
        settings?.show(pane: pane)
    }
}
