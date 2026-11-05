import AppKit
import Observation
import SwiftUI

/// Owns the notch panel: placement, hover to open, leave to close, click-through, drag-and-drop, hiding.
@MainActor
final class NotchController: NSObject {
    let app: AppModel
    private(set) var panel: NotchPanel!
    private var observers: [NSObjectProtocol] = []
    private var monitors: [Any] = []
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var dragBaseline = NSPasteboard(name: .drag).changeCount
    private var mouseDown = false

    /// Opened with a keyboard shortcut: stays open until the pointer has visited the panel (or Esc / click outside).
    private(set) var openedByKeyboard = false

    /// Live tests set this instead of moving the real pointer.
    var pointerOverride: CGPoint?
    var pointerLocation: CGPoint { pointerOverride ?? NSEvent.mouseLocation }

    /// Extra room around the open panel for its shadow.
    static let margin = 40.0
    static let alertSize = CGSize(width: 430, height: 112)

    init(app: AppModel) {
        self.app = app
        super.init()
    }

    // MARK: Setup

    func start() {
        let panel = NotchPanel(frame: .zero)
        let host = NotchHostingView(rootView: NotchRootView(app: app, controller: self))
        host.sizingOptions = []
        panel.contentView = host
        panel.ignoresMouseEvents = true
        self.panel = panel
        relayout()
        panel.orderFrontRegardless()
        installMonitors()
        observeSystem()
        observePrefs()
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        observers.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        observers.removeAll()
        panel?.orderOut(nil)
    }

    var geo: NotchGeo { app.notch.geo }

    func relayout() {
        let p = app.prefs.v
        app.notch.geo = NotchGeo.detect(widthOffset: p.notchWidthOffset, heightOffset: p.notchHeightOffset)
        let m = app.maxPanelSize
        panel.setFrame(geo.topRect(width: m.width + 2 * Self.margin, height: m.height + Self.margin), display: true)
        panel.sharingType = p.hideFromScreenSharing || app.prompter?.live == true ? .none : .readOnly
        updateVisibility()
    }

    private func observePrefs() {
        withObservationTracking {
            let p = app.prefs.v
            _ = (p.openWidth, p.openHeight, p.notchWidthOffset, p.notchHeightOffset, p.hideFromScreenSharing,
                 p.hideInFullscreen, p.hideWhileMirroring, p.notchlessScreens, p.prompterWidth, p.prompterHeight, p.webWidth, p.webHeight)
            _ = app.prompter?.live
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.relayout()
                self.observePrefs()
            }
        }
    }

    private func observeSystem() {
        let nc = NotificationCenter.default, ws = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.relayout() }
        })
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.updateVisibility()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { MainActor.assumeIsolated { self?.updateVisibility() } }
                }
            })
        }
        observers.append(ws.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.app.notch.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        })
        observers.append(nc.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.app.notch.mode == .open, !self.app.notch.pinned else { return }
                if !self.hit(self.interactiveRect, self.pointerLocation) { self.close() }
            }
        })
    }

    private func installMonitors() {
        let types: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp, .rightMouseDown]
        if let s = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] e in
            let dy = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY : e.scrollingDeltaY * 12
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.app.notch.isOpen, self.hit(self.interactiveRect, self.pointerLocation) else { return false }
                return self.app.scrollHandler?(dy) ?? false
            }
            return handled ? nil : e
        }) { monitors.append(s) }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: types, handler: { [weak self] e in
            let type = e.type
            MainActor.assumeIsolated { self?.handle(type, at: self?.pointerLocation ?? NSEvent.mouseLocation, local: false) }
        }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: types.union(.keyDown), handler: { [weak self] e in
            MainActor.assumeIsolated {
                guard let self else { return }
                if e.type == .keyDown {
                    if e.keyCode == 53, e.window === self.panel, self.app.notch.isOpen { self.close(); return }
                } else {
                    self.handle(e.type, at: self.pointerLocation, local: true)
                }
            }
            return e
        }) { monitors.append(l) }
    }

    // MARK: Geometry

    /// The black shape's current rect in global coordinates: what takes the mouse.
    var interactiveRect: CGRect {
        let s = app.notch
        let size: CGSize
        if s.isOpen { size = app.openSize }
        else if s.alert != nil { size = Self.alertSize }
        else { size = app.closedSize }
        return geo.topRect(width: size.width, height: size.height)
    }

    /// Where the pointer has to be to open the closed notch.
    var hotZone: CGRect { interactiveRect.insetBy(dx: -4, dy: -3) }

    /// `contains` that also counts the screen's very top row (a rect's maxY edge is otherwise outside).
    func hit(_ r: CGRect, _ p: CGPoint) -> Bool {
        p.x >= r.minX && p.x <= r.maxX && p.y >= r.minY && p.y <= r.maxY + 1
    }

    // MARK: Pointer

    func handle(_ type: NSEvent.EventType, at p: CGPoint, local: Bool) {
        switch type {
        case .mouseMoved: pointer(at: p)
        case .leftMouseDown:
            mouseDown = true
            dragBaseline = NSPasteboard(name: .drag).changeCount
            if !local, app.notch.mode == .open, !app.notch.pinned, !hit(interactiveRect, p) { close() }
        case .rightMouseDown:
            if !local, app.notch.mode == .open, !app.notch.pinned, !hit(interactiveRect, p) { close() }
        case .leftMouseDragged: dragMoved(at: p)
        case .leftMouseUp:
            mouseDown = false
            dragEnded()
            pointer(at: p)
        default: break
        }
    }

    func pointer(at p: CGPoint) {
        guard !app.notch.hidden else { return }
        let s = app.notch
        let inside = hit(interactiveRect, p)
        setIgnoresMouse(!inside)
        switch s.mode {
        case .closed:
            guard s.alert == nil else { return }
            if hit(hotZone, p) { scheduleOpen() } else { cancelOpen() }
        case .open:
            if inside { openedByKeyboard = false }
            if inside { cancelClose() } else if !keepOpen && !openedByKeyboard { scheduleClose() }
        case .drop:
            break
        }
    }

    private func setIgnoresMouse(_ ignore: Bool) {
        if panel.ignoresMouseEvents != ignore { panel.ignoresMouseEvents = ignore }
    }

    /// Typing, pinned, a button held down, or a feature asking to stay (file picker, live prompter...).
    var keepOpen: Bool {
        if app.notch.pinned || mouseDown || !app.keepOpenReasons.isEmpty { return true }
        return isEditing
    }

    var isEditing: Bool {
        guard panel.isKeyWindow, let r = panel.firstResponder else { return false }
        if r is NSTextView { return true }
        return String(describing: type(of: r)).hasPrefix("WK")
    }

    private func scheduleOpen() {
        guard openWork == nil else { return }
        let w = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.openWork = nil
                if self.hit(self.hotZone, self.pointerLocation) { self.open() }
            }
        }
        openWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, app.prefs.v.hoverDelay), execute: w)
    }

    private func cancelOpen() { openWork?.cancel(); openWork = nil }

    private func scheduleClose() {
        guard closeWork == nil else { return }
        let w = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.closeWork = nil
                if !self.keepOpen, !self.hit(self.interactiveRect, self.pointerLocation) { self.close() }
            }
        }
        closeWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.05, app.prefs.v.closeDelay), execute: w)
    }

    private func cancelClose() { closeWork?.cancel(); closeWork = nil }

    // MARK: Open / close

    func open(_ tab: Tab? = nil) {
        guard let panel else { return }
        cancelOpen()
        cancelClose()
        if let tab { app.select(tab) }
        guard app.notch.mode != .open, !app.notch.hidden else { return }
        if app.notch.alert != nil { app.dismissAlert() }
        panel.allowKey = true
        withAnimation(app.notch.reduceMotion ? Theme.fade : Theme.openSpring) { app.notch.mode = .open }
        if app.prefs.v.hapticFeedback { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
        setIgnoresMouse(!hit(interactiveRect, pointerLocation))
    }

    func close() {
        guard let panel else { return }
        cancelOpen()
        cancelClose()
        guard app.notch.mode != .closed else { return }
        withAnimation(app.notch.reduceMotion ? Theme.fade : Theme.closeSpring) {
            app.notch.mode = .closed
            app.notch.dropTarget = nil
        }
        app.notch.pinned = false
        openedByKeyboard = false
        panel.allowKey = false
        if panel.isKeyWindow {   // hand the keyboard back to the app underneath
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
        setIgnoresMouse(true)
    }

    /// Shortcut: open (on a tab), or close if that tab is already showing. `typing` puts the keyboard in the panel.
    func toggleFromKeyboard(_ tab: Tab?, typing: Bool) {
        guard let panel else { return }
        if app.notch.mode == .open && (tab == nil || tab == app.notch.tab) {
            close()
            return
        }
        let wasOpen = app.notch.mode == .open
        open(tab)
        if !wasOpen { openedByKeyboard = true }
        if typing {
            app.notch.focusSearch = true
            panel.makeKey()
        }
    }

    func toggle(_ tab: Tab? = nil) {
        if app.notch.mode == .open && (tab == nil || tab == app.notch.tab) { close() } else { open(tab) }
    }

    // MARK: Drag and drop

    private func dragMoved(at p: CGPoint) {
        let pb = NSPasteboard(name: .drag)
        guard !app.notch.hidden, pb.changeCount != dragBaseline, !app.dropHandlers.isEmpty,
              DropSupport.canAccept(pb) else { return }
        let near = interactiveRect.insetBy(dx: -110, dy: -70)
        switch app.notch.mode {
        case .closed, .open:
            if hit(near, p) {
                cancelClose()
                panel.allowKey = false
                withAnimation(Theme.openSpring) { app.notch.mode = .drop }
                setIgnoresMouse(false)
            }
        case .drop:
            setIgnoresMouse(!hit(interactiveRect.insetBy(dx: -20, dy: -20), p))
        }
    }

    private func dragEnded() {
        guard app.notch.mode == .drop else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.app.notch.mode == .drop else { return }
                self.app.notch.dropTarget = nil
                self.app.notch.mode = .open
                self.close()
            }
        }
    }

    // MARK: Hiding

    func updateVisibility() {
        guard let panel else { return }
        let p = app.prefs.v
        var hide = false
        if p.hideInFullscreen && frontAppIsFullscreen() { hide = true }
        if p.hideWhileMirroring && geo.displayID != 0 && CGDisplayIsInMirrorSet(geo.displayID) != 0 { hide = true }
        if !geo.real && p.notchlessScreens == "hidden" { hide = true }
        app.notch.transparentClosed = !geo.real && p.notchlessScreens == "transparent"
        guard hide != app.notch.hidden else { return }
        app.notch.hidden = hide
        if hide {
            close()
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// True when the front app has a layer-0 window covering the whole notch screen.
    func frontAppIsFullscreen() -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, pid != getpid(),
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first else { return false }
        let f = geo.screenFrame
        let cg = CGRect(x: f.minX, y: primary.frame.maxY - f.maxY, width: f.width, height: f.height)
        for w in list {
            guard (w[kCGWindowOwnerPID as String] as? Int32) == pid, (w[kCGWindowLayer as String] as? Int) == 0,
                  let d = w[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: d) else { continue }
            if abs(b.minX - cg.minX) < 1, abs(b.minY - cg.minY) < 1, abs(b.width - cg.width) < 1, abs(b.height - cg.height) < 1 { return true }
        }
        return false
    }
}

/// What the notch accepts when something is dragged onto it.
enum DropSupport {
    static let types: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .string, .png, .tiff]

    static func canAccept(_ pb: NSPasteboard) -> Bool {
        guard let available = pb.types else { return false }
        return available.contains(where: types.contains)
    }
}
