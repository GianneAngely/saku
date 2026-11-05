import AppKit

/// The notch on one screen. x values are local to the screen (0 = its left edge); `screenFrame` is global.
struct NotchGeo: Equatable {
    var screenFrame: CGRect
    var notchMinX: Double
    var notchMaxX: Double
    var notchH: Double
    var real: Bool
    var displayID: CGDirectDisplayID = 0

    var notchW: Double { notchMaxX - notchMinX }
    var midX: Double { (notchMinX + notchMaxX) / 2 }

    static let fallback = NotchGeo(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                   notchMinX: 663.5, notchMaxX: 848.5, notchH: 32, real: false)

    /// The built-in notch screen, or (for clamshell / external only) a fake 185x32 notch on the main screen.
    /// `widthOffset` / `heightOffset` are the user's fine-tuning (points, may be negative).
    @MainActor static func detect(widthOffset: Double = 0, heightOffset: Double = 0) -> NotchGeo {
        var g: NotchGeo
        if let s = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
           let left = s.auxiliaryTopLeftArea, let right = s.auxiliaryTopRightArea {
            g = NotchGeo(screenFrame: s.frame, notchMinX: left.width, notchMaxX: right.minX - left.minX,
                         notchH: s.safeAreaInsets.top, real: true, displayID: s.displayID)
        } else {
            let s = NSScreen.main ?? NSScreen.screens.first
            let f = s?.frame ?? fallback.screenFrame
            let menuBar = s.map { $0.frame.maxY - $0.visibleFrame.maxY } ?? 24
            g = NotchGeo(screenFrame: f, notchMinX: f.width / 2 - 92.5, notchMaxX: f.width / 2 + 92.5,
                         notchH: max(24, min(38, menuBar)), real: false, displayID: s?.displayID ?? 0)
        }
        g.notchMinX -= widthOffset / 2
        g.notchMaxX += widthOffset / 2
        g.notchH = max(20, g.notchH + heightOffset)
        return g
    }

    /// A rect hanging from the top edge, centred on the notch, in global AppKit coordinates.
    func topRect(width: Double, height: Double) -> CGRect {
        CGRect(x: screenFrame.minX + midX - width / 2, y: screenFrame.maxY - height, width: width, height: height)
    }

    var globalNotchRect: CGRect { topRect(width: notchW, height: notchH) }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
