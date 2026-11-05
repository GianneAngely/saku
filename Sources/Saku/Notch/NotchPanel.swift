import AppKit
import SwiftUI

/// Borderless, transparent, non-activating panel that sits over the menu bar at the notch.
/// It only becomes key while open, so typing into notes, the browser or the AI box works without
/// pulling Saku to the front.
final class NotchPanel: NSPanel {
    var allowKey = false

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)   // above the menu bar and Dock, below menus
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { allowKey }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }   // stay on the menu bar
}

/// Hosting view that takes the first click even while Saku is in the background.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
