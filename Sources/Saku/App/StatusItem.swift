import AppKit

/// Optional menu bar icon: open the notch, settings, quit.
@MainActor
final class StatusItemController: NSObject {
    private let item: NSStatusItem
    private let app: AppModel
    private weak var notch: NotchController?

    init(app: AppModel, notch: NotchController) {
        self.app = app
        self.notch = notch
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        item.button?.image = Self.icon()
        item.button?.toolTip = "Saku"
        let menu = NSMenu()
        menu.addItem(withTitle: tr("Open Saku"), action: #selector(openNotch), keyEquivalent: "").target = self
        menu.addItem(withTitle: tr("Settings…"), action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("Quit Saku"), action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
    }

    func remove() { NSStatusBar.system.removeStatusItem(item) }

    @objc private func openNotch() { notch?.open() }
    @objc private func openSettings() { app.commands.openSettings(nil) }
    @objc private func quit() { NSApp.terminate(nil) }

    /// Template blossom: five petals around a hollow centre.
    static func icon() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
            let c = CGPoint(x: r.midX, y: r.midY)
            let petals = NSBezierPath()
            for i in 0..<5 {
                let a = CGFloat(i) * 2 * .pi / 5 + .pi / 2
                let center = CGPoint(x: c.x + cos(a) * 4.3, y: c.y + sin(a) * 4.3)
                petals.append(NSBezierPath(ovalIn: CGRect(x: center.x - 3.4, y: center.y - 3.4, width: 6.8, height: 6.8)))
            }
            petals.windingRule = .nonZero
            NSColor.black.setFill()
            petals.fill()
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: CGRect(x: c.x - 1.9, y: c.y - 1.9, width: 3.8, height: 3.8)).fill()
            return true
        }
        img.isTemplate = true
        return img
    }
}
